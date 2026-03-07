from __future__ import annotations

import argparse
import getpass
import os
import sys
from dataclasses import dataclass
from typing import Callable

from .core.logging import ConsoleLogger
from .core.session_store import load_session
from .core.settings import (
    load_effective_settings,
    resolve_profile_name,
    token_from_env_aliases,
    token_from_settings,
)
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
    command: str = "migrate"

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
    settings_profile: str = ""

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

    settings_action: str = ""
    settings_provider: str = ""
    settings_env_name: str = ""
    settings_token: str = ""
    settings_scope_local: bool = False
    settings_yes: bool = False


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


def _resolve_side_token(
    *,
    raw: RawCLIOptions,
    side: str,
    provider: str,
    settings_payload: dict,
    profile: str,
) -> str:
    if not _known_provider(provider):
        return ""

    from_settings = token_from_settings(settings_payload, profile, provider)
    if from_settings:
        return from_settings

    side_env_name = raw.session_source_token_env if side == "source" else raw.session_target_token_env
    return token_from_env_aliases(provider, side_env_name=side_env_name)


def _apply_settings_and_env_fallback(raw: RawCLIOptions, settings_payload: dict, profile: str) -> None:
    source_provider = _normalize_provider(raw.source_provider)
    target_provider = _normalize_provider(raw.target_provider)

    if not raw.source_token and _known_provider(source_provider):
        raw.source_token = _resolve_side_token(
            raw=raw,
            side="source",
            provider=source_provider,
            settings_payload=settings_payload,
            profile=profile,
        )

    if not raw.target_token and _known_provider(target_provider):
        raw.target_token = _resolve_side_token(
            raw=raw,
            side="target",
            provider=target_provider,
            settings_payload=settings_payload,
            profile=profile,
        )


def _prompt_missing(
    raw: RawCLIOptions,
    input_fn: Callable[[str], str],
    getpass_fn: Callable[[str], str],
    *,
    prompt_skip_tags: bool,
    settings_payload: dict,
    profile: str,
) -> None:
    while not _known_provider(_normalize_provider(raw.source_provider)):
        raw.source_provider = input_fn("Source provider (github/gitlab/bitbucket): ").strip()

    if not raw.source_url:
        raw.source_url = input_fn("Source project URL: ").strip()

    if not raw.source_token:
        provider = _normalize_provider(raw.source_provider)
        raw.source_token = _resolve_side_token(
            raw=raw,
            side="source",
            provider=provider,
            settings_payload=settings_payload,
            profile=profile,
        )
    if not raw.source_token:
        raw.source_token = getpass_fn("Source token: ").strip()

    while not _known_provider(_normalize_provider(raw.target_provider)):
        raw.target_provider = input_fn("Target provider (github/gitlab/bitbucket): ").strip()

    if not raw.target_url:
        raw.target_url = input_fn("Target project URL: ").strip()

    if not raw.target_token:
        provider = _normalize_provider(raw.target_provider)
        raw.target_token = _resolve_side_token(
            raw=raw,
            side="target",
            provider=provider,
            settings_payload=settings_payload,
            profile=profile,
        )
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
    if raw.command != "migrate":
        raise ValueError("resolve_runtime_options only supports migrate command")

    if raw.resume_session:
        raw.load_session = True
        raw.save_session = True

    raw.session_token_mode = (raw.session_token_mode or "env").strip().lower()
    if raw.session_token_mode not in {"env", "plain"}:
        raise ValueError("--session-token-mode must be one of: env, plain")

    _load_session_fill_missing(raw, logger)

    raw.source_provider = _normalize_provider(raw.source_provider)
    raw.target_provider = _normalize_provider(raw.target_provider)

    settings_payload = load_effective_settings()
    profile = resolve_profile_name(settings_payload, raw.settings_profile)
    raw.settings_profile = profile
    _apply_settings_and_env_fallback(raw, settings_payload, profile)

    if not raw.non_interactive:
        prompt_skip_tags = sys.stdin.isatty() or input_fn is not input
        _prompt_missing(
            raw,
            input_fn,
            getpass_fn,
            prompt_skip_tags=prompt_skip_tags,
            settings_payload=settings_payload,
            profile=profile,
        )
        raw.source_provider = _normalize_provider(raw.source_provider)
        raw.target_provider = _normalize_provider(raw.target_provider)
        _apply_settings_and_env_fallback(raw, settings_payload, profile)

    if not all([raw.source_provider, raw.source_url, raw.target_provider, raw.target_url]):
        raise ValueError("Missing required canonical inputs. Provide source/target provider URL and token.")

    if not raw.source_token:
        raise ValueError(
            "Missing source token. Provide --source-token, settings profile token, or relevant env variable."
        )
    if not raw.target_token:
        raise ValueError(
            "Missing target token. Provide --target-token, settings profile token, or relevant env variable."
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
    parser.add_argument("--settings-profile", default="")

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


def build_settings_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="gfrm settings", description="Manage gfrm settings")
    sub = parser.add_subparsers(dest="settings_action", required=True)

    init = sub.add_parser("init", help="Interactive bootstrap for provider token settings")
    init.add_argument("--profile", default="")
    init.add_argument("--local", action="store_true")
    init.add_argument("--yes", action="store_true")

    set_env = sub.add_parser("set-token-env", help="Store token environment variable name for a provider")
    set_env.add_argument("--provider", required=True)
    set_env.add_argument("--env-name", required=True)
    set_env.add_argument("--profile", default="")
    set_env.add_argument("--local", action="store_true")

    set_plain = sub.add_parser("set-token-plain", help="Store plain token value for a provider")
    set_plain.add_argument("--provider", required=True)
    set_plain.add_argument("--token", default="")
    set_plain.add_argument("--profile", default="")
    set_plain.add_argument("--local", action="store_true")

    unset = sub.add_parser("unset-token", help="Unset provider token settings")
    unset.add_argument("--provider", required=True)
    unset.add_argument("--profile", default="")
    unset.add_argument("--local", action="store_true")

    show = sub.add_parser("show", help="Show effective settings")
    show.add_argument("--profile", default="")

    return parser


def _parse_settings_args(args: list[str]) -> RawCLIOptions:
    ns = build_settings_parser().parse_args(args)
    raw = RawCLIOptions(command="settings")
    raw.settings_action = str(getattr(ns, "settings_action", "") or "")
    raw.settings_provider = _normalize_provider(str(getattr(ns, "provider", "") or ""))
    raw.settings_env_name = str(getattr(ns, "env_name", "") or "")
    raw.settings_token = str(getattr(ns, "token", "") or "")
    raw.settings_profile = str(getattr(ns, "profile", "") or "")
    raw.settings_scope_local = bool(getattr(ns, "local", False))
    raw.settings_yes = bool(getattr(ns, "yes", False))
    return raw


def parse_raw_args(argv: list[str] | None = None) -> RawCLIOptions:
    arg_list = list(argv) if argv is not None else sys.argv[1:]

    if arg_list and arg_list[0] == "settings":
        return _parse_settings_args(arg_list[1:])

    ns = build_parser().parse_args(arg_list)
    raw = RawCLIOptions(**vars(ns))
    raw.command = "migrate"
    raw.skip_tags_provided = "--skip-tags" in arg_list
    raw.download_workers_provided = "--download-workers" in arg_list
    raw.release_workers_provided = "--release-workers" in arg_list
    return raw
