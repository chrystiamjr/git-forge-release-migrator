from __future__ import annotations

import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

from .config import parse_raw_args, resolve_runtime_options
from .core.jsonl import append_log
from .core.logging import ConsoleLogger
from .core.session_store import save_session
from .migrations.engine import MigrationEngine
from .models import RuntimeOptions
from .providers.registry import ProviderRegistry


def _print_banner() -> None:
    if not sys.stdout.isatty():
        return

    use_color = os.getenv("NO_COLOR") is None
    reset = "\033[0m" if use_color else ""
    green = "\033[92m" if use_color else ""
    cyan = "\033[96m" if use_color else ""
    yellow = "\033[93m" if use_color else ""

    logo = r"""
   ____ _ _      _____
  / ___(_) |_   |  ___|__  _ __ __ _  ___
 | |  _| | __|  | |_ / _ \| '__/ _` |/ _ \
 | |_| | | |_   |  _| (_) | | | (_| |  __/
  \____|_|\__|  |_|  \___/|_|  \__, |_|\___|
                               |___/
  ____      _                        __  __ _                  _
 |  _ \ ___| | ___  __ _ ___  ___   |  \/  (_) __ _ _ __ __ _| |_ ___  _ __
 | |_) / _ \ |/ _ \/ _` / __|/ _ \  | |\/| | |/ _` | '__/ _` | __/ _ \| '__|
 |  _ <  __/ |  __/ (_| \__ \  __/  | |  | | | (_| | | | (_| | || (_) | |
 |_| \_\___|_|\___|\__,_|___/\___|  |_|  |_|_|\__, |_|  \__,_|\__\___/|_|
                                               |___/
"""

    print()
    print(f"{green}{logo}{reset}")
    print(f"{cyan}Migrate tags, releases, changelog and assets between Git forges.{reset}")
    print(f"{yellow}Quick commands:{reset}")
    print("  ./bin/repo-migrator.py --help")
    print("  ./bin/repo-migrator.py --resume-session")
    print("  ./bin/repo-migrator.py --non-interactive --dry-run --source-provider gitlab --target-provider github ...")
    print()


def _allocate_run_workdir(base_dir: Path) -> Path:
    run_id = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    candidate = base_dir / run_id
    if not candidate.exists():
        return candidate
    idx = 2
    while True:
        candidate = base_dir / f"{run_id}-{idx}"
        if not candidate.exists():
            return candidate
        idx += 1


def _demo_tags(options: RuntimeOptions) -> list[str]:
    if options.tags_file:
        tag_file = Path(options.tags_file)
        if tag_file.exists():
            tags = [
                line.strip()
                for line in tag_file.read_text(encoding="utf-8").splitlines()
                if line.strip() and not line.strip().startswith("#")
            ]
            if tags:
                return tags[: options.demo_releases]

    tags: list[str] = []
    for idx in range(options.demo_releases):
        if idx == 0:
            tags.append("v3.2.1")
        else:
            tags.append(f"v3.{2 + idx}.0")
    return tags


def _run_demo(options: RuntimeOptions, logger: ConsoleLogger, *, results_root: Path, run_workdir: Path) -> int:
    tags = _demo_tags(options)
    log_path = Path(options.log_file or (run_workdir / "migration-log.jsonl"))
    log_path.write_text("", encoding="utf-8")

    logger.info("DEMO MODE enabled (no network calls, no provider API interactions)")
    logger.info(f"  Source: {options.source_provider} ({options.source_url})")
    logger.info(f"  Target: {options.target_provider} ({options.target_url})")
    logger.info(f"  Tokens: source='{options.source_token}' target='{options.target_token}'")
    logger.info(f"  Simulated releases: {len(tags)}")
    logger.info(f"  Sleep per release: {options.demo_sleep_seconds:.2f}s")
    logger.info(f"  Results root: {results_root}")
    logger.info(f"  Run workdir: {run_workdir}")

    created = 0
    start_all = time.time()

    for idx, tag in enumerate(tags, start=1):
        percent = int(idx * 100 / len(tags)) if tags else 0
        progress = f"[{idx}/{len(tags)} - {percent:3d}%] Release {tag}"
        spinner_started = logger.start_spinner(progress)
        started = time.time()
        time.sleep(options.demo_sleep_seconds)
        if spinner_started:
            logger.stop_spinner()

        notes = run_workdir / f"release-{tag}-notes.md"
        notes.write_text(
            "\n".join(
                [
                    f"# {tag}",
                    "",
                    "This is a local demo run for README GIF recording.",
                    "No real API call was executed.",
                ]
            )
            + "\n",
            encoding="utf-8",
        )

        asset_count = 7 if idx % 2 else 6
        duration_ms = int((time.time() - started) * 1000)
        append_log(
            str(log_path),
            status="created",
            tag=tag,
            message="Demo: release created",
            asset_count=asset_count,
            duration_ms=duration_ms,
            dry_run=options.dry_run,
        )

        logger.info(f"[{tag}] created with {asset_count} asset(s) [demo]")
        created += 1

    failed_tags_path = run_workdir / "failed-tags.txt"
    failed_tags_path.write_text("", encoding="utf-8")

    total_ms = int((time.time() - start_all) * 1000)
    summary = {
        "demo_mode": True,
        "order": options.migration_order,
        "source": options.source_url,
        "target": options.target_url,
        "counts": {
            "tags_created": 0,
            "tags_skipped": len(tags) if options.skip_tag_migration else 0,
            "tags_failed": 0,
            "releases_created": created,
            "releases_updated": 0,
            "releases_skipped": 0,
            "releases_failed": 0,
        },
        "duration_ms": total_ms,
        "paths": {
            "jsonl_log": str(log_path),
            "workdir": str(run_workdir),
            "failed_tags": str(failed_tags_path),
        },
    }
    summary_path = run_workdir / "summary.json"
    summary_path.write_text(json.dumps(summary, ensure_ascii=True, indent=2) + "\n", encoding="utf-8")

    logger.info("Migration summary")
    logger.info("  Mode: demo")
    logger.info(f"  Releases created: {created}")
    logger.info("  Releases failed: 0")
    logger.info(f"  JSONL log: {log_path}")
    logger.info(f"  Summary JSON: {summary_path}")
    logger.info(f"  Failed tags file: {failed_tags_path}")
    return 0


