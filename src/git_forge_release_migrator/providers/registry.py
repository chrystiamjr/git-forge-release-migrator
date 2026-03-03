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
        if (source, target) in {("gitlab", "github"), ("github", "gitlab")}:
            return "enabled"
        if "bitbucket" in {source, target}:
            return "not_implemented"
        return "unsupported"

    def require_supported_pair(self, source: str, target: str) -> None:
        status = self.pair_status(source, target)
        if status == "enabled":
            return
        if status == "not_implemented":
            raise ValueError(
                f"Provider pair {source}->{target} is registered but not implemented yet (Bitbucket phase pending)."
            )
        raise ValueError(f"Provider pair {source}->{target} is unsupported.")
