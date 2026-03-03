from __future__ import annotations

import argparse
import getpass
import os
import sys
from dataclasses import dataclass
from typing import Callable

from .core.logging import ConsoleLogger
from .core.session_store import load_session
from .core.versioning import version_le
from .models import RuntimeOptions

_PROVIDER_MAP = {
    "github": "github",
    "gh": "github",
    "gitlab": "gitlab",
    "gl": "gitlab",
    "bitbucket": "bitbucket",
    "bb": "bitbucket",
}


@dataclass
class RawCLIOptions:
    source_provider: str = ""
    source_url: str = ""
    source_token: str = ""
    target_provider: str = ""
    target_url: str = ""
    target_token: str = ""
    skip_tags: bool = False
    skip_tags_provided: bool = False
    from_tag: str = ""
    to_tag: str = ""
    workdir: str = ""
    log_file: str = ""
    dry_run: bool = False
    non_interactive: bool = False
    load_session: bool = False
    save_session: bool = True
    resume_session: bool = False
    session_file: str = ""
    session_token_mode: str = "env"
    session_source_token_env: str = "GFRM_SOURCE_TOKEN"
    session_target_token_env: str = "GFRM_TARGET_TOKEN"
    download_workers: int = 4
    download_workers_provided: bool = False
    release_workers: int = 1
    release_workers_provided: bool = False
    checkpoint_file: str = ""
    tags_file: str = ""
    no_banner: bool = False
    quiet: bool = False
    json_output: bool = False
    progress_bar: bool = False
    demo_mode: bool = False
    demo_releases: int = 5
    demo_sleep_seconds: float = 1.0


def _normalize_provider(value: str | None) -> str:
    if value is None:
        return ""
    key = str(value).strip().lower()
    return _PROVIDER_MAP.get(key, "")


def _known_provider(value: str) -> bool:
    return value in {"github", "gitlab", "bitbucket"}


def _prompt_yes_no(input_fn: Callable[[str], str], prompt: str, *, default: bool = False) -> bool:
    suffix = " [Y/n]: " if default else " [y/N]: "
    while True:
        answer = input_fn(f"{prompt}{suffix}")
        normalized = "" if answer is None else str(answer).strip().lower()
        if not normalized:
            return default
        if normalized in {"y", "yes", "s", "sim"}:
            return True
        if normalized in {"n", "no", "nao", "não"}:
            return False


def _load_session_fill_missing(raw: RawCLIOptions, logger: ConsoleLogger) -> None:
    if not (raw.load_session or raw.resume_session):
        return

    session_path = (
        raw.session_file
        or RuntimeOptions(
            source_provider="",
            source_url="",
            source_token="",
            target_provider="",
            target_url="",
            target_token="",
            migration_order="",
        ).effective_session_file()
    )

    try:
        data = load_session(session_path)
    except FileNotFoundError:
        if raw.resume_session:
            if not raw.session_file:
                raw.session_file = session_path
            logger.warn(
                f"Session file not found at {session_path}. Continuing without loading; a new session will be saved."
            )
            return
        raise

    raw.source_provider = raw.source_provider or str(data.get("source_provider", ""))
    raw.source_url = raw.source_url or str(data.get("source_url", ""))
    raw.target_provider = raw.target_provider or str(data.get("target_provider", ""))
    raw.target_url = raw.target_url or str(data.get("target_url", ""))

    source_token_plain = str(data.get("source_token", ""))
    target_token_plain = str(data.get("target_token", ""))
    source_token_env = str(data.get("source_token_env", "")).strip()
    target_token_env = str(data.get("target_token_env", "")).strip()

    if source_token_env:
        raw.session_source_token_env = source_token_env
    if target_token_env:
        raw.session_target_token_env = target_token_env

    if not raw.source_token:
        if source_token_plain:
            raw.source_token = source_token_plain
        elif source_token_env:
            raw.source_token = os.getenv(source_token_env, "")

    if not raw.target_token:
        if target_token_plain:
            raw.target_token = target_token_plain
        elif target_token_env:
            raw.target_token = os.getenv(target_token_env, "")

    raw.from_tag = raw.from_tag or str(data.get("from_tag", ""))
    raw.to_tag = raw.to_tag or str(data.get("to_tag", ""))
    if not raw.download_workers_provided:
        raw.download_workers = int(data.get("download_workers", raw.download_workers) or raw.download_workers)
    if not raw.release_workers_provided:
        raw.release_workers = int(data.get("release_workers", raw.release_workers) or raw.release_workers)
    if not raw.skip_tags and bool(data.get("skip_tag_migration", False)):
        raw.skip_tags = True

    if not raw.session_file:
        raw.session_file = session_path

    logger.info(f"Session loaded from {session_path}")


