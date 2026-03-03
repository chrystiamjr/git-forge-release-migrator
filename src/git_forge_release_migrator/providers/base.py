from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field


@dataclass
class ProviderRef:
    provider: str
    raw_url: str
    base_url: str
    host: str
    resource: str
    metadata: dict[str, str] = field(default_factory=dict)


class ProviderAdapter(ABC):
    name: str

    @abstractmethod
    def parse_url(self, url: str) -> ProviderRef:
        raise NotImplementedError

    def validate_url(self, url: str) -> bool:
        try:
            self.parse_url(url)
            return True
        except ValueError:
            return False

    @abstractmethod
    def to_canonical_release(self, release_payload: dict) -> dict:
        raise NotImplementedError

    def build_tag_url(self, ref: ProviderRef, tag: str) -> str:
        raise NotImplementedError(f"build_tag_url is not implemented for provider {self.name}")

    def list_releases(self, ref: ProviderRef, token: str) -> list[dict]:
        raise NotImplementedError(f"list_releases is not implemented for provider {self.name}")

    def list_tags(self, ref: ProviderRef, token: str) -> list[str]:
        raise NotImplementedError(f"list_tags is not implemented for provider {self.name}")
