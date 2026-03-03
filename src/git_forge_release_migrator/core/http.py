from __future__ import annotations

import base64
import binascii
import hashlib
import json
import re
import time
from pathlib import Path

from .shell import run_cmd


class HTTPRequestError(RuntimeError):
    pass


class AuthenticationError(HTTPRequestError):
    """Raised when the server returns 401 (unauthorized) or 403 (forbidden, non-rate-limit)."""

    pass


def _curl_base(url: str, *, method: str, headers: dict[str, str] | None = None) -> list[str]:
    cmd = [
        "curl",
        "--silent",
        "--show-error",
        "--location",
        "--fail",
        "--connect-timeout",
        "10",
        "--max-time",
        "90",
        "--request",
        method,
    ]
    for key, value in (headers or {}).items():
        cmd.extend(["--header", f"{key}: {value}"])
    cmd.append(url)
    return cmd


def request_json(
    url: str,
    *,
    method: str = "GET",
    headers: dict[str, str] | None = None,
    json_data: dict | list | None = None,
    retries: int = 3,
    retry_delay: float = 2.0,
) -> dict | list:
    final_headers = dict(headers or {})
    body = None
    if json_data is not None:
        final_headers["Content-Type"] = "application/json"
        body = json.dumps(json_data, ensure_ascii=True)

    last_error = ""
    for attempt in range(1, retries + 1):
        cmd = _curl_base(url, method=method, headers=final_headers)
        if body is not None:
            cmd = cmd[:-1] + ["--data", body, cmd[-1]]

        proc = run_cmd(cmd, check=False)
        if proc.returncode == 0:
            text = (proc.stdout or "").strip()
            if not text:
                return {}
            try:
                return json.loads(text)
            except json.JSONDecodeError as exc:
                raise HTTPRequestError(f"Invalid JSON from {url}: {text[:300]}") from exc

        last_error = (proc.stderr or proc.stdout or "").strip()

        # Detect auth failures immediately — no point retrying these
        _err_lower = last_error.lower()
        if "401" in last_error:
            raise AuthenticationError(f"Authentication failed (401) for {url}: {last_error}")
        if "403" in last_error and "rate" not in _err_lower and "ratelimit" not in _err_lower:
            raise AuthenticationError(f"Authorization denied (403) for {url}: {last_error}")

        if attempt < retries:
            time.sleep(retry_delay)

    raise HTTPRequestError(last_error or f"HTTP JSON request failed for {url}")


def request_status(url: str, *, headers: dict[str, str] | None = None) -> int:
    cmd = [
        "curl",
        "--silent",
        "--show-error",
        "--location",
        "--output",
        "/dev/null",
        "--write-out",
        "%{http_code}",
    ]
    for key, value in (headers or {}).items():
        cmd.extend(["--header", f"{key}: {value}"])
    cmd.append(url)

    proc = run_cmd(cmd, check=False)
    text = (proc.stdout or "").strip()
    try:
        return int(text)
    except ValueError:
        return 0