def _prompt_missing(
    raw: RawCLIOptions,
    input_fn: Callable[[str], str],
    getpass_fn: Callable[[str], str],
    *,
    prompt_skip_tags: bool,
) -> None:
    while not _known_provider(_normalize_provider(raw.source_provider)):
        raw.source_provider = input_fn("Source provider (github/gitlab/bitbucket): ").strip()

    if not raw.source_url:
        raw.source_url = input_fn("Source project URL: ").strip()

    if not raw.source_token:
        raw.source_token = getpass_fn("Source token: ").strip()

    while not _known_provider(_normalize_provider(raw.target_provider)):
        raw.target_provider = input_fn("Target provider (github/gitlab/bitbucket): ").strip()

    if not raw.target_url:
        raw.target_url = input_fn("Target project URL: ").strip()

    if not raw.target_token:
        raw.target_token = getpass_fn("Target token: ").strip()

    if prompt_skip_tags and not raw.skip_tags_provided:
        raw.skip_tags = _prompt_yes_no(input_fn, "Skip tag migration?", default=raw.skip_tags)


def resolve_runtime_options(
    raw: RawCLIOptions,
    logger: ConsoleLogger,
    input_fn: Callable[[str], str] = input,
    getpass_fn: Callable[[str], str] = getpass.getpass,
) -> RuntimeOptions:
    if raw.resume_session:
        raw.load_session = True
        raw.save_session = True

    raw.session_token_mode = (raw.session_token_mode or "env").strip().lower()
    if raw.session_token_mode not in {"env", "plain"}:
        raise ValueError("--session-token-mode must be one of: env, plain")

    _load_session_fill_missing(raw, logger)

    raw.source_provider = _normalize_provider(raw.source_provider)
    raw.target_provider = _normalize_provider(raw.target_provider)

    if not raw.non_interactive:
        prompt_skip_tags = sys.stdin.isatty() or input_fn is not input
        _prompt_missing(raw, input_fn, getpass_fn, prompt_skip_tags=prompt_skip_tags)
        raw.source_provider = _normalize_provider(raw.source_provider)
        raw.target_provider = _normalize_provider(raw.target_provider)

    if not all([raw.source_provider, raw.source_url, raw.target_provider, raw.target_url]):
        raise ValueError("Missing required canonical inputs. Provide source/target provider URL and token.")

    if not raw.source_token:
        raise ValueError(
            f"Missing source token. Provide --source-token or set env var '{raw.session_source_token_env}'."
        )
    if not raw.target_token:
        raise ValueError(
            f"Missing target token. Provide --target-token or set env var '{raw.session_target_token_env}'."
        )

    if not _known_provider(raw.source_provider):
        raise ValueError(f"Unsupported source provider: {raw.source_provider}")

    if not _known_provider(raw.target_provider):
        raise ValueError(f"Unsupported target provider: {raw.target_provider}")

    if raw.from_tag and raw.to_tag and not version_le(raw.from_tag, raw.to_tag):
        raise ValueError(f"Invalid range: --from-tag ({raw.from_tag}) must be <= --to-tag ({raw.to_tag})")

    if raw.download_workers < 1:
        raise ValueError("--download-workers must be >= 1")
    if raw.download_workers > 16:
        raise ValueError("--download-workers must be <= 16")
    if raw.release_workers < 1:
        raise ValueError("--release-workers must be >= 1")
    if raw.release_workers > 8:
        raise ValueError("--release-workers must be <= 8")

    if raw.demo_releases < 1:
        raise ValueError("--demo-releases must be >= 1")
    if raw.demo_releases > 100:
        raise ValueError("--demo-releases must be <= 100")
    if raw.demo_sleep_seconds < 0:
        raise ValueError("--demo-sleep-seconds must be >= 0")

    return RuntimeOptions(
        source_provider=raw.source_provider,
        source_url=raw.source_url,
        source_token=raw.source_token,
        target_provider=raw.target_provider,
        target_url=raw.target_url,
        target_token=raw.target_token,
        migration_order=f"{raw.source_provider}-to-{raw.target_provider}",
        skip_tag_migration=raw.skip_tags,
        from_tag=raw.from_tag,
        to_tag=raw.to_tag,
        dry_run=raw.dry_run,
        non_interactive=raw.non_interactive,
        workdir=raw.workdir,
        log_file=raw.log_file,
        load_session=raw.load_session,
        save_session=raw.save_session,
        resume_session=raw.resume_session,
        session_file=raw.session_file,
        session_token_mode=raw.session_token_mode,
        session_source_token_env=raw.session_source_token_env,
        session_target_token_env=raw.session_target_token_env,
        download_workers=raw.download_workers,
        release_workers=raw.release_workers,
        checkpoint_file=raw.checkpoint_file,
        tags_file=raw.tags_file,
        no_banner=raw.no_banner,
        quiet=raw.quiet,
        json_output=raw.json_output,
        progress_bar=raw.progress_bar,
        demo_mode=raw.demo_mode,
        demo_releases=raw.demo_releases,
        demo_sleep_seconds=raw.demo_sleep_seconds,
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="gfrm", description="Python runtime for git-forge-release-migrator")

    parser.add_argument("--source-provider")
    parser.add_argument("--source-url")
    parser.add_argument("--source-token")
    parser.add_argument("--target-provider")
    parser.add_argument("--target-url")
    parser.add_argument("--target-token")

    parser.add_argument("--load-session", action="store_true")
    parser.add_argument("--save-session", dest="save_session", action="store_true", default=True)
    parser.add_argument("--no-save-session", dest="save_session", action="store_false")
    parser.add_argument("--resume-session", action="store_true")
    parser.add_argument("--session-file", default="")
    parser.add_argument("--session-token-mode", choices=["env", "plain"], default="env")
    parser.add_argument("--session-source-token-env", default="GFRM_SOURCE_TOKEN")
    parser.add_argument("--session-target-token-env", default="GFRM_TARGET_TOKEN")

    parser.add_argument("--download-workers", type=int, default=4)
    parser.add_argument("--release-workers", type=int, default=1)
    parser.add_argument("--checkpoint-file", default="")

    parser.add_argument("--skip-tags", action="store_true")
    parser.add_argument("--from-tag", default="")
    parser.add_argument("--to-tag", default="")
    parser.add_argument("--tags-file", default="")
    parser.add_argument("--workdir", default="")
    parser.add_argument("--log-file", default="")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--non-interactive", action="store_true")
    parser.add_argument("--no-banner", action="store_true")
    parser.add_argument("--quiet", action="store_true")
    parser.add_argument("--json", dest="json_output", action="store_true")
    parser.add_argument("--progress-bar", action="store_true")

    parser.add_argument("--demo-mode", action="store_true")
    parser.add_argument("--demo-releases", type=int, default=5)
    parser.add_argument("--demo-sleep-seconds", type=float, default=1.0)

    return parser


def parse_raw_args(argv: list[str] | None = None) -> RawCLIOptions:
    ns = build_parser().parse_args(argv)
    raw = RawCLIOptions(**vars(ns))
    arg_list = argv if argv is not None else sys.argv[1:]
    raw.skip_tags_provided = "--skip-tags" in arg_list
    raw.download_workers_provided = "--download-workers" in arg_list
    raw.release_workers_provided = "--release-workers" in arg_list
    return raw
