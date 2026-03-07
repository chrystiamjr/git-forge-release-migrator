from __future__ import annotations

import hashlib
import json
import re
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import quote

from ..core.http import download_file, request_json, request_status
from ..core.shell import run_cmd
from .base import ProviderAdapter, ProviderRef


class BitbucketAdapter(ProviderAdapter):
    name = "bitbucket"
    _API_BASE = "https://api.bitbucket.org/2.0"

    def _headers(self, token: str) -> dict[str, str]:
        return {"Authorization": f"Bearer {token}"}

    def _repo_api_url(self, ref: ProviderRef, suffix: str) -> str:
        workspace = quote(ref.metadata.get("workspace", ""), safe="")
        repo = quote(ref.metadata.get("repo", ""), safe="")
        return f"{self._API_BASE}/repositories/{workspace}/{repo}{suffix}"

    def _paginated_values(self, start_url: str, token: str) -> list[dict]:
        values: list[dict] = []
        next_url = start_url
        while next_url:
            payload = request_json(next_url, headers=self._headers(token), retries=3, retry_delay=2)
            if not isinstance(payload, dict):
                break
            page_values = payload.get("values", [])
            if isinstance(page_values, list):
                values.extend([item for item in page_values if isinstance(item, dict)])
            next_raw = payload.get("next", "")
            next_url = str(next_raw) if next_raw else ""
        return values

    def _manifest_filename(self, tag: str) -> str:
        safe_tag = re.sub(r"[^a-zA-Z0-9._-]+", "-", tag).strip("-") or "tag"
        return f".gfrm-release-{safe_tag}.json"

    def _download_url_from_item(self, item: dict) -> str:
        links = item.get("links", {}) if isinstance(item.get("links"), dict) else {}
        download = links.get("download", {}) if isinstance(links.get("download"), dict) else {}
        href = str(download.get("href", ""))
        if href:
            return href
        self_link = links.get("self", {}) if isinstance(links.get("self"), dict) else {}
        return str(self_link.get("href", ""))

    def download_url(self, item: dict) -> str:
        return self._download_url_from_item(item)

    def parse_url(self, url: str) -> ProviderRef:
        if not url:
            raise ValueError("Invalid Bitbucket URL: empty value")
        clean = str(url).strip().removesuffix(".git")
        clean = clean.split("?", 1)[0].split("#", 1)[0]

        workspace = ""
        repo = ""
        m = re.match(r"^git@([^:]+):([^/]+)/([^/]+)$", clean)
        if m:
            host = m.group(1)
            workspace = m.group(2)
            repo = m.group(3)
            base_url = f"https://{host}"
        else:
            m = re.match(r"^https?://([^/]+)/(.+)$", clean)
            if not m:
                raise ValueError(f"Invalid Bitbucket URL: {url}")
            host = m.group(1)
            path = m.group(2)
            base_url = f"https://{host}"

            project_path = path.lstrip("/").split("/-/", 1)[0]
            parts = [part for part in project_path.split("/") if part]
            if len(parts) < 2:
                raise ValueError(f"Invalid Bitbucket repository path: {url}")
            workspace = parts[0]
            repo = parts[1]

        if m and not repo:
            path = path.split("?", 1)[0].split("#", 1)[0]
            parts = [part for part in path.split("/") if part]
            if len(parts) < 2:
                raise ValueError(f"Invalid Bitbucket repository path: {url}")
            workspace = parts[0]
            repo = parts[1]

        if host != "bitbucket.org" or not workspace or not repo:
            raise ValueError("Only Bitbucket Cloud URLs are supported in this phase")

        workspace_encoded = quote(workspace, safe="")
        repo_encoded = quote(repo, safe="")

        return ProviderRef(
            provider=self.name,
            raw_url=url,
            base_url=base_url,
            host=host,
            resource=f"{workspace}/{repo}",
            metadata={
                "workspace": workspace,
                "repo": repo,
                "workspace_encoded": workspace_encoded,
                "repo_encoded": repo_encoded,
                "repo_ref": f"{workspace}/{repo}",
            },
        )

    def build_tag_url(self, ref: ProviderRef, tag: str) -> str:
        workspace = ref.metadata.get("workspace", "")
        repo = ref.metadata.get("repo", "")
        return f"{ref.base_url.rstrip('/')}/{workspace}/{repo}/src/{tag}"

    def list_tags(self, ref: ProviderRef, token: str) -> list[str]:
        payload = self._paginated_values(self._repo_api_url(ref, "/refs/tags?pagelen=100"), token)
        tags: list[str] = []
        for item in payload:
            name = str(item.get("name", "")).strip()
            if name:
                tags.append(name)
        return tags

    def list_tags_payload(self, ref: ProviderRef, token: str) -> list[dict]:
        return self._paginated_values(self._repo_api_url(ref, "/refs/tags?pagelen=100"), token)

    def tag_exists(self, ref: ProviderRef, token: str, tag: str) -> bool:
        status = request_status(
            self._repo_api_url(ref, f"/refs/tags/{quote(tag, safe='')}"),
            headers=self._headers(token),
        )
        return status == 200

    def tag_commit_sha(self, ref: ProviderRef, token: str, tag: str) -> str:
        payload = request_json(
            self._repo_api_url(ref, f"/refs/tags/{quote(tag, safe='')}"),
            headers=self._headers(token),
            retries=3,
            retry_delay=2,
        )
        if not isinstance(payload, dict):
            return ""
        target = payload.get("target", {}) if isinstance(payload.get("target"), dict) else {}
        return str(target.get("hash", ""))

    def create_tag(self, ref: ProviderRef, token: str, tag: str, ref_sha: str, message: str = "") -> None:
        payload = {
            "name": tag,
            "target": {"hash": ref_sha},
        }
        if message:
            payload["message"] = message
        request_json(
            self._repo_api_url(ref, "/refs/tags"),
            method="POST",
            headers=self._headers(token),
            json_data=payload,
            retries=3,
            retry_delay=2,
        )

    def list_downloads(self, ref: ProviderRef, token: str) -> list[dict]:
        return self._paginated_values(self._repo_api_url(ref, "/downloads?pagelen=100"), token)

    def delete_download(self, ref: ProviderRef, token: str, name: str) -> None:
        request_json(
            self._repo_api_url(ref, f"/downloads/{quote(name, safe='')}"),
            method="DELETE",
            headers=self._headers(token),
            retries=3,
            retry_delay=1,
        )

    def upload_download(self, ref: ProviderRef, token: str, filepath: str) -> dict:
        proc = run_cmd(
            [
                "curl",
                "--silent",
                "--show-error",
                "--fail",
                "--location",
                "--header",
                f"Authorization: Bearer {token}",
                "--form",
                f"files=@{filepath}",
                self._repo_api_url(ref, "/downloads"),
            ]
        )
        payload = json.loads((proc.stdout or "{}").strip() or "{}")
        if not isinstance(payload, dict):
            raise RuntimeError("Bitbucket downloads upload returned invalid payload")
        return payload

    def replace_download(self, ref: ProviderRef, token: str, filepath: str, *, upload_name: str = "") -> dict:
        target_name = upload_name or Path(filepath).name
        existing = None
        for item in self.list_downloads(ref, token):
            if str(item.get("name", "")) == target_name:
                existing = item
                break
        if existing is not None:
            self.delete_download(ref, token, target_name)
        return self.upload_download(ref, token, filepath)

    def download_with_auth(self, token: str, url: str, destination: str) -> bool:
        return download_file(
            url,
            destination,
            headers=self._headers(token),
            retries=3,
            backoff_seconds=0.75,
        )

    def find_download_by_name(self, ref: ProviderRef, token: str, name: str) -> dict | None:
        for item in self.list_downloads(ref, token):
            if str(item.get("name", "")) == name:
                return item
        return None

    def read_release_manifest(self, ref: ProviderRef, token: str, tag: str) -> dict | None:
        manifest_name = self._manifest_filename(tag)
        item = self.find_download_by_name(ref, token, manifest_name)
        if not isinstance(item, dict):
            return None
        manifest_url = self._download_url_from_item(item)
        if not manifest_url:
            return None
        try:
            payload = request_json(manifest_url, headers=self._headers(token), retries=3, retry_delay=1)
        except Exception:  # noqa: BLE001
            return None
        return payload if isinstance(payload, dict) else None

    def write_release_manifest(self, ref: ProviderRef, token: str, tag: str, manifest: dict) -> None:
        manifest_name = self._manifest_filename(tag)
        with tempfile.TemporaryDirectory(prefix="gfrm-bb-manifest-") as tmp:
            manifest_path = Path(tmp) / manifest_name
            manifest_path.write_text(json.dumps(manifest, ensure_ascii=True, indent=2) + "\n", encoding="utf-8")
            self.replace_download(ref, token, str(manifest_path), upload_name=manifest_name)

    def build_release_manifest(
        self,
        *,
        tag: str,
        release_name: str,
        notes: str,
        uploaded_assets: list[dict],
        missing_assets: list[dict],
    ) -> dict:
        notes_hash = hashlib.sha256((notes or "").encode("utf-8")).hexdigest()
        return {
            "version": 1,
            "tag_name": tag,
            "release_name": release_name or tag,
            "notes_hash": notes_hash,
            "uploaded_assets": uploaded_assets,
            "missing_assets": missing_assets,
            "updated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        }

    def manifest_is_complete(self, manifest: dict | None) -> bool:
        if not isinstance(manifest, dict):
            return False
        uploaded = manifest.get("uploaded_assets")
        missing = manifest.get("missing_assets")
        if not isinstance(uploaded, list) or not isinstance(missing, list):
            return False
        return len(missing) == 0

    def list_releases(self, ref: ProviderRef, token: str) -> list[dict]:
        tags_payload = self.list_tags_payload(ref, token)
        downloads = self.list_downloads(ref, token)
        downloads_by_name: dict[str, dict] = {}
        for item in downloads:
            name = str(item.get("name", "")).strip()
            if name:
                downloads_by_name[name] = item

        releases: list[dict] = []
        for tag_payload in tags_payload:
            tag = str(tag_payload.get("name", "")).strip()
            if not tag:
                continue
            manifest_name = self._manifest_filename(tag)
            manifest = None
            manifest_item = downloads_by_name.get(manifest_name)
            if isinstance(manifest_item, dict):
                manifest_url = self._download_url_from_item(manifest_item)
                if manifest_url:
                    try:
                        payload = request_json(manifest_url, headers=self._headers(token), retries=3, retry_delay=1)
                        if isinstance(payload, dict):
                            manifest = payload
                    except Exception:  # noqa: BLE001
                        manifest = None

            target = tag_payload.get("target", {}) if isinstance(tag_payload.get("target"), dict) else {}
            commit_hash = str(target.get("hash", ""))
            notes = str(tag_payload.get("message", ""))
            release_name = tag
            links: list[dict] = []
            if isinstance(manifest, dict):
                release_name = str(manifest.get("release_name", "") or tag)
                uploaded_assets = manifest.get("uploaded_assets", [])
                if isinstance(uploaded_assets, list):
                    for item in uploaded_assets:
                        if not isinstance(item, dict):
                            continue
                        name = str(item.get("name", "")).strip()
                        url = str(item.get("url", "")).strip()
                        if not name or not url:
                            continue
                        links.append(
                            {
                                "name": name,
                                "url": url,
                                "direct_url": url,
                                "type": str(item.get("type", "package") or "package"),
                            }
                        )

            releases.append(
                {
                    "tag_name": tag,
                    "name": release_name,
                    "description_markdown": notes,
                    "commit_sha": commit_hash,
                    "assets": {"links": links, "sources": []},
                    "provider_metadata": {
                        "manifest_found": isinstance(manifest, dict),
                        "legacy_no_manifest": not isinstance(manifest, dict),
                        "manifest": manifest if isinstance(manifest, dict) else {},
                    },
                }
            )
        return releases

    def to_canonical_release(self, release_payload: dict) -> dict:
        tag_name = str(release_payload.get("tag_name", ""))

        if "description_markdown" in release_payload:
            assets_payload = release_payload.get("assets", {})
            assets = assets_payload if isinstance(assets_payload, dict) else {}
            links = assets.get("links", []) if isinstance(assets.get("links"), list) else []
            sources = assets.get("sources", []) if isinstance(assets.get("sources"), list) else []
            metadata_payload = release_payload.get("provider_metadata", {})
            metadata = metadata_payload if isinstance(metadata_payload, dict) else {}
            return {
                "tag_name": tag_name,
                "name": str(release_payload.get("name") or tag_name),
                "description_markdown": str(release_payload.get("description_markdown", "")),
                "commit_sha": str(release_payload.get("commit_sha", "")),
                "assets": {"links": links, "sources": sources},
                "provider_metadata": metadata,
            }

        target = release_payload.get("target", {}) if isinstance(release_payload.get("target"), dict) else {}
        return {
            "tag_name": tag_name,
            "name": str(release_payload.get("name") or tag_name),
            "description_markdown": str(release_payload.get("message", "")),
            "commit_sha": str(target.get("hash", "")),
            "assets": {"links": [], "sources": []},
            "provider_metadata": {"manifest_found": False, "legacy_no_manifest": True, "manifest": {}},
        }