def main(argv: list[str] | None = None) -> int:
    try:
        raw = parse_raw_args(argv)
        logger = ConsoleLogger(quiet=raw.quiet, json_output=raw.json_output)

        if not raw.no_banner and not raw.json_output and not raw.quiet:
            _print_banner()

        options = resolve_runtime_options(raw, logger)

        # Keep checkpoints in the root results directory while storing run artifacts in timestamped subdirs.
        results_root = Path(options.effective_workdir())
        run_workdir = _allocate_run_workdir(results_root)
        options.workdir = str(run_workdir)
        if not options.log_file:
            options.log_file = str(run_workdir / "migration-log.jsonl")
        if not options.checkpoint_file:
            options.checkpoint_file = str(results_root / "checkpoints" / "state.jsonl")

        run_workdir.mkdir(parents=True, exist_ok=True)

        if options.demo_mode:
            # force ephemeral behavior in demo runs
            options.save_session = False
            options.load_session = False
            options.resume_session = False
            return _run_demo(options, logger, results_root=results_root, run_workdir=run_workdir)

        registry = ProviderRegistry.default()
        source_adapter = registry.get(options.source_provider)
        target_adapter = registry.get(options.target_provider)

        source_ref = source_adapter.parse_url(options.source_url)
        target_ref = target_adapter.parse_url(options.target_url)

        if options.save_session or options.resume_session:
            session_file = options.effective_session_file()
            if options.session_token_mode == "env":
                os.environ[options.session_source_env_name()] = options.source_token
                os.environ[options.session_target_env_name()] = options.target_token
            save_session(session_file, options.to_session_payload())
            logger.info(f"Session saved to {session_file}")
            if options.session_token_mode == "plain":
                logger.warn("Session file stores tokens in plain text. Keep file permissions restricted.")
            else:
                logger.info(
                    "Session stores token env references only. Keep those environment variables available for resume."
                )

        logger.info("Python runtime loaded")
        logger.info(f"  Source: {options.source_provider} ({source_ref.resource})")
        logger.info(f"  Target: {options.target_provider} ({target_ref.resource})")
        logger.info(f"  Order: {options.migration_order}")
        logger.info(f"  Tag range: {options.from_tag or '<start>'} -> {options.to_tag or '<end>'}")
        logger.info(f"  Dry-run: {str(options.dry_run).lower()}")
        logger.info(f"  Skip tags: {str(options.skip_tag_migration).lower()}")
        logger.info(f"  Download workers: {options.download_workers}")
        logger.info(f"  Release workers: {options.release_workers}")
        logger.info(f"  Session token mode: {options.session_token_mode}")
        logger.info(f"  Checkpoint file: {options.effective_checkpoint_file()}")
        logger.info(f"  Results root: {results_root}")
        logger.info(f"  Run workdir: {run_workdir}")
        if options.tags_file:
            logger.info(f"  Tags file: {options.tags_file}")

        migration_engine = MigrationEngine(registry=registry, logger=logger)
        migration_engine.run(options, source_ref, target_ref)
        logger.stop_spinner()
        return 0

    except Exception as exc:  # noqa: BLE001
        try:
            logger.stop_spinner()  # type: ignore[name-defined]
        except Exception:  # noqa: BLE001
            pass
        if "logger" in locals():
            logger.error(str(exc))
        else:
            print(f"[ERROR] {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