def download_file(
    url: str,
    destination: str,
    *,
    headers: dict[str, str] | None = None,
    retries: int = 3,
    backoff_seconds: float = 0.75,
) -> bool:
    dest = Path(destination)
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists():
        dest.unlink(missing_ok=True)
    headers_path = dest.parent / f".{dest.name}.headers"
    headers_path.unlink(missing_ok=True)

    delay = backoff_seconds
    for attempt in range(1, retries + 1):
        cmd = [
            "curl",
            "--silent",
            "--show-error",
            "--location",
            "--dump-header",
            str(headers_path),
            "--output",
            str(dest),
            "--write-out",
            "%{http_code}",
            "--connect-timeout",
            "10",
            "--max-time",
            "180",
        ]
        for key, value in (headers or {}).items():
            cmd.extend(["--header", f"{key}: {value}"])
        cmd.append(url)

        proc = run_cmd(cmd, check=False)
        status_text = (proc.stdout or "").strip()
        try:
            status_code = int(status_text)
        except ValueError:
            status_code = 0

        if proc.returncode == 0 and 200 <= status_code < 400:
            if not _validate_download_integrity(dest, headers_path):
                dest.unlink(missing_ok=True)
                if attempt < retries:
                    time.sleep(delay)
                    delay = min(delay * 2, 5)
                    continue
                headers_path.unlink(missing_ok=True)
                return False
            headers_path.unlink(missing_ok=True)
            return True

        dest.unlink(missing_ok=True)
        if status_code in {401, 404}:
            headers_path.unlink(missing_ok=True)
            return False

        retry_after = _read_header_last_int(headers_path, "Retry-After")
        rate_remaining = _read_header_last_int(headers_path, "X-RateLimit-Remaining")
        rate_reset = _read_header_last_int(headers_path, "X-RateLimit-Reset")
        is_rate_limited = status_code == 429 or (
            status_code == 403 and (retry_after is not None or rate_remaining == 0)
        )

        if status_code == 403 and not is_rate_limited:
            headers_path.unlink(missing_ok=True)
            return False

        if attempt < retries:
            wait_for = delay
            if retry_after is not None and retry_after > 0:
                wait_for = max(wait_for, float(retry_after))
            elif rate_remaining == 0 and rate_reset is not None and rate_reset > 0:
                wait_for = max(wait_for, float(max(1, rate_reset - int(time.time()))))
            elif is_rate_limited:
                wait_for = max(wait_for, min(delay * 2, 15))

            time.sleep(wait_for)
            delay = min(delay * 2, 5)

    headers_path.unlink(missing_ok=True)
    return False


def _validate_download_integrity(dest: Path, headers_path: Path) -> bool:
    if not dest.exists() or not dest.is_file():
        return False

    content_len = _read_header_last_int(headers_path, "Content-Length")
    if content_len is not None and content_len >= 0 and dest.stat().st_size != content_len:
        return False

    expected_sha256 = _extract_expected_sha256(headers_path)
    if expected_sha256:
        digest = hashlib.sha256()
        with dest.open("rb") as f:
            while True:
                chunk = f.read(1024 * 1024)
                if not chunk:
                    break
                digest.update(chunk)
        if digest.hexdigest().lower() != expected_sha256:
            return False

    return True


def _extract_expected_sha256(headers_path: Path) -> str:
    x_checksum = _read_header_last_str(headers_path, "X-Checksum-Sha256")
    normalized = _normalize_sha256_hex(x_checksum)
    if normalized:
        return normalized

    digest_header = _read_header_last_str(headers_path, "Digest")
    if digest_header:
        # RFC 3230 style: Digest: sha-256=<base64>
        m = re.search(r"sha-256=([^,\s]+)", digest_header, flags=re.IGNORECASE)
        if m:
            token = m.group(1).strip().strip('"')
            normalized = _normalize_sha256_hex(token)
            if normalized:
                return normalized
            try:
                decoded = base64.b64decode(token, validate=True)
                if len(decoded) == 32:
                    return decoded.hex()
            except (binascii.Error, ValueError):
                pass

    etag = _read_header_last_str(headers_path, "ETag")
    if etag:
        normalized = _normalize_sha256_hex(etag.strip("W/").strip('"'))
        if normalized:
            return normalized

    return ""


def _normalize_sha256_hex(value: str | None) -> str:
    if not value:
        return ""
    token = value.strip().lower().strip('"')
    if len(token) == 64 and all(c in "0123456789abcdef" for c in token):
        return token
    return ""


def add_query_param(url: str, key: str, value: str) -> str:
    separator = "&" if "?" in url else "?"
    return f"{url}{separator}{key}={value}"


def _read_header_last_int(headers_path: Path, header_name: str) -> int | None:
    raw = _read_header_last_str(headers_path, header_name)
    if raw is None:
        return None
    try:
        return int(raw)
    except ValueError:
        return None


def _read_header_last_str(headers_path: Path, header_name: str) -> str | None:
    if not headers_path.exists():
        return None
    name = header_name.lower()
    last_value: str | None = None
    for raw_line in headers_path.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = raw_line.strip()
        if not line or ":" not in line:
            continue
        key, value = line.split(":", 1)
        if key.strip().lower() == name:
            last_value = value.strip()
    return last_value
