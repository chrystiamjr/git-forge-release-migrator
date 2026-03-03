from __future__ import annotations

import json
import re
from urllib.parse import quote

from ..core.http import add_query_param, download_file, request_json, request_status
from ..core.shell import run_cmd
from .base import ProviderAdapter, ProviderRef


class GitLabAdapter(ProviderAdapter):
    name = "gitlab"

    def parse_url(self, url: str) -> ProviderRef:
        if not url:
            raise ValueError("Invalid GitLab URL: empty value")
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
                raise ValueError(f"Invalid GitLab URL: {url}")
            host = m.group(1)
            path = m.group(2)
            base_url = f"https://{host}"

        project_path = path.lstrip("/").split("/-/", 1)[0]
        if not project_path:
            raise ValueError(f"Invalid GitLab project path: {url}")

        return ProviderRef(
            provider=self.name,
            raw_url=url,
            base_url=base_url,
            host=host,
            resource=project_path,
            metadata={"project_path": project_path, "project_encoded": quote(project_path, safe="")},
        )

    def _headers(self, token: str) -> dict[str, str]:
        return {"PRIVATE-TOKEN": token}

    def _project_encoded(self, ref: ProviderRef) -> str:
        return ref.metadata.get("project_encoded") or quote(ref.resource, safe="")

    def normalize_url(self, ref: ProviderRef, url: str) -> str:
        if url.startswith("http://") or url.startswith("https://"):
            return url
        if url.startswith("/"):
            return f"{ref.base_url.rstrip('/')}{url}"
        return f"{ref.base_url.rstrip('/')}/{url}"

    def list_releases(self, ref: ProviderRef, token: str) -> list[dict]:
        project = self._project_encoded(ref)
        page = 1
        releases: list[dict] = []
        while True:
            url = f"{ref.base_url.rstrip('/')}/api/v4/projects/{project}/releases?per_page=100&page={page}"
            payload = request_json(url, headers=self._headers(token), retries=3, retry_delay=2)
            if not isinstance(payload, list) or not payload:
                break
            releases.extend([item for item in payload if isinstance(item, dict)])
            if len(payload) < 100:
                break
            page += 1
        return releases

    def list_tags(self, ref: ProviderRef, token: str) -> list[str]:
        project = self._project_encoded(ref)
        page = 1
        tags: list[str] = []
        while True:
            url = f"{ref.base_url.rstrip('/')}/api/v4/projects/{project}/repository/tags?per_page=100&page={page}"
            payload = request_json(url, headers=self._headers(token), retries=3, retry_delay=2)
            if not isinstance(payload, list) or not payload:
                break
            for item in payload:
                if isinstance(item, dict) and item.get("name"):
                    tags.append(str(item["name"]))
            if len(payload) < 100:
                break
            page += 1
        return tags

    def tag_exists(self, ref: ProviderRef, token: str, tag: str) -> bool:
        project = self._project_encoded(ref)
        url = f"{ref.base_url.rstrip('/')}/api/v4/projects/{project}/repository/tags/{quote(tag, safe='')}"
        return request_status(url, headers=self._headers(token)) == 200

    def tag_commit_sha(self, ref: ProviderRef, token: str, tag: str) -> str:
        project = self._project_encoded(ref)
        url = f"{ref.base_url.rstrip('/')}/api/v4/projects/{project}/repository/tags/{quote(tag, safe='')}"
        payload = request_json(url, headers=self._headers(token), retries=3, retry_delay=2)
        if not isinstance(payload, dict):
            return ""
        return str(payload.get("target", ""))

    def create_tag(self, ref: ProviderRef, token: str, tag: str, ref_sha: str) -> None:
        project = self._project_encoded(ref)
        run_cmd(
            [
                "curl",
                "--silent",
                "--show-error",
                "--fail",
                "--location",
                "--request",
                "POST",
                "--header",
                f"PRIVATE-TOKEN: {token}",
                "--data-urlencode",
                f"tag_name={tag}",
                "--data-urlencode",
                f"ref={ref_sha}",
                f"{ref.base_url.rstrip('/')}/api/v4/projects/{project}/repository/tags",
            ]
        )

    def release_exists(self, ref: ProviderRef, token: str, tag: str) -> bool:
        project = self._project_encoded(ref)
        url = f"{ref.base_url.rstrip('/')}/api/v4/projects/{project}/releases/{quote(tag, safe='')}"
        return request_status(url, headers=self._headers(token)) == 200

    def release_by_tag(self, ref: ProviderRef, token: str, tag: str) -> dict | None:
        project = self._project_encoded(ref)
        url = f"{ref.base_url.rstrip('/')}/api/v4/projects/{project}/releases/{quote(tag, safe='')}"
        try:
            payload = request_json(url, headers=self._headers(token), retries=3, retry_delay=2)
            return payload if isinstance(payload, dict) else None
        except Exception:  # noqa: BLE001
            return None

    def create_or_update_release(
        self, ref: ProviderRef, token: str, tag: str, name: str, description: str, links: list[dict]
    ) -> None:
        project = self._project_encoded(ref)
        exists = self.release_exists(ref, token, tag)

        if exists:
            method = "PUT"
            url = f"{ref.base_url.rstrip('/')}/api/v4/projects/{project}/releases/{quote(tag, safe='')}"
            payload = {"name": name, "description": description, "assets": {"links": links}}
        else:
            method = "POST"
            url = f"{ref.base_url.rstrip('/')}/api/v4/projects/{project}/releases"
            payload = {"tag_name": tag, "name": name, "description": description, "assets": {"links": links}}

        request_json(url, method=method, headers=self._headers(token), json_data=payload, retries=3, retry_delay=2)

    def upload_file(self, ref: ProviderRef, token: str, filepath: str) -> str:
        project = self._project_encoded(ref)
        proc = run_cmd(
            [
                "curl",
                "--silent",
                "--show-error",
                "--fail",
                "--location",
                "--header",
                f"PRIVATE-TOKEN: {token}",
                "--form",
                f"file=@{filepath}",
                f"{ref.base_url.rstrip('/')}/api/v4/projects/{project}/uploads",
            ]
        )
        payload = json.loads(proc.stdout or "{}")
        rel_url = str(payload.get("url", ""))
        if not rel_url:
            raise RuntimeError("GitLab upload did not return URL")
        return f"{ref.base_url.rstrip('/')}{rel_url}"

    def build_release_download_api_url(self, ref: ProviderRef, tag: str, resolved_url: str) -> str | None:
        marker = f"/-/releases/{tag}/downloads/"
        if marker not in resolved_url:
            return None
        asset_path = resolved_url.split(marker, 1)[1].split("?", 1)[0]
        if not asset_path:
            return None
        project = self._project_encoded(ref)
        return (
            f"{ref.base_url.rstrip('/')}/api/v4/projects/{project}"
            f"/releases/{quote(tag, safe='')}/downloads/{asset_path}"
        )

    def build_project_upload_api_url(self, ref: ProviderRef, resolved_url: str) -> str | None:
        marker = "/uploads/"
        if marker not in resolved_url:
            return None

        after = resolved_url.split(marker, 1)[1].split("?", 1)[0]
        if "/" not in after:
            return None
        secret, name = after.split("/", 1)
        if not secret or not name:
            return None

        project = self._project_encoded(ref)
        return f"{ref.base_url.rstrip('/')}/api/v4/projects/{project}/uploads/{secret}/{quote(name, safe='')}"

    def build_repository_archive_api_url(self, ref: ProviderRef, tag: str, fmt: str) -> str:
        project = self._project_encoded(ref)
        return (
            f"{ref.base_url.rstrip('/')}/api/v4/projects/{project}/repository/archive.{fmt}?sha={quote(tag, safe='')}"
        )

    def build_tag_url(self, ref: ProviderRef, tag: str) -> str:
        return f"{ref.base_url.rstrip('/')}/{ref.resource}/-/tags/{tag}"

    def add_private_token_query(self, url: str, token: str) -> str:
        return add_query_param(url, "private_token", token)

    def download_with_auth(self, token: str, url: str, destination: str) -> bool:
        return download_file(url, destination, headers=self._headers(token), retries=3, backoff_seconds=0.75)

    def download_no_auth(self, url: str, destination: str) -> bool:
        return download_file(url, destination, headers=None, retries=3, backoff_seconds=0.75)

    def to_canonical_release(self, release_payload: dict) -> dict:
        assets = release_payload.get("assets", {}) if isinstance(release_payload.get("assets"), dict) else {}

        links_payload = assets.get("links", []) if isinstance(assets.get("links"), list) else []
        links = []
        for link in links_payload:
            if not isinstance(link, dict):
                continue
            links.append(
                {
                    "name": str(link.get("name", "")),
                    "url": str(link.get("url", "")),
                    "direct_url": str(link.get("direct_asset_url", "")),
                    "type": str(link.get("link_type", "other")),
                }
            )

        sources_payload = assets.get("sources", []) if isinstance(assets.get("sources"), list) else []
        sources = []
        for source in sources_payload:
            if not isinstance(source, dict):
                continue
            source_url = str(source.get("url", ""))
            name = source_url.split("?", 1)[0].split("/")[-1] if source_url else ""
            sources.append(
                {
                    "format": str(source.get("format", "source")),
                    "url": source_url,
                    "name": name,
                }
            )

        commit = release_payload.get("commit", {}) if isinstance(release_payload.get("commit"), dict) else {}

        return {
            "tag_name": str(release_payload.get("tag_name", "")),
            "name": str(release_payload.get("name") or release_payload.get("tag_name") or ""),
            "description_markdown": str(release_payload.get("description", "")),
            "commit_sha": str(commit.get("id", "")),
            "assets": {
                "links": links,
                "sources": sources,
            },
        }
