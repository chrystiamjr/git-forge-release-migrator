from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from git_forge_release_migrator.core.http import download_file


class _Proc:
    def __init__(self, *, returncode: int, stdout: str = "", stderr: str = "") -> None:
        self.returncode = returncode
        self.stdout = stdout
        self.stderr = stderr


class HTTPDownloadIntegrityTests(unittest.TestCase):
    def _fake_curl(self, *, payload: bytes, headers_text: str):
        def _runner(cmd: list[str], check: bool = False):
            del check
            dump_header_idx = cmd.index("--dump-header") + 1
            output_idx = cmd.index("--output") + 1
            headers_path = Path(cmd[dump_header_idx])
            output_path = Path(cmd[output_idx])
            headers_path.write_text(headers_text, encoding="utf-8")
            output_path.write_bytes(payload)
            return _Proc(returncode=0, stdout="200")

        return _runner

    def test_download_fails_when_content_length_mismatch(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            destination = Path(tmp) / "asset.bin"
            fake = self._fake_curl(payload=b"abc", headers_text="HTTP/1.1 200 OK\nContent-Length: 10\n")
            with patch("git_forge_release_migrator.core.http.run_cmd", side_effect=fake):
                ok = download_file("https://example.com/asset", str(destination), retries=1)
            self.assertFalse(ok)

    def test_download_succeeds_when_content_length_matches(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            destination = Path(tmp) / "asset.bin"
            fake = self._fake_curl(payload=b"abcd", headers_text="HTTP/1.1 200 OK\nContent-Length: 4\n")
            with patch("git_forge_release_migrator.core.http.run_cmd", side_effect=fake):
                ok = download_file("https://example.com/asset", str(destination), retries=1)
            self.assertTrue(ok)
            self.assertTrue(destination.exists())

    def test_download_fails_when_checksum_mismatch(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            destination = Path(tmp) / "asset.bin"
            sha = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
            fake = self._fake_curl(
                payload=b"abcdef",
                headers_text=(f"HTTP/1.1 200 OK\nContent-Length: 6\nX-Checksum-Sha256: {sha}\n"),
            )
            with patch("git_forge_release_migrator.core.http.run_cmd", side_effect=fake):
                ok = download_file("https://example.com/asset", str(destination), retries=1)
            self.assertFalse(ok)


if __name__ == "__main__":
    unittest.main()
