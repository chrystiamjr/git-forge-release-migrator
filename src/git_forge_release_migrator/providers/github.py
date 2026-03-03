from __future__ import annotations

import re

from ..core.http import download_file
from ..core.shell import run_cmd, run_json
from .base import ProviderAdapter, ProviderRef


class GitHubAdapter(ProviderAdapter):
    name = "github"

    def parse_url(self, url: str) -> ProviderRef:
        if not url:
            raise ValueError("Invalid GitHub URL: empty value")
        clean = str(url).strip().removesuffix(".git")
        clean = clean.split("?", 1)[0].split("#", 1)[0]

        m = re.match(r"^git@([^:]+):(.+)$", clean)
        if m:
            host = m.group(1)
            path = m.group(2)
            base_url = f"https://{host}"
        else:
            m = re.match(r"^https?://([^/]+)/(.+)$", clean)
            if not m:
                raise ValueError(f"Invalid GitHub URL: {url}")
            host = m.group(1)
            path = m.group(2)
            base_url = f"https://{host}"

        path = path.lstrip("/")
        path = path.split("/-/", 1)[0]
        parts = path.split("/")
        if len(parts) < 2:
            raise ValueError(f"Invalid GitHub repository path: {url}")

        owner = parts[0]
        repo = parts[1]
        resource = f"{owner}/{repo}"
        repo_ref = resource if host == "github.com" else f"{host}/{resource}"

        return ProviderRef(
            provider=self.name,
            raw_url=url,
            base_url=base_url,
            host=host,
            resource=resource,
            metadata={"owner": owner, "repo": repo, "repo_ref": repo_ref},
        )

    def _gh_env(self, token: str) -> dict[str, str]:
        return {"GH_TOKEN": token}

    def gh_api_json(self, token: str, path: str) -> dict | list:
        return run_json(["gh", "api", path], env=self._gh_env(token))

    def list_releases(self, ref: ProviderRef, token: str) -> list[dict]:
        releases: list[dict] = []
        page = 1
        while True:
            payload = self.gh_api_json(token, f"repos/{ref.resource}/releases?per_page=100&page={page}")
            if not isinstance(payload, list) or not payload:
                break
            releases.extend([item for item in payload if isinstance(item, dict)])
            if len(payload) < 100:
                break
            page += 1
        return releases

    def list_release_tags(self, ref: ProviderRef, token: str) -> list[str]:
        return [str(item.get("tag_name", "")) for item in self.list_releases(ref, token) if item.get("tag_name")]

    def list_tags(self, ref: ProviderRef, token: str) -> list[str]:
        payload = self.gh_api_json(token, f"repos/{ref.resource}/git/matching-refs/tags/")
        if not isinstance(payload, list):
            return []
        tags: list[str] = []
        for item in payload:
            if not isinstance(item, dict):
                continue
            raw = str(item.get("ref", ""))
            if raw.startswith("refs/tags/"):
                tags.append(raw.removeprefix("refs/tags/"))
        return tags

    def release_by_tag(self, ref: ProviderRef, token: str, tag: str) -> dict | None:
        try:
            payload = self.gh_api_json(token, f"repos/{ref.resource}/releases/tags/{tag}")
            if isinstance(payload, dict):
                return payload
            return None
        except Exception:  # noqa: BLE001
            return None

    def tag_exists(self, ref: ProviderRef, token: str, tag: str) -> bool:
        try:
            self.gh_api_json(token, f"repos/{ref.resource}/git/ref/tags/{tag}")
            return True
        except Exception:  # noqa: BLE001
            return False

    def create_tag_ref(self, ref: ProviderRef, token: str, tag: str, sha: str) -> None:
        run_cmd(
            [
                "gh",
                "api",
                "-X",
                "POST",
                f"repos/{ref.resource}/git/refs",
                "-f",
                f"ref=refs/tags/{tag}",
                "-f",
                f"sha={sha}",
            ],
            env=self._gh_env(token),
        )

    def commit_sha_for_ref(self, ref: ProviderRef, token: str, ref_name: str) -> str:
        payload = self.gh_api_json(token, f"repos/{ref.resource}/commits/{ref_name}")
        if not isinstance(payload, dict) or not payload.get("sha"):
            raise RuntimeError(f"Commit SHA not found for ref '{ref_name}' in GitHub")
        return str(payload["sha"])

    def release_create(self, ref: ProviderRef, token: str, tag: str, title: str, notes_file: str) -> None:
        run_cmd(
            [
                "gh",
                "release",
                "create",
                tag,
                "-R",
                ref.resource,
                "--title",
                title,
                "--notes-file",
                notes_file,
                "--verify-tag",
            ],
            env=self._gh_env(token),
        )

    def release_upload(self, ref: ProviderRef, token: str, tag: str, assets: list[str]) -> None:
        if not assets:
            return
        cmd = ["gh", "release", "upload", tag, "-R", ref.resource, "--clobber", *assets]
        run_cmd(cmd, env=self._gh_env(token))

    def release_edit(self, ref: ProviderRef, token: str, tag: str, title: str, notes_file: str) -> None:
        run_cmd(
            [
                "gh",
                "release",
                "edit",
                tag,
                "-R",
                ref.resource,
                "--title",
                title,
                "--notes-file",
                notes_file,
            ],
            env=self._gh_env(token),
        )

    def download_with_token(self, token: str, url: str, destination: str) -> bool:
        return download_file(
            url,
            destination,
            headers={
                "Authorization": f"Bearer {token}",
                "Accept": "application/octet-stream",
            },
            retries=3,
            backoff_seconds=0.75,
        )

    def build_tag_url(self, ref: ProviderRef, tag: str) -> str:
        return f"{ref.base_url.rstrip('/')}/{ref.resource}/releases/tag/{tag}"

    def to_canonical_release(self, release_payload: dict) -> dict:
        tag_name = str(release_payload.get("tag_name", ""))
        assets = release_payload.get("assets", [])
        if not isinstance(assets, list):
            assets = []

        links = []
        for asset in assets:
            if not isinstance(asset, dict):
                continue
            links.append(
                {
                    "name": str(asset.get("name", "")),
                    "url": str(asset.get("browser_download_url", "")),
                    "direct_url": str(asset.get("browser_download_url", "")),
                    "type": "package",
                }
            )

        sources = []
        zip_url = str(release_payload.get("zipball_url", ""))
        tar_url = str(release_payload.get("tarball_url", ""))
        if zip_url:
            sources.append({"format": "zip", "url": zip_url, "name": f"{tag_name or 'release'}-source.zip"})
        if tar_url:
            sources.append({"format": "tar.gz", "url": tar_url, "name": f"{tag_name or 'release'}-source.tar.gz"})

        return {
            "tag_name": tag_name,
            "name": str(release_payload.get("name") or tag_name),
            "description_markdown": str(release_payload.get("body", "")),
            "commit_sha": str(release_payload.get("target_commitish", "")),
            "assets": {"links": links, "sources": sources},
        }
