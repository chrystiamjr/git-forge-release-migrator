from __future__ import annotations

import re

from .base import ProviderAdapter, ProviderRef


class BitbucketAdapter(ProviderAdapter):
    name = "bitbucket"

    def parse_url(self, url: str) -> ProviderRef:
        if not url:
            raise ValueError("Invalid Bitbucket URL: empty value")
        clean = str(url).strip().removesuffix(".git")
        clean = clean.split("?", 1)[0].split("#", 1)[0]

        m = re.match(r"^git@([^:]+):([^/]+)/([^/]+)$", clean)
        if m:
            host = m.group(1)
            workspace = m.group(2)
            repo = m.group(3)
            base_url = f"https://{host}"
        else:
            m = re.match(r"^https?://([^/]+)/([^/]+)/([^/]+)$", clean)
            if not m:
                raise ValueError(f"Invalid Bitbucket URL: {url}")
            host = m.group(1)
            workspace = m.group(2)
            repo = m.group(3)
            base_url = f"https://{host}"

        repo = repo.rstrip("/").split("/-/", 1)[0]

        if host != "bitbucket.org" or not workspace or not repo:
            raise ValueError("Only Bitbucket Cloud URLs are supported in this phase")

        return ProviderRef(
            provider=self.name,
            raw_url=url,
            base_url=base_url,
            host=host,
            resource=f"{workspace}/{repo}",
            metadata={"workspace": workspace, "repo": repo, "repo_ref": f"{workspace}/{repo}"},
        )

    def build_tag_url(self, ref: ProviderRef, tag: str) -> str:
        workspace = ref.metadata.get("workspace", "")
        repo = ref.metadata.get("repo", "")
        return f"{ref.base_url.rstrip('/')}/{workspace}/{repo}/src/{tag}"

    def to_canonical_release(self, release_payload: dict) -> dict:
        raise NotImplementedError("Bitbucket canonical release mapping is not implemented yet")
