from __future__ import annotations

from dataclasses import dataclass

from .base import ProviderAdapter
from .bitbucket import BitbucketAdapter
from .github import GitHubAdapter
from .gitlab import GitLabAdapter


@dataclass
class ProviderRegistry:
    adapters: dict[str, ProviderAdapter]

    @classmethod
    def default(cls) -> "ProviderRegistry":
        return cls(
            adapters={
                "github": GitHubAdapter(),
                "gitlab": GitLabAdapter(),
                "bitbucket": BitbucketAdapter(),
            }
        )

    def get(self, provider: str) -> ProviderAdapter:
        if provider not in self.adapters:
            raise ValueError(f"Unsupported provider: {provider}")
        return self.adapters[provider]

    def pair_status(self, source: str, target: str) -> str:
        known = {"github", "gitlab", "bitbucket"}
        if source not in known or target not in known:
            return "unsupported"
        if source == target:
            return "unsupported"
        if source in known and target in known:
            return "enabled"
        return "unsupported"

    def require_supported_pair(self, source: str, target: str) -> None:
        status = self.pair_status(source, target)
        if status == "enabled":
            return
        raise ValueError(f"Provider pair {source}->{target} is unsupported.")
