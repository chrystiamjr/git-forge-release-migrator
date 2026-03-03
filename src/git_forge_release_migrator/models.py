from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

_DEFAULT_SOURCE_TOKEN_ENV = "GFRM_SOURCE_TOKEN"
_DEFAULT_TARGET_TOKEN_ENV = "GFRM_TARGET_TOKEN"


@dataclass
class RuntimeOptions:
    source_provider: str
    source_url: str
    source_token: str
    target_provider: str
    target_url: str
    target_token: str
    migration_order: str
    skip_tag_migration: bool = False
    from_tag: str = ""
    to_tag: str = ""
    dry_run: bool = False
    non_interactive: bool = False
    workdir: str = ""
    log_file: str = ""
    load_session: bool = False
    save_session: bool = True
    resume_session: bool = False
    session_file: str = ""
    download_workers: int = 4
    release_workers: int = 1
    checkpoint_file: str = ""
    tags_file: str = ""
    quiet: bool = False
    json_output: bool = False
    no_banner: bool = False
    progress_bar: bool = False
    demo_mode: bool = False
    demo_releases: int = 5
    demo_sleep_seconds: float = 1.0
    session_token_mode: str = "env"
    session_source_token_env: str = _DEFAULT_SOURCE_TOKEN_ENV
    session_target_token_env: str = _DEFAULT_TARGET_TOKEN_ENV

    def effective_workdir(self) -> str:
        if self.workdir:
            return self.workdir
        return str(Path.cwd() / "migration-results")

    def effective_session_file(self) -> str:
        if self.session_file:
            return self.session_file
        return str(Path.cwd() / "sessions" / "last-session.json")

    def effective_checkpoint_file(self) -> str:
        if self.checkpoint_file:
            return self.checkpoint_file
        return str(Path(self.effective_workdir()) / "checkpoints" / "state.jsonl")

    def session_source_env_name(self) -> str:
        return (self.session_source_token_env or _DEFAULT_SOURCE_TOKEN_ENV).strip() or _DEFAULT_SOURCE_TOKEN_ENV

    def session_target_env_name(self) -> str:
        return (self.session_target_token_env or _DEFAULT_TARGET_TOKEN_ENV).strip() or _DEFAULT_TARGET_TOKEN_ENV

    def to_session_payload(self) -> dict:
        payload = {
            "source_provider": self.source_provider,
            "source_url": self.source_url,
            "target_provider": self.target_provider,
            "target_url": self.target_url,
            "from_tag": self.from_tag,
            "to_tag": self.to_tag,
            "skip_tag_migration": self.skip_tag_migration,
            "download_workers": self.download_workers,
            "release_workers": self.release_workers,
            "saved_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "session_token_mode": self.session_token_mode,
        }

        if self.session_token_mode == "plain":
            payload["source_token"] = self.source_token
            payload["target_token"] = self.target_token
        else:
            payload["source_token_env"] = self.session_source_env_name()
            payload["target_token_env"] = self.session_target_env_name()

        return payload


@dataclass
class MigrationContext:
    """Carries shared migration state passed to release-processing methods."""

    source_ref: Any
    target_ref: Any
    source: Any
    target: Any
    options: RuntimeOptions
    log_path: str
    workdir: Path
    checkpoint_path: str
    checkpoint_signature: str
    checkpoint_state: dict
    selected_tags: list
    target_tags: set
    target_release_tags: set
    failed_tags: set
    releases: list
