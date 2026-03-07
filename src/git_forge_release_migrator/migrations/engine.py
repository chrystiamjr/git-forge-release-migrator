from __future__ import annotations

import json
import re
import shlex
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from pathlib import Path
from threading import RLock
from typing import Any, Callable, cast

from ..core.checkpoint import (
    append_checkpoint,
    is_terminal_release_status,
    is_terminal_tag_status,
    load_checkpoint_state,
)
from ..core.files import cleanup_dir, ensure_dir, sanitize_filename, unique_asset_filename
from ..core.http import AuthenticationError, HTTPRequestError
from ..core.jsonl import append_log
from ..core.logging import ConsoleLogger
from ..core.versioning import version_le
from ..models import MigrationContext, RuntimeOptions
from ..providers.base import ProviderRef
from ..providers.bitbucket import BitbucketAdapter
from ..providers.github import GitHubAdapter
from ..providers.gitlab import GitLabAdapter
from ..providers.registry import ProviderRegistry

_SEMVER_TAG_RE = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")
_SUPPORTED_ARCHIVE_FORMATS = {"zip", "tar.gz", "tar.bz2", "tar"}


@dataclass
class MigrationEngine:
    registry: ProviderRegistry
    logger: ConsoleLogger
    _log_lock: RLock = field(default_factory=RLock, init=False, repr=False)
    _checkpoint_lock: RLock = field(default_factory=RLock, init=False, repr=False)

    def run(self, options: RuntimeOptions, source_ref: ProviderRef, target_ref: ProviderRef) -> None:
        self.registry.require_supported_pair(options.source_provider, options.target_provider)

        pair = (options.source_provider, options.target_provider)
        if pair == ("gitlab", "github"):
            source = cast(GitLabAdapter, self.registry.get("gitlab"))
            target = cast(GitHubAdapter, self.registry.get("github"))
            self._migrate_gitlab_to_github(options, source_ref, target_ref, source, target)
            return

        if pair == ("github", "gitlab"):
            source = cast(GitHubAdapter, self.registry.get("github"))
            target = cast(GitLabAdapter, self.registry.get("gitlab"))
            self._migrate_github_to_gitlab(options, source_ref, target_ref, source, target)
            return

        if pair == ("github", "bitbucket"):
            source = cast(GitHubAdapter, self.registry.get("github"))
            target = cast(BitbucketAdapter, self.registry.get("bitbucket"))
            self._migrate_github_to_bitbucket(options, source_ref, target_ref, source, target)
            return

        if pair == ("gitlab", "bitbucket"):
            source = cast(GitLabAdapter, self.registry.get("gitlab"))
            target = cast(BitbucketAdapter, self.registry.get("bitbucket"))
            self._migrate_gitlab_to_bitbucket(options, source_ref, target_ref, source, target)
            return

        if pair == ("bitbucket", "github"):
            source = cast(BitbucketAdapter, self.registry.get("bitbucket"))
            target = cast(GitHubAdapter, self.registry.get("github"))
            self._migrate_bitbucket_to_github(options, source_ref, target_ref, source, target)
            return

        if pair == ("bitbucket", "gitlab"):
            source = cast(BitbucketAdapter, self.registry.get("bitbucket"))
            target = cast(GitLabAdapter, self.registry.get("gitlab"))
            self._migrate_bitbucket_to_gitlab(options, source_ref, target_ref, source, target)
            return

        raise ValueError(f"Provider pair {source_ref.provider}->{target_ref.provider} is unsupported.")

    def _semver_key(self, tag: str) -> tuple[int, int, int]:
        m = _SEMVER_TAG_RE.match(tag)
        if not m:
            raise ValueError(f"Invalid semantic tag: {tag}")
        return int(m.group(1)), int(m.group(2)), int(m.group(3))

    def _collect_selected_tags(self, releases: list[dict], from_tag: str, to_tag: str) -> list[str]:
        tags = []
        for release in releases:
            tag = str(release.get("tag_name", ""))
            if not _SEMVER_TAG_RE.match(tag):
                continue
            tags.append(tag)

        tags = sorted(set(tags), key=self._semver_key)

        selected: list[str] = []
        for tag in tags:
            if from_tag and not version_le(from_tag, tag):
                continue
            if to_tag and not version_le(tag, to_tag):
                continue
            selected.append(tag)

        return selected

    def _release_by_tag(self, releases: list[dict], tag: str) -> dict | None:
        for item in releases:
            if str(item.get("tag_name", "")) == tag:
                return item
        return None

    def _log(
        self, log_path: str, *, status: str, tag: str, message: str, asset_count: int, duration_ms: int, dry_run: bool
    ) -> None:
        with self._log_lock:
            append_log(
                log_path,
                status=status,
                tag=tag,
                message=message,
                asset_count=asset_count,
                duration_ms=duration_ms,
                dry_run=dry_run,
            )

    def _checkpoint_signature(self, options: RuntimeOptions, source_ref: ProviderRef, target_ref: ProviderRef) -> str:
        return "|".join(
            [
                options.migration_order,
                source_ref.resource,
                target_ref.resource,
                options.from_tag or "<start>",
                options.to_tag or "<end>",
            ]
        )

    def _checkpoint_mark(
        self,
        checkpoint_path: str,
        checkpoint_state: dict[str, str],
        *,
        signature: str,
        key: str,
        tag: str,
        status: str,
        message: str,
    ) -> None:
        with self._checkpoint_lock:
            append_checkpoint(
                checkpoint_path,
                signature=signature,
                key=key,
                tag=tag,
                status=status,
                message=message,
            )
            checkpoint_state[key] = status

    def _progress_message(self, index: int, total: int, message: str, *, progress_bar: bool = False) -> str:
        percent = int(index * 100 / total) if total else 0
        if progress_bar and total > 0:
            width = 20
            filled = int(width * index / total)
            bar = ("#" * filled) + ("-" * (width - filled))
            return f"[{index}/{total} - {percent:3d}%] [{bar}] {message}"
        return f"[{index}/{total} - {percent:3d}%] {message}"

    def _progress(self, index: int, total: int, message: str, *, progress_bar: bool = False) -> None:
        self.logger.info(self._progress_message(index, total, message, progress_bar=progress_bar))

    def _tag_sort_key(self, tag: str) -> tuple[int, int, int, int] | tuple[int, str]:
        m = _SEMVER_TAG_RE.match(tag)
        if not m:
            return (1, tag)
        return (0, int(m.group(1)), int(m.group(2)), int(m.group(3)))

    def _load_tags_file(self, tags_file: str) -> set[str]:
        p = Path(tags_file)
        if not p.exists():
            raise RuntimeError(f"Tags file not found: {tags_file}")

        tags: set[str] = set()
        for raw in p.read_text(encoding="utf-8").splitlines():
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            tags.add(line)
        if not tags:
            raise RuntimeError(f"Tags file is empty: {tags_file}")
        return tags

    def _apply_tags_filter(self, selected_tags: list[str], tags_file: str) -> list[str]:
        if not tags_file:
            return selected_tags
        allowed = self._load_tags_file(tags_file)
        return [tag for tag in selected_tags if tag in allowed]

    def _build_retry_command(self, options: RuntimeOptions, failed_tags_path: Path) -> str:
        cmd = ["./bin/repo-migrator.py", "--resume-session", "--tags-file", str(failed_tags_path)]
        if options.non_interactive:
            cmd.append("--non-interactive")
        if options.no_banner:
            cmd.append("--no-banner")
        if options.quiet:
            cmd.append("--quiet")
        if options.json_output:
            cmd.append("--json")
        if options.session_token_mode == "plain":
            cmd.extend(["--session-token-mode", "plain"])
        return " ".join(shlex.quote(part) for part in cmd)

    def _reserve_output_name(self, used_names: set[str], raw_name: str) -> str:
        clean = sanitize_filename(raw_name)
        stem = clean
        suffix = ""
        if "." in clean and not clean.startswith("."):
            stem, ext = clean.rsplit(".", 1)
            suffix = f".{ext}"

        candidate = f"{stem}{suffix}"
        i = 2
        while candidate in used_names:
            candidate = f"{stem}-{i}{suffix}"
            i += 1
        used_names.add(candidate)
        return candidate

    def _run_parallel_jobs(
        self,
        jobs: list[dict[str, Any]],
        worker_count: int,
        runner: Callable[[dict[str, Any]], dict[str, Any]],
    ) -> list[dict[str, Any]]:
        if not jobs:
            return []

        max_workers = max(1, min(worker_count, len(jobs)))
        if max_workers == 1:
            return [runner(job) for job in jobs]

        results: list[dict[str, Any]] = [{} for _ in jobs]
        with ThreadPoolExecutor(max_workers=max_workers) as pool:
            future_map = {pool.submit(runner, job): idx for idx, job in enumerate(jobs)}
            for future in as_completed(future_map):
                idx = future_map[future]
                try:
                    results[idx] = future.result()
                except Exception:  # noqa: BLE001
                    failed_job = jobs[idx]
                    results[idx] = {
                        "ok": False,
                        "name": str(failed_job.get("name", "asset")),
                        "output_path": str(failed_job.get("output_path", "")),
                    }
        return results

    def _download_gitlab_link_asset(
        self,
        source: GitLabAdapter,
        source_ref: ProviderRef,
        token: str,
        tag: str,
        *,
        direct_resolved: str,
        raw_resolved: str,
        output_path: str,
    ) -> bool:
        downloaded = False
        if direct_resolved and source.download_with_auth(token, direct_resolved, output_path):
            downloaded = True
            return downloaded

        if not downloaded and direct_resolved:
            self.logger.info(f"[{tag}] link asset: auth download failed for direct_url, trying release API URL")
            api_url = source.build_release_download_api_url(source_ref, tag, direct_resolved)
            if api_url and source.download_with_auth(token, api_url, output_path):
                downloaded = True
                return downloaded

        if not downloaded and direct_resolved:
            self.logger.info(f"[{tag}] link asset: release API download failed, trying project upload API URL")
            upload_api_url = source.build_project_upload_api_url(source_ref, direct_resolved)
            if upload_api_url and source.download_with_auth(token, upload_api_url, output_path):
                downloaded = True
                return downloaded

        if not downloaded and raw_resolved and raw_resolved != direct_resolved:
            self.logger.info(f"[{tag}] link asset: direct_url strategies failed, trying raw_url with auth")
            if source.download_with_auth(token, raw_resolved, output_path):
                downloaded = True
                return downloaded

        if not downloaded and raw_resolved and raw_resolved != direct_resolved:
            self.logger.info(f"[{tag}] link asset: raw_url auth failed, trying project upload API URL for raw_url")
            upload_api_url = source.build_project_upload_api_url(source_ref, raw_resolved)
            if upload_api_url and source.download_with_auth(token, upload_api_url, output_path):
                downloaded = True
                return downloaded

        if not downloaded and direct_resolved:
            self.logger.info(f"[{tag}] link asset: all auth strategies failed, trying private_token query param")
            private_url = source.add_private_token_query(direct_resolved, token)
            if source.download_no_auth(private_url, output_path):
                downloaded = True
                return downloaded

        if not downloaded and raw_resolved and raw_resolved != direct_resolved:
            private_url = source.add_private_token_query(raw_resolved, token)
            if source.download_no_auth(private_url, output_path):
                downloaded = True

        if not downloaded:
            self.logger.info(f"[{tag}] link asset: all download strategies exhausted")

        return downloaded

    def _download_gitlab_source_asset(
        self,
        source: GitLabAdapter,
        source_ref: ProviderRef,
        token: str,
        tag: str,
        *,
        source_format: str,
        source_resolved: str,
        output_path: str,
    ) -> bool:
        downloaded = False
        if source_format in _SUPPORTED_ARCHIVE_FORMATS:
            archive_api_url = source.build_repository_archive_api_url(source_ref, tag, source_format)
            if source.download_with_auth(token, archive_api_url, output_path):
                downloaded = True
                return downloaded
            self.logger.info(f"[{tag}] source asset: archive API download failed for format '{source_format}'")

        if not downloaded and source_resolved:
            self.logger.info(f"[{tag}] source asset: trying direct source URL with auth")
            if source.download_with_auth(token, source_resolved, output_path):
                downloaded = True
                return downloaded

        if not downloaded and source_resolved:
            self.logger.info(f"[{tag}] source asset: auth failed, trying private_token query param")
            private_url = source.add_private_token_query(source_resolved, token)
            if source.download_no_auth(private_url, output_path):
                downloaded = True

        if not downloaded:
            self.logger.info(f"[{tag}] source asset: all download strategies exhausted for format '{source_format}'")

        return downloaded

    def _summary_common(
        self,
        *,
        order: str,
        source_ref: ProviderRef,
        target_ref: ProviderRef,
        options: RuntimeOptions,
        tag_created: int,
        tag_skipped: int,
        tag_failed: int,
        tag_would_create: int,
        created: int,
        updated: int,
        skipped: int,
        failed: int,
        would_create: int,
        log_path: str,
        workdir: Path,
        checkpoint_path: str,
        failed_tags: set[str],
    ) -> None:
        sorted_failed_tags = sorted(failed_tags, key=self._tag_sort_key)
        failed_tags_path = workdir / "failed-tags.txt"
        failed_tags_path.write_text(
            "\n".join(sorted_failed_tags) + ("\n" if sorted_failed_tags else ""), encoding="utf-8"
        )

        retry_command = self._build_retry_command(options, failed_tags_path) if sorted_failed_tags else ""

        summary_payload = {
            "order": order,
            "source": source_ref.resource,
            "target": target_ref.resource,
            "tag_range": {
                "from": options.from_tag or "<start>",
                "to": options.to_tag or "<end>",
            },
            "dry_run": options.dry_run,
            "counts": {
                "tags_created": tag_created,
                "tags_skipped": tag_skipped,
                "tags_failed": tag_failed,
                "tags_would_create": tag_would_create,
                "releases_created": created,
                "releases_updated": updated,
                "releases_skipped": skipped,
                "releases_failed": failed,
                "releases_would_create": would_create,
            },
            "paths": {
                "jsonl_log": log_path,
                "checkpoint": checkpoint_path,
                "workdir": str(workdir),
                "failed_tags": str(failed_tags_path),
            },
            "failed_tags": sorted_failed_tags,
            "retry_command": retry_command,
        }

        summary_path = workdir / "summary.json"
        summary_path.write_text(json.dumps(summary_payload, ensure_ascii=True, indent=2) + "\n", encoding="utf-8")

        self.logger.info("Migration summary")
        self.logger.info(f"  Order: {order}")
        self.logger.info(f"  Source: {source_ref.resource}")
        self.logger.info(f"  Target: {target_ref.resource}")
        if options.from_tag or options.to_tag:
            self.logger.info(f"  Tag range: {options.from_tag or '<start>'} -> {options.to_tag or '<end>'}")
        else:
            self.logger.info("  Tag range: full")
        self.logger.info(f"  Dry-run: {str(options.dry_run).lower()}")
        self.logger.info(f"  Tags created: {tag_created}")
        self.logger.info(f"  Tags skipped: {tag_skipped}")
        self.logger.info(f"  Tags failed: {tag_failed}")
        self.logger.info(f"  Tags dry-run (would create): {tag_would_create}")
        self.logger.info(f"  Releases created: {created}")
        self.logger.info(f"  Releases updated: {updated}")
        self.logger.info(f"  Releases skipped: {skipped}")
        self.logger.info(f"  Releases failed: {failed}")
        self.logger.info(f"  Releases dry-run (would create): {would_create}")
        self.logger.info(f"  JSONL log: {log_path}")
        self.logger.info(f"  Summary JSON: {summary_path}")
        self.logger.info(f"  Failed tags file: {failed_tags_path}")
        self.logger.info(f"  Workdir: {workdir}")
        if retry_command:
            self.logger.info(f"  Retry command: {retry_command}")

    def _run_release_dispatch(
        self,
        ctx: MigrationContext,
        process_fn: Callable[[int, str], str],
    ) -> tuple[int, int, int, int, int]:
        created = updated = skipped = failed = would_create = 0

        def _consume(tag: str, result: str) -> None:
            nonlocal created, updated, skipped, failed, would_create
            if result == "created":
                created += 1
            elif result == "updated":
                updated += 1
            elif result == "skipped":
                skipped += 1
            elif result == "would_create":
                would_create += 1
            else:
                failed += 1
                ctx.failed_tags.add(tag)

        release_workers = max(1, min(ctx.options.release_workers, len(ctx.selected_tags)))
        if release_workers > 1:
            self.logger.info(f"Processing releases with {release_workers} workers")
            with ThreadPoolExecutor(max_workers=release_workers) as pool:
                future_map = {
                    pool.submit(process_fn, idx, tag): tag for idx, tag in enumerate(ctx.selected_tags, start=1)
                }
                for future in as_completed(future_map):
                    tag = future_map[future]
                    try:
                        result = future.result()
                    except Exception as exc:  # noqa: BLE001
                        self.logger.warn(f"[{tag}] failed on release worker: {exc}")
                        result = "failed"
                    _consume(tag, result)
        else:
            for idx, tag in enumerate(ctx.selected_tags, start=1):
                _consume(tag, process_fn(idx, tag))

        return created, updated, skipped, failed, would_create

    def _migrate_gitlab_to_github(
        self,
        options: RuntimeOptions,
        source_ref: ProviderRef,
        target_ref: ProviderRef,
        source: GitLabAdapter,
        target: GitHubAdapter,
    ) -> None:
        workdir = ensure_dir(options.effective_workdir())
        log_path = options.log_file or str(workdir / "migration-log.jsonl")
        Path(log_path).write_text("", encoding="utf-8")
        checkpoint_path = options.effective_checkpoint_file()
        checkpoint_signature = self._checkpoint_signature(options, source_ref, target_ref)
        checkpoint_state = load_checkpoint_state(checkpoint_path, checkpoint_signature)
        self.logger.info(f"Checkpoint loaded: {len(checkpoint_state)} entries")

        self.logger.info(f"Fetching releases from GitLab: {source_ref.resource}")
        releases = source.list_releases(source_ref, options.source_token)
        self.logger.info(f"Releases found in GitLab: {len(releases)}")

        self.logger.info(f"Fetching existing GitHub releases: {target_ref.resource}")
        target_release_tags = set(target.list_release_tags(target_ref, options.target_token))

        selected_tags = self._collect_selected_tags(releases, options.from_tag, options.to_tag)
        selected_tags = self._apply_tags_filter(selected_tags, options.tags_file)
        if not selected_tags:
            raise RuntimeError("No releases found in selected range")

        if options.from_tag or options.to_tag:
            from_tag = options.from_tag or "<start>"
            to_tag = options.to_tag or "<end>"
            self.logger.info(f"Selected releases in range {from_tag}..{to_tag}: {len(selected_tags)}")
        else:
            self.logger.info(f"Selected releases: {len(selected_tags)}")

        self.logger.info(f"Fetching existing GitHub tags: {target_ref.resource}")
        target_tags = set(target.list_tags(target_ref, options.target_token))

        tag_created = 0
        tag_skipped = 0
        tag_failed = 0
        tag_would_create = 0
        failed_tags: set[str] = set()

        if options.skip_tag_migration:
            self.logger.info("Tag migration is disabled (--skip-tags)")
        else:
            self.logger.info("Starting tag migration (tags first, then releases)")
            for idx, tag in enumerate(selected_tags, start=1):
                self._progress(idx, len(selected_tags), f"Tag {tag}", progress_bar=options.progress_bar)
                checkpoint_key = f"tag:{tag}"
                checkpoint_status = checkpoint_state.get(checkpoint_key, "")
                if is_terminal_tag_status(checkpoint_status) and tag in target_tags:
                    tag_skipped += 1
                    self._log(
                        log_path,
                        status="tag_skipped_existing",
                        tag=tag,
                        message=f"Checkpoint skip ({checkpoint_status})",
                        asset_count=0,
                        duration_ms=0,
                        dry_run=False,
                    )
                    self.logger.info(f"[{tag}] checkpoint skip: tag already processed")
                    continue

                if tag in target_tags:
                    tag_skipped += 1
                    self._log(
                        log_path,
                        status="tag_skipped_existing",
                        tag=tag,
                        message="Tag already exists in GitHub",
                        asset_count=0,
                        duration_ms=0,
                        dry_run=False,
                    )
                    self._checkpoint_mark(
                        checkpoint_path,
                        checkpoint_state,
                        signature=checkpoint_signature,
                        key=checkpoint_key,
                        tag=tag,
                        status="tag_skipped_existing",
                        message="Tag already exists in GitHub",
                    )
                    continue

                release_payload = self._release_by_tag(releases, tag)
                commit_sha = ""
                if release_payload:
                    commit = (
                        release_payload.get("commit", {}) if isinstance(release_payload.get("commit"), dict) else {}
                    )
                    commit_sha = str(commit.get("id", ""))
                if not commit_sha:
                    commit_sha = source.tag_commit_sha(source_ref, options.source_token, tag)

                if not commit_sha:
                    tag_failed += 1
                    failed_tags.add(tag)
                    self._log(
                        log_path,
                        status="tag_failed",
                        tag=tag,
                        message="Tag commit SHA not found in GitLab",
                        asset_count=0,
                        duration_ms=0,
                        dry_run=False,
                    )
                    self.logger.warn(f"[{tag}] tag migration failed: commit SHA not found")
                    continue

                if options.dry_run:
                    tag_would_create += 1
                    target_tags.add(tag)
                    self._log(
                        log_path,
                        status="tag_created",
                        tag=tag,
                        message="Dry-run: tag would be created",
                        asset_count=0,
                        duration_ms=0,
                        dry_run=True,
                    )
                    continue

                try:
                    target.create_tag_ref(target_ref, options.target_token, tag, commit_sha)
                    tag_created += 1
                    target_tags.add(tag)
                    self._log(
                        log_path,
                        status="tag_created",
                        tag=tag,
                        message="Tag migrated successfully",
                        asset_count=0,
                        duration_ms=0,
                        dry_run=False,
                    )
                    self._checkpoint_mark(
                        checkpoint_path,
                        checkpoint_state,
                        signature=checkpoint_signature,
                        key=checkpoint_key,
                        tag=tag,
                        status="tag_created",
                        message="Tag migrated successfully",
                    )
                except (HTTPRequestError, OSError, ValueError) as exc:
                    if isinstance(exc, AuthenticationError):
                        tag_failed += 1
                        failed_tags.add(tag)
                        self._log(
                            log_path,
                            status="tag_failed",
                            tag=tag,
                            message=f"Authentication error creating tag: {exc}",
                            asset_count=0,
                            duration_ms=0,
                            dry_run=False,
                        )
                        self.logger.warn(f"[{tag}] tag creation failed: authentication error: {exc}")
                    elif (
                        "409" in str(exc)
                        or "already exists" in str(exc).lower()
                        or target.tag_exists(target_ref, options.target_token, tag)
                    ):
                        tag_skipped += 1
                        target_tags.add(tag)
                        self._log(
                            log_path,
                            status="tag_skipped_existing",
                            tag=tag,
                            message="Tag detected after create attempt",
                            asset_count=0,
                            duration_ms=0,
                            dry_run=False,
                        )
                        self._checkpoint_mark(
                            checkpoint_path,
                            checkpoint_state,
                            signature=checkpoint_signature,
                            key=checkpoint_key,
                            tag=tag,
                            status="tag_skipped_existing",
                            message="Tag detected after create attempt",
                        )
                    else:
                        tag_failed += 1
                        failed_tags.add(tag)
                        self._log(
                            log_path,
                            status="tag_failed",
                            tag=tag,
                            message=f"Failed to create tag in GitHub: {exc}",
                            asset_count=0,
                            duration_ms=0,
                            dry_run=False,
                        )
                        self.logger.warn(f"[{tag}] failed to create tag in GitHub: {exc}")

        ctx = MigrationContext(
            source_ref=source_ref,
            target_ref=target_ref,
            source=source,
            target=target,
            options=options,
            log_path=log_path,
            workdir=workdir,
            checkpoint_path=checkpoint_path,
            checkpoint_signature=checkpoint_signature,
            checkpoint_state=checkpoint_state,
            selected_tags=selected_tags,
            target_tags=target_tags,
            target_release_tags=target_release_tags,
            failed_tags=failed_tags,
            releases=releases,
        )
        created, updated, skipped, failed, would_create = self._run_release_dispatch(
            ctx, lambda i, t: self._process_release_gl_to_gh(ctx, i, t)
        )

        self._summary_common(
            order="GitLab -> GitHub",
            source_ref=source_ref,
            target_ref=target_ref,
            options=options,
            tag_created=tag_created,
            tag_skipped=tag_skipped,
            tag_failed=tag_failed,
            tag_would_create=tag_would_create,
            created=created,
            updated=updated,
            skipped=skipped,
            failed=failed,
            would_create=would_create,
            log_path=log_path,
            workdir=workdir,
            checkpoint_path=checkpoint_path,
            failed_tags=failed_tags,
        )

        if failed > 0 or tag_failed > 0:
            raise RuntimeError("Migration finished with failures")

    def _process_release_gl_to_gh(self, ctx: MigrationContext, idx: int, tag: str) -> str:
        options = ctx.options
        source_ref = ctx.source_ref
        target_ref = ctx.target_ref
        source = ctx.source
        target = ctx.target
        workdir = ctx.workdir
        log_path = ctx.log_path
        checkpoint_path = ctx.checkpoint_path
        checkpoint_signature = ctx.checkpoint_signature
        checkpoint_state = ctx.checkpoint_state
        selected_tags = ctx.selected_tags
        target_release_tags = ctx.target_release_tags
        target_tags = ctx.target_tags
        releases = ctx.releases

        start = time.time()
        progress_text = self._progress_message(
            idx, len(selected_tags), f"Release {tag}", progress_bar=options.progress_bar
        )
        spinner_started = False
        if options.release_workers == 1:
            spinner_started = self.logger.start_spinner(progress_text)
        else:
            self._progress(idx, len(selected_tags), f"Release {tag}", progress_bar=options.progress_bar)

        try:
            checkpoint_key = f"release:{tag}"
            checkpoint_status = checkpoint_state.get(checkpoint_key, "")
            if is_terminal_release_status(checkpoint_status) and tag in target_release_tags:
                self._log(
                    log_path,
                    status="skipped_existing",
                    tag=tag,
                    message=f"Checkpoint skip ({checkpoint_status})",
                    asset_count=0,
                    duration_ms=0,
                    dry_run=False,
                )
                self.logger.info(f"[{tag}] checkpoint skip: release already processed")
                return "skipped"

            release_payload = self._release_by_tag(releases, tag)
            if not release_payload:
                self._log(
                    log_path,
                    status="failed",
                    tag=tag,
                    message="Release not found in GitLab payload",
                    asset_count=0,
                    duration_ms=0,
                    dry_run=False,
                )
                self.logger.warn(f"[{tag}] failed: release missing in payload")
                return "failed"

            canonical = source.to_canonical_release(release_payload)
            release_name = str(canonical.get("name") or tag)
            notes_file = workdir / f"release-{tag}-notes.md"
            notes_file.write_text(str(canonical.get("description_markdown", "")), encoding="utf-8")

            canonical_assets = canonical.get("assets")
            links = canonical_assets.get("links", []) if isinstance(canonical_assets, dict) else []
            sources = canonical_assets.get("sources", []) if isinstance(canonical_assets, dict) else []
            expected_link_assets = len(links)
            expected_assets = len(links) + len(sources)

            existing_release = False
            should_retry_existing = False
            existing_reason = ""

            if tag in target_release_tags:
                existing_release = True
                existing_payload = target.release_by_tag(target_ref, options.target_token, tag)
                if isinstance(existing_payload, dict):
                    draft = bool(existing_payload.get("draft", False))
                    existing_assets_raw = existing_payload.get("assets")
                    assets = existing_assets_raw if isinstance(existing_assets_raw, list) else []
                    assets_count = len(assets)
                    if draft:
                        should_retry_existing = True
                        existing_reason = "existing draft release"
                    elif assets_count < expected_link_assets:
                        should_retry_existing = True
                        existing_reason = (
                            f"existing release with incomplete required assets ({assets_count}/{expected_link_assets})"
                        )
                else:
                    should_retry_existing = True
                    existing_reason = "existing release with metadata lookup failure"

            if existing_release and not should_retry_existing:
                self._log(
                    log_path,
                    status="skipped_existing",
                    tag=tag,
                    message="Release already exists and is complete",
                    asset_count=expected_assets,
                    duration_ms=0,
                    dry_run=False,
                )
                self._checkpoint_mark(
                    checkpoint_path,
                    checkpoint_state,
                    signature=checkpoint_signature,
                    key=checkpoint_key,
                    tag=tag,
                    status="skipped_existing",
                    message="Release already exists and is complete",
                )
                self.logger.info(f"[{tag}] skip: release already exists and is complete")
                return "skipped"

            if tag not in target_tags:
                self._log(
                    log_path,
                    status="failed",
                    tag=tag,
                    message="Tag missing in GitHub after tag migration step",
                    asset_count=0,
                    duration_ms=0,
                    dry_run=False,
                )
                self.logger.warn(f"[{tag}] failed: tag not available in GitHub")
                return "failed"

            if options.dry_run:
                if existing_release:
                    self._log(
                        log_path,
                        status="updated",
                        tag=tag,
                        message=f"Dry-run: release would be resumed ({existing_reason})",
                        asset_count=expected_assets,
                        duration_ms=0,
                        dry_run=True,
                    )
                else:
                    self._log(
                        log_path,
                        status="created",
                        tag=tag,
                        message="Dry-run: release would be created",
                        asset_count=expected_assets,
                        duration_ms=0,
                        dry_run=True,
                    )
                return "would_create"

            release_dir = ensure_dir(workdir / f"release-{tag}")
            assets_dir = ensure_dir(release_dir / "assets")

            asset_files: list[str] = []
            asset_count = 0
            used_output_names: set[str] = set()
            missing_link_assets: list[dict[str, str]] = []
            missing_source_assets: list[dict[str, str]] = []

            link_jobs: list[dict[str, Any]] = []
            for link in links:
                link_name = str(link.get("name", "")).strip()
                direct_raw = str(link.get("direct_url", "")).strip()
                raw_url = str(link.get("url", "")).strip()

                direct_resolved = source.normalize_url(source_ref, direct_raw) if direct_raw else ""
                raw_resolved = source.normalize_url(source_ref, raw_url) if raw_url else ""

                if not direct_resolved and not raw_resolved:
                    self.logger.warn(f"[{tag}] link asset without URL")
                    missing_link_assets.append({"name": link_name or "asset", "url": ""})
                    continue

                if not link_name:
                    base = (direct_resolved or raw_resolved).split("?", 1)[0].split("/")[-1]
                    link_name = base or "asset"

                output_name = self._reserve_output_name(used_output_names, link_name)
                output_path = str((assets_dir / output_name).resolve())
                link_jobs.append(
                    {
                        "name": link_name,
                        "direct_resolved": direct_resolved,
                        "raw_resolved": raw_resolved,
                        "output_path": output_path,
                    }
                )

            def _run_link(job: dict[str, Any]) -> dict[str, Any]:
                ok = self._download_gitlab_link_asset(
                    source,
                    source_ref,
                    options.source_token,
                    tag,
                    direct_resolved=str(job.get("direct_resolved", "")),
                    raw_resolved=str(job.get("raw_resolved", "")),
                    output_path=str(job.get("output_path", "")),
                )
                return {
                    "ok": ok,
                    "name": str(job.get("name", "asset")),
                    "output_path": str(job.get("output_path", "")),
                }

            link_results = self._run_parallel_jobs(link_jobs, options.download_workers, _run_link)
            for job, result in zip(link_jobs, link_results):
                if not result.get("ok", False):
                    name = str(result.get("name", "asset"))
                    self.logger.warn(f"[{tag}] failed to download asset.link '{name}'")
                    missing_link_assets.append(
                        {
                            "name": name,
                            "url": str(job.get("direct_resolved", "") or job.get("raw_resolved", "")),
                        }
                    )
                    continue
                output_path = str(result.get("output_path", ""))
                if output_path:
                    asset_files.append(output_path)
                    asset_count += 1

            source_fallback_formats: list[str] = []
            source_tag_url = source.build_tag_url(source_ref, tag)

            source_jobs: list[dict[str, Any]] = []
            for source_asset in sources:
                source_url_raw = str(source_asset.get("url", "")).strip()
                source_format = str(source_asset.get("format", "source")).strip()
                source_name = str(source_asset.get("name", "")).strip()

                source_resolved = source.normalize_url(source_ref, source_url_raw) if source_url_raw else ""
                if not source_name:
                    base = source_resolved.split("?", 1)[0].split("/")[-1] if source_resolved else ""
                    source_name = base or f"{tag}.{source_format}"

                output_name = self._reserve_output_name(used_output_names, f"{source_format}-{source_name}")
                output_path = str((assets_dir / output_name).resolve())
                source_jobs.append(
                    {
                        "name": source_name,
                        "format": source_format,
                        "source_resolved": source_resolved,
                        "output_path": output_path,
                    }
                )

            def _run_source(job: dict[str, Any]) -> dict[str, Any]:
                ok = self._download_gitlab_source_asset(
                    source,
                    source_ref,
                    options.source_token,
                    tag,
                    source_format=str(job.get("format", "source")),
                    source_resolved=str(job.get("source_resolved", "")),
                    output_path=str(job.get("output_path", "")),
                )
                return {
                    "ok": ok,
                    "name": str(job.get("name", "source")),
                    "format": str(job.get("format", "source")),
                    "source_resolved": str(job.get("source_resolved", "")),
                    "output_path": str(job.get("output_path", "")),
                }

            source_results = self._run_parallel_jobs(source_jobs, options.download_workers, _run_source)
            failed_source_results: list[dict[str, Any]] = []
            for result in source_results:
                if result.get("ok", False):
                    output_path = str(result.get("output_path", ""))
                    if output_path:
                        asset_files.append(output_path)
                        asset_count += 1
                else:
                    failed_source_results.append(result)

            if failed_source_results:
                source_tag_exists = source.tag_exists(source_ref, options.source_token, tag)
                if source_tag_exists:
                    for result in failed_source_results:
                        fmt = str(result.get("format", "source"))
                        name = str(result.get("name", "source"))
                        source_fallback_formats.append(fmt)
                        self.logger.warn(f"[{tag}] source asset '{name}' unavailable, using tag link fallback")
                else:
                    for result in failed_source_results:
                        name = str(result.get("name", "source"))
                        resolved_url = str(result.get("source_resolved", ""))
                        self.logger.warn(f"[{tag}] source asset '{name}' unavailable and no tag fallback")
                        missing_source_assets.append({"name": name, "url": resolved_url})

            if source_fallback_formats:
                dedup_formats = sorted(set(source_fallback_formats))
                with notes_file.open("a", encoding="utf-8") as f:
                    f.write("\n\n### Source Archives Fallback\n")
                    f.write("Some source archives could not be downloaded during migration.\n")
                    f.write(f"Fallback formats: `{','.join(dedup_formats)}`\n")
                    f.write(f"GitLab tag: [{tag}]({source_tag_url})\n")

            if missing_link_assets or missing_source_assets:
                with notes_file.open("a", encoding="utf-8") as f:
                    f.write("\n\n### Missing Assets During Migration\n")
                    f.write("Some assets could not be downloaded and were not uploaded to this release.\n")
                    if missing_link_assets:
                        f.write("\n- Missing link assets:\n")
                        for item in missing_link_assets:
                            name = item.get("name", "asset")
                            url = item.get("url", "")
                            f.write(f"  - {name}: {url}\n" if url else f"  - {name}\n")
                    if missing_source_assets:
                        f.write("\n- Missing source assets:\n")
                        for item in missing_source_assets:
                            name = item.get("name", "source")
                            url = item.get("url", "")
                            f.write(f"  - {name}: {url}\n" if url else f"  - {name}\n")

            if expected_assets > 0 and asset_count == 0:
                self._log(
                    log_path,
                    status="failed",
                    tag=tag,
                    message="No release assets were downloaded",
                    asset_count=asset_count,
                    duration_ms=0,
                    dry_run=False,
                )
                self.logger.warn(f"[{tag}] failed: no assets downloaded")
                cleanup_dir(release_dir)
                return "failed"

            try:
                if not existing_release:
                    target.release_create(target_ref, options.target_token, tag, release_name, str(notes_file))
                target.release_upload(target_ref, options.target_token, tag, asset_files)
                target.release_edit(target_ref, options.target_token, tag, release_name, str(notes_file))
            except (HTTPRequestError, OSError, ValueError) as exc:
                self._log(
                    log_path,
                    status="failed",
                    tag=tag,
                    message=f"GitHub release operation failed: {exc}",
                    asset_count=asset_count,
                    duration_ms=0,
                    dry_run=False,
                )
                self.logger.warn(f"[{tag}] failed on GitHub release operation: {exc}")
                cleanup_dir(release_dir)
                return "failed"

            duration_ms = int((time.time() - start) * 1000)
            if existing_release:
                self._log(
                    log_path,
                    status="updated",
                    tag=tag,
                    message="Release resumed/updated successfully",
                    asset_count=asset_count,
                    duration_ms=duration_ms,
                    dry_run=False,
                )
                self._checkpoint_mark(
                    checkpoint_path,
                    checkpoint_state,
                    signature=checkpoint_signature,
                    key=checkpoint_key,
                    tag=tag,
                    status="updated",
                    message="Release resumed/updated successfully",
                )
                self.logger.info(f"[{tag}] resumed/updated with {asset_count} asset(s)")
                cleanup_dir(release_dir)
                return "updated"

            self._log(
                log_path,
                status="created",
                tag=tag,
                message="Release created successfully",
                asset_count=asset_count,
                duration_ms=duration_ms,
                dry_run=False,
            )
            self._checkpoint_mark(
                checkpoint_path,
                checkpoint_state,
                signature=checkpoint_signature,
                key=checkpoint_key,
                tag=tag,
                status="created",
                message="Release created successfully",
            )
            self.logger.info(f"[{tag}] created with {asset_count} asset(s)")
            cleanup_dir(release_dir)
            return "created"
        finally:
            if spinner_started:
                self.logger.stop_spinner()

    def _migrate_bitbucket_to_github(
        self,
        options: RuntimeOptions,
        source_ref: ProviderRef,
        target_ref: ProviderRef,
        source: BitbucketAdapter,
        target: GitHubAdapter,
    ) -> None:
        workdir = ensure_dir(options.effective_workdir())
        log_path = options.log_file or str(workdir / "migration-log.jsonl")
        Path(log_path).write_text("", encoding="utf-8")
        checkpoint_path = options.effective_checkpoint_file()
        checkpoint_signature = self._checkpoint_signature(options, source_ref, target_ref)
        checkpoint_state = load_checkpoint_state(checkpoint_path, checkpoint_signature)
        self.logger.info(f"Checkpoint loaded: {len(checkpoint_state)} entries")

        self.logger.info(f"Fetching releases from Bitbucket: {source_ref.resource}")
        releases = source.list_releases(source_ref, options.source_token)
        self.logger.info(f"Releases found in Bitbucket: {len(releases)}")

        self.logger.info(f"Fetching existing GitHub releases: {target_ref.resource}")
        target_release_tags = set(target.list_release_tags(target_ref, options.target_token))

        selected_tags = self._collect_selected_tags(releases, options.from_tag, options.to_tag)
        selected_tags = self._apply_tags_filter(selected_tags, options.tags_file)
        if not selected_tags:
            raise RuntimeError("No releases found in selected range")

        if options.from_tag or options.to_tag:
            from_tag = options.from_tag or "<start>"
            to_tag = options.to_tag or "<end>"
            self.logger.info(f"Selected releases in range {from_tag}..{to_tag}: {len(selected_tags)}")
        else:
            self.logger.info(f"Selected releases: {len(selected_tags)}")

        self.logger.info(f"Fetching existing GitHub tags: {target_ref.resource}")
        target_tags = set(target.list_tags(target_ref, options.target_token))

        tag_created = 0
        tag_skipped = 0
        tag_failed = 0
        tag_would_create = 0
        failed_tags: set[str] = set()

        if options.skip_tag_migration:
            self.logger.info("Tag migration is disabled (--skip-tags)")
        else:
            self.logger.info("Starting tag migration (tags first, then releases)")
            for idx, tag in enumerate(selected_tags, start=1):
                self._progress(idx, len(selected_tags), f"Tag {tag}", progress_bar=options.progress_bar)
                checkpoint_key = f"tag:{tag}"
                checkpoint_status = checkpoint_state.get(checkpoint_key, "")
                if is_terminal_tag_status(checkpoint_status) and tag in target_tags:
                    tag_skipped += 1
                    self._log(
                        log_path,
                        status="tag_skipped_existing",
                        tag=tag,
                        message=f"Checkpoint skip ({checkpoint_status})",
                        asset_count=0,
                        duration_ms=0,
                        dry_run=False,
                    )
                    self.logger.info(f"[{tag}] checkpoint skip: tag already processed")
                    continue

                if tag in target_tags:
                    tag_skipped += 1
                    self._log(
                        log_path,
                        status="tag_skipped_existing",
                        tag=tag,
                        message="Tag already exists in GitHub",
                        asset_count=0,
                        duration_ms=0,
                        dry_run=False,
                    )
                    self._checkpoint_mark(
                        checkpoint_path,
                        checkpoint_state,
                        signature=checkpoint_signature,
                        key=checkpoint_key,
                        tag=tag,
                        status="tag_skipped_existing",
                        message="Tag already exists in GitHub",
                    )
                    continue

                release_payload = self._release_by_tag(releases, tag)
                canonical = source.to_canonical_release(release_payload or {})
                commit_sha = ""
                try:
                    commit_sha = self._extract_source_commit_sha(
                        source, source_ref, options.source_token, tag, canonical
                    )
                except (HTTPRequestError, OSError, ValueError):
                    commit_sha = ""

                if not commit_sha:
                    tag_failed += 1
                    failed_tags.add(tag)
                    self._log(
                        log_path,
                        status="tag_failed",
                        tag=tag,
                        message="Tag commit SHA not found in Bitbucket",
                        asset_count=0,
                        duration_ms=0,
                        dry_run=False,
                    )
                    self.logger.warn(f"[{tag}] tag migration failed: commit SHA not found")
                    continue

                if options.dry_run:
                    tag_would_create += 1
                    target_tags.add(tag)
                    self._log(
                        log_path,
                        status="tag_created",
                        tag=tag,
                        message="Dry-run: tag would be created",
                        asset_count=0,
                        duration_ms=0,
                        dry_run=True,
                    )
                    continue

                try:
                    target.create_tag_ref(target_ref, options.target_token, tag, commit_sha)
                    tag_created += 1
                    target_tags.add(tag)
                    self._log(
                        log_path,
                        status="tag_created",
                        tag=tag,
                        message="Tag migrated successfully",
                        asset_count=0,
                        duration_ms=0,
                        dry_run=False,
                    )
                    self._checkpoint_mark(
                        checkpoint_path,
                        checkpoint_state,
                        signature=checkpoint_signature,
                        key=checkpoint_key,
                        tag=tag,
                        status="tag_created",
                        message="Tag migrated successfully",
                    )
                except (HTTPRequestError, OSError, ValueError) as exc:
                    if isinstance(exc, AuthenticationError):
                        tag_failed += 1
                        failed_tags.add(tag)
                        self._log(
                            log_path,
                            status="tag_failed",
                            tag=tag,
                            message=f"Authentication error creating tag: {exc}",
                            asset_count=0,
                            duration_ms=0,
                            dry_run=False,
                        )
                        self.logger.warn(f"[{tag}] tag creation failed: authentication error: {exc}")
                    elif (
                        "409" in str(exc)
                        or "already exists" in str(exc).lower()
                        or target.tag_exists(target_ref, options.target_token, tag)
                    ):
                        tag_skipped += 1
                        target_tags.add(tag)
                        self._log(
                            log_path,
                            status="tag_skipped_existing",
                            tag=tag,
                            message="Tag detected after create attempt",
                            asset_count=0,
                            duration_ms=0,
                            dry_run=False,
                        )
                        self._checkpoint_mark(
                            checkpoint_path,
                            checkpoint_state,
                            signature=checkpoint_signature,
                            key=checkpoint_key,
                            tag=tag,
                            status="tag_skipped_existing",
                            message="Tag detected after create attempt",
                        )
                    else:
                        tag_failed += 1
                        failed_tags.add(tag)
                        self._log(
                            log_path,
                            status="tag_failed",
                            tag=tag,
                            message=f"Failed to create tag in GitHub: {exc}",
                            asset_count=0,
                            duration_ms=0,
                            dry_run=False,
                        )
                        self.logger.warn(f"[{tag}] failed to create tag in GitHub: {exc}")

        ctx = MigrationContext(
            source_ref=source_ref,
            target_ref=target_ref,
            source=source,
            target=target,
            options=options,
            log_path=log_path,
            workdir=workdir,
            checkpoint_path=checkpoint_path,
            checkpoint_signature=checkpoint_signature,
            checkpoint_state=checkpoint_state,
            selected_tags=selected_tags,
            target_tags=target_tags,
            target_release_tags=target_release_tags,
            failed_tags=failed_tags,
            releases=releases,
        )
        created, updated, skipped, failed, would_create = self._run_release_dispatch(
            ctx, lambda i, t: self._process_release_bb_to_gh(ctx, i, t)
        )

        self._summary_common(
            order="Bitbucket -> GitHub",
            source_ref=source_ref,
            target_ref=target_ref,
            options=options,
            tag_created=tag_created,
            tag_skipped=tag_skipped,
            tag_failed=tag_failed,
            tag_would_create=tag_would_create,
            created=created,
            updated=updated,
            skipped=skipped,
            failed=failed,
            would_create=would_create,
            log_path=log_path,
            workdir=workdir,
            checkpoint_path=checkpoint_path,
            failed_tags=failed_tags,
        )

        if failed > 0 or tag_failed > 0:
            raise RuntimeError("Migration finished with failures")

    def _process_release_bb_to_gh(self, ctx: MigrationContext, idx: int, tag: str) -> str:
        options = ctx.options
        source_ref = ctx.source_ref
        target_ref = ctx.target_ref
        source = cast(BitbucketAdapter, ctx.source)
        target = cast(GitHubAdapter, ctx.target)
        workdir = ctx.workdir
        log_path = ctx.log_path
        checkpoint_path = ctx.checkpoint_path
        checkpoint_signature = ctx.checkpoint_signature
        checkpoint_state = ctx.checkpoint_state
        selected_tags = ctx.selected_tags
        target_release_tags = ctx.target_release_tags
        target_tags = ctx.target_tags
        releases = ctx.releases

        start = time.time()
        progress_text = self._progress_message(
            idx, len(selected_tags), f"Release {tag}", progress_bar=options.progress_bar
        )
        spinner_started = False
        if options.release_workers == 1:
            spinner_started = self.logger.start_spinner(progress_text)
        else:
            self._progress(idx, len(selected_tags), f"Release {tag}", progress_bar=options.progress_bar)

        try:
            checkpoint_key = f"release:{tag}"
            checkpoint_status = checkpoint_state.get(checkpoint_key, "")
            if is_terminal_release_status(checkpoint_status) and tag in target_release_tags:
                self._log(
                    log_path,
                    status="skipped_existing",
                    tag=tag,
                    message=f"Checkpoint skip ({checkpoint_status})",
                    asset_count=0,
                    duration_ms=0,
                    dry_run=False,
                )
                self.logger.info(f"[{tag}] checkpoint skip: release already processed")
                return "skipped"

            release_payload = self._release_by_tag(releases, tag)
            if not release_payload:
                self._log(
                    log_path,
                    status="failed",
                    tag=tag,
                    message="Release missing from Bitbucket payload",
                    asset_count=0,
                    duration_ms=0,
                    dry_run=False,
                )
                self.logger.warn(f"[{tag}] failed: release missing in payload")
                return "failed"

            canonical = source.to_canonical_release(release_payload)
            metadata_payload = canonical.get("provider_metadata")
            metadata = metadata_payload if isinstance(metadata_payload, dict) else {}
            legacy_no_manifest = bool(metadata.get("legacy_no_manifest", False))

            release_name = str(canonical.get("name") or tag)
            notes_file = workdir / f"release-{tag}-notes.md"
            notes_file.write_text(str(canonical.get("description_markdown", "")), encoding="utf-8")
            if legacy_no_manifest:
                self._append_bitbucket_legacy_notes(notes_file, source_ref=source_ref, tag=tag)

            canonical_assets = canonical.get("assets")
            links = canonical_assets.get("links", []) if isinstance(canonical_assets, dict) else []
            sources = canonical_assets.get("sources", []) if isinstance(canonical_assets, dict) else []
            expected_link_assets = len(links)
            expected_assets = len(links) + len(sources)

            existing_release = False
            should_retry_existing = False
            existing_reason = ""

            if tag in target_release_tags:
                existing_release = True
                existing_payload = target.release_by_tag(target_ref, options.target_token, tag)
                if isinstance(existing_payload, dict):
                    draft = bool(existing_payload.get("draft", False))
                    existing_assets_raw = existing_payload.get("assets")
                    assets = existing_assets_raw if isinstance(existing_assets_raw, list) else []
                    assets_count = len(assets)
                    if draft:
                        should_retry_existing = True
                        existing_reason = "existing draft release"
                    elif assets_count < expected_link_assets:
                        should_retry_existing = True
                        existing_reason = (
                            f"existing release with incomplete required assets ({assets_count}/{expected_link_assets})"
                        )
                else:
                    should_retry_existing = True
                    existing_reason = "existing release with metadata lookup failure"

            if existing_release and not should_retry_existing:
                self._log(
                    log_path,
                    status="skipped_existing",
                    tag=tag,
                    message="Release already exists and is complete",
                    asset_count=expected_assets,
                    duration_ms=0,
                    dry_run=False,
                )
                self._checkpoint_mark(
                    checkpoint_path,
                    checkpoint_state,
                    signature=checkpoint_signature,
                    key=checkpoint_key,
                    tag=tag,
                    status="skipped_existing",
                    message="Release already exists and is complete",
                )
                self.logger.info(f"[{tag}] skip: release already exists and is complete")
                return "skipped"

            if tag not in target_tags:
                self._log(
                    log_path,
                    status="failed",
                    tag=tag,
                    message="Tag missing in GitHub after tag migration step",
                    asset_count=0,
                    duration_ms=0,
                    dry_run=False,
                )
                self.logger.warn(f"[{tag}] failed: tag not available in GitHub")
                return "failed"

            if options.dry_run:
                if existing_release:
                    self._log(
                        log_path,
                        status="updated",
                        tag=tag,
                        message=f"Dry-run: release would be resumed ({existing_reason})",
                        asset_count=expected_assets,
                        duration_ms=0,
                        dry_run=True,
                    )
                else:
                    self._log(
                        log_path,
                        status="created",
                        tag=tag,
                        message="Dry-run: release would be created",
                        asset_count=expected_assets,
                        duration_ms=0,
                        dry_run=True,
                    )
                return "would_create"

            release_dir = ensure_dir(workdir / f"release-{tag}")
            assets_dir = ensure_dir(release_dir / "assets")
            asset_files: list[str] = []
            asset_count = 0
            used_output_names: set[str] = set()

            for link in links:
                link_name = str(link.get("name", "")).strip()
                raw_url = str(link.get("url", "")).strip()
                if not raw_url:
                    continue
                if not link_name:
                    link_name = raw_url.split("?", 1)[0].split("/")[-1] or "asset"
                output_name = self._reserve_output_name(used_output_names, link_name)
                output_path = str((assets_dir / output_name).resolve())
                if source.download_with_auth(options.source_token, raw_url, output_path):
                    asset_files.append(output_path)
                    asset_count += 1
                else:
                    self.logger.warn(f"[{tag}] failed to download asset.link '{link_name}'")

            for source_asset in sources:
                source_name = str(source_asset.get("name", "")).strip()
                source_url = str(source_asset.get("url", "")).strip()
                if not source_name:
                    source_name = source_url.split("?", 1)[0].split("/")[-1] if source_url else "source"
                if not source_url:
                    continue
                output_name = self._reserve_output_name(used_output_names, source_name)
                output_path = str((assets_dir / output_name).resolve())
                if source.download_with_auth(options.source_token, source_url, output_path):
                    asset_files.append(output_path)
                    asset_count += 1
                else:
                    self.logger.warn(f"[{tag}] failed to download source asset '{source_name}'")

            if expected_assets > 0 and asset_count == 0:
                self._log(
                    log_path,
                    status="failed",
                    tag=tag,
                    message="No release assets were downloaded",
                    asset_count=asset_count,
                    duration_ms=0,
                    dry_run=False,
                )
                self.logger.warn(f"[{tag}] failed: no assets downloaded")
                cleanup_dir(release_dir)
                return "failed"

            try:
                if not existing_release:
                    target.release_create(target_ref, options.target_token, tag, release_name, str(notes_file))
                target.release_upload(target_ref, options.target_token, tag, asset_files)
                target.release_edit(target_ref, options.target_token, tag, release_name, str(notes_file))
            except (HTTPRequestError, OSError, ValueError) as exc:
                self._log(
                    log_path,
                    status="failed",
                    tag=tag,
                    message=f"GitHub release operation failed: {exc}",
                    asset_count=asset_count,
                    duration_ms=0,
                    dry_run=False,
                )
                self.logger.warn(f"[{tag}] failed on GitHub release operation: {exc}")
                cleanup_dir(release_dir)
                return "failed"

            duration_ms = int((time.time() - start) * 1000)
            if existing_release:
                self._log(
                    log_path,
                    status="updated",
                    tag=tag,
                    message="Release resumed/updated successfully",
                    asset_count=asset_count,
                    duration_ms=duration_ms,
                    dry_run=False,
                )
                self._checkpoint_mark(
                    checkpoint_path,
                    checkpoint_state,
                    signature=checkpoint_signature,
                    key=checkpoint_key,
                    tag=tag,
                    status="updated",
                    message="Release resumed/updated successfully",
                )
                self.logger.info(f"[{tag}] resumed/updated with {asset_count} asset(s)")
                cleanup_dir(release_dir)
                return "updated"

            self._log(
                log_path,
                status="created",
                tag=tag,
                message="Release created successfully",
                asset_count=asset_count,
                duration_ms=duration_ms,
                dry_run=False,
            )
            self._checkpoint_mark(
                checkpoint_path,
                checkpoint_state,
                signature=checkpoint_signature,
                key=checkpoint_key,
                tag=tag,
                status="created",
                message="Release created successfully",
            )
            self.logger.info(f"[{tag}] created with {asset_count} asset(s)")
            cleanup_dir(release_dir)
            return "created"
        finally:
            if spinner_started:
                self.logger.stop_spinner()

    def _migrate_bitbucket_to_gitlab(
        self,
        options: RuntimeOptions,
        source_ref: ProviderRef,
        target_ref: ProviderRef,
        source: BitbucketAdapter,
        target: GitLabAdapter,
    ) -> None:
        workdir = ensure_dir(options.effective_workdir())
        log_path = options.log_file or str(workdir / "migration-log.jsonl")
        Path(log_path).write_text("", encoding="utf-8")
        checkpoint_path = options.effective_checkpoint_file()
        checkpoint_signature = self._checkpoint_signature(options, source_ref, target_ref)
        checkpoint_state = load_checkpoint_state(checkpoint_path, checkpoint_signature)
        self.logger.info(f"Checkpoint loaded: {len(checkpoint_state)} entries")

        self.logger.info(f"Fetching releases from Bitbucket: {source_ref.resource}")
        releases = source.list_releases(source_ref, options.source_token)
        self.logger.info(f"Releases found in Bitbucket: {len(releases)}")

        selected_tags = self._collect_selected_tags(releases, options.from_tag, options.to_tag)
        selected_tags = self._apply_tags_filter(selected_tags, options.tags_file)
        if not selected_tags:
            raise RuntimeError("No releases found in selected range")

        self.logger.info(f"Selected releases: {len(selected_tags)}")

        self.logger.info(f"Fetching existing GitLab tags: {target_ref.resource}")
        target_tags = set(target.list_tags(target_ref, options.target_token))

        tag_created = 0
        tag_skipped = 0
        tag_failed = 0
        tag_would_create = 0
        failed_tags: set[str] = set()

        if options.skip_tag_migration:
            self.logger.info("Tag migration is disabled (--skip-tags)")
        else:
            self.logger.info("Migrating tags from Bitbucket to GitLab")
            for idx, tag in enumerate(selected_tags, start=1):
                self._progress(idx, len(selected_tags), f"Tag {tag}", progress_bar=options.progress_bar)
                checkpoint_key = f"tag:{tag}"
                checkpoint_status = checkpoint_state.get(checkpoint_key, "")
                if is_terminal_tag_status(checkpoint_status) and tag in target_tags:
                    tag_skipped += 1
                    self._log(
                        log_path,
                        status="tag_skipped_existing",
                        tag=tag,
                        message=f"Checkpoint skip ({checkpoint_status})",
                        asset_count=0,
                        duration_ms=0,
                        dry_run=False,
                    )
                    self.logger.info(f"[{tag}] checkpoint skip: tag already processed")
                    continue

                if tag in target_tags or target.tag_exists(target_ref, options.target_token, tag):
                    target_tags.add(tag)
                    tag_skipped += 1
                    self._checkpoint_mark(
                        checkpoint_path,
                        checkpoint_state,
                        signature=checkpoint_signature,
                        key=checkpoint_key,
                        tag=tag,
                        status="tag_skipped_existing",
                        message="Tag already exists in GitLab",
                    )
                    continue

                release_payload = self._release_by_tag(releases, tag)
                canonical = source.to_canonical_release(release_payload or {})
                try:
                    commit_sha = self._extract_source_commit_sha(
                        source, source_ref, options.source_token, tag, canonical
                    )
                except (HTTPRequestError, OSError, ValueError) as exc:
                    tag_failed += 1
                    failed_tags.add(tag)
                    self.logger.warn(f"[{tag}] failed to migrate tag: commit SHA not found in Bitbucket: {exc}")
                    continue

                if not commit_sha:
                    tag_failed += 1
                    failed_tags.add(tag)
                    self.logger.warn(f"[{tag}] failed to migrate tag: empty commit SHA")
                    continue

                if options.dry_run:
                    tag_would_create += 1
                    target_tags.add(tag)
                    continue

                try:
                    target.create_tag(target_ref, options.target_token, tag, commit_sha)
                    tag_created += 1
                    target_tags.add(tag)
                    self._checkpoint_mark(
                        checkpoint_path,
                        checkpoint_state,
                        signature=checkpoint_signature,
                        key=checkpoint_key,
                        tag=tag,
                        status="tag_created",
                        message="Tag migrated successfully",
                    )
                except (HTTPRequestError, OSError, ValueError) as exc:
                    if isinstance(exc, AuthenticationError):
                        tag_failed += 1
                        failed_tags.add(tag)
                        self.logger.warn(f"[{tag}] tag creation failed: authentication error: {exc}")
                    elif (
                        "409" in str(exc)
                        or "already exists" in str(exc).lower()
                        or target.tag_exists(target_ref, options.target_token, tag)
                    ):
                        target_tags.add(tag)
                        tag_skipped += 1
                        self._checkpoint_mark(
                            checkpoint_path,
                            checkpoint_state,
                            signature=checkpoint_signature,
                            key=checkpoint_key,
                            tag=tag,
                            status="tag_skipped_existing",
                            message="Tag detected after create attempt",
                        )
                    else:
                        tag_failed += 1
                        failed_tags.add(tag)
                        self.logger.warn(f"[{tag}] failed to create tag in GitLab: {exc}")

        ctx = MigrationContext(
            source_ref=source_ref,
            target_ref=target_ref,
            source=source,
            target=target,
            options=options,
            log_path=log_path,
            workdir=workdir,
            checkpoint_path=checkpoint_path,
            checkpoint_signature=checkpoint_signature,
            checkpoint_state=checkpoint_state,
            selected_tags=selected_tags,
            target_tags=target_tags,
            target_release_tags=set(),
            failed_tags=failed_tags,
            releases=releases,
        )
        created, updated, skipped, failed, would_create = self._run_release_dispatch(
            ctx, lambda i, t: self._process_release_bb_to_gl(ctx, i, t)
        )

        self._summary_common(
            order="Bitbucket -> GitLab",
            source_ref=source_ref,
            target_ref=target_ref,
            options=options,
            tag_created=tag_created,
            tag_skipped=tag_skipped,
            tag_failed=tag_failed,
            tag_would_create=tag_would_create,
            created=created,
            updated=updated,
            skipped=skipped,
            failed=failed,
            would_create=would_create,
            log_path=log_path,
            workdir=workdir,
            checkpoint_path=checkpoint_path,
            failed_tags=failed_tags,
        )

        if failed > 0 or tag_failed > 0:
            raise RuntimeError("Migration finished with failures")

    def _process_release_bb_to_gl(self, ctx: MigrationContext, idx: int, tag: str) -> str:
        options = ctx.options
        source_ref = ctx.source_ref
        target_ref = ctx.target_ref
        source = cast(BitbucketAdapter, ctx.source)
        target = cast(GitLabAdapter, ctx.target)
        workdir = ctx.workdir
        log_path = ctx.log_path
        checkpoint_path = ctx.checkpoint_path
        checkpoint_signature = ctx.checkpoint_signature
        checkpoint_state = ctx.checkpoint_state
        selected_tags = ctx.selected_tags
        releases = ctx.releases

        start = time.time()
        progress_text = self._progress_message(
            idx, len(selected_tags), f"Release {tag}", progress_bar=options.progress_bar
        )
        spinner_started = False
        if options.release_workers == 1:
            spinner_started = self.logger.start_spinner(progress_text)
        else:
            self._progress(idx, len(selected_tags), f"Release {tag}", progress_bar=options.progress_bar)

        try:
            checkpoint_key = f"release:{tag}"
            checkpoint_status = checkpoint_state.get(checkpoint_key, "")
            if is_terminal_release_status(checkpoint_status) and target.release_exists(
                target_ref, options.target_token, tag
            ):
                self.logger.info(f"[{tag}] checkpoint skip: release already processed")
                return "skipped"

            release_payload = self._release_by_tag(releases, tag)
            if not release_payload:
                self.logger.warn(f"[{tag}] release missing from Bitbucket payload")
                self._log(
                    log_path,
                    status="failed",
                    tag=tag,
                    message="Release missing from Bitbucket payload",
                    asset_count=0,
                    duration_ms=0,
                    dry_run=False,
                )
                return "failed"

            canonical = source.to_canonical_release(release_payload)
            metadata_payload = canonical.get("provider_metadata")
            metadata = metadata_payload if isinstance(metadata_payload, dict) else {}
            legacy_no_manifest = bool(metadata.get("legacy_no_manifest", False))

            release_name = str(canonical.get("name") or tag)
            notes_file = workdir / f"release-{tag}-notes.md"
            notes_file.write_text(str(canonical.get("description_markdown", "")), encoding="utf-8")
            if legacy_no_manifest:
                self._append_bitbucket_legacy_notes(notes_file, source_ref=source_ref, tag=tag)

            canonical_assets = canonical.get("assets")
            links = canonical_assets.get("links", []) if isinstance(canonical_assets, dict) else []
            sources = canonical_assets.get("sources", []) if isinstance(canonical_assets, dict) else []
            expected_link_assets = len(links)
            expected_assets = len(links) + len(sources)

            existing_release = False
            should_retry_existing = False
            existing_reason = ""

            if target.release_exists(target_ref, options.target_token, tag):
                existing_release = True
                existing_payload = target.release_by_tag(target_ref, options.target_token, tag)
                existing_links_count = 0
                if isinstance(existing_payload, dict):
                    existing_assets_raw = existing_payload.get("assets")
                    assets = existing_assets_raw if isinstance(existing_assets_raw, dict) else {}
                    links_payload = assets.get("links", []) if isinstance(assets.get("links"), list) else []
                    existing_links_count = len(links_payload)

                if existing_links_count < expected_link_assets:
                    should_retry_existing = True
                    existing_reason = (
                        f"existing release with incomplete links ({existing_links_count}/{expected_link_assets})"
                    )

                if not should_retry_existing:
                    self.logger.info(f"[{tag}] skip: release already exists in GitLab and is complete")
                    self._checkpoint_mark(
                        checkpoint_path,
                        checkpoint_state,
                        signature=checkpoint_signature,
                        key=checkpoint_key,
                        tag=tag,
                        status="skipped_existing",
                        message="Release already exists in GitLab and is complete",
                    )
                    return "skipped"

            if options.dry_run:
                if existing_reason:
                    self.logger.info(f"[{tag}] dry-run: would update release ({existing_reason})")
                else:
                    self.logger.info(f"[{tag}] dry-run: would create release")
                return "would_create"

            release_dir = ensure_dir(workdir / f"release-{tag}")
            assets_dir = ensure_dir(release_dir / "assets")
            release_links: list[dict] = []
            downloaded_assets = 0
            missing_link_assets: list[dict[str, str]] = []
            missing_source_assets: list[dict[str, str]] = []

            for asset in links:
                asset_name = str(asset.get("name", "")).strip()
                asset_url = str(asset.get("url", "")).strip()

                if not asset_url:
                    missing_link_assets.append({"name": asset_name or "asset", "url": ""})
                    continue
                if not asset_name:
                    asset_name = asset_url.split("?", 1)[0].split("/")[-1] or "asset"

                output_name = unique_asset_filename(assets_dir, asset_name)
                output_path = str((assets_dir / output_name).resolve())
                downloaded = source.download_with_auth(options.source_token, asset_url, output_path)

                if downloaded:
                    downloaded_assets += 1
                    try:
                        uploaded_url = target.upload_file(target_ref, options.target_token, output_path)
                        release_links.append({"name": asset_name, "url": uploaded_url, "link_type": "package"})
                    except (HTTPRequestError, OSError, ValueError) as exc:
                        self.logger.warn(
                            f"[{tag}] upload failed for '{asset_name}', falling back to external link: {exc}"
                        )
                        release_links.append({"name": asset_name, "url": asset_url, "link_type": "other"})
                else:
                    self.logger.warn(
                        f"[{tag}] asset '{asset_name}' could not be uploaded to GitLab, adding external link"
                    )
                    missing_link_assets.append({"name": asset_name, "url": asset_url})
                    release_links.append({"name": asset_name, "url": asset_url, "link_type": "other"})

            for source_asset in sources:
                source_name = str(source_asset.get("name", "")).strip()
                source_url = str(source_asset.get("url", "")).strip()
                source_format = str(source_asset.get("format", "source")).strip()

                if not source_name:
                    source_name = f"{tag}-source.{source_format}"
                if not source_url:
                    missing_source_assets.append({"name": source_name, "url": ""})
                    continue

                output_name = unique_asset_filename(assets_dir, source_name)
                output_path = str((assets_dir / output_name).resolve())

                downloaded = source.download_with_auth(options.source_token, source_url, output_path)
                if downloaded:
                    downloaded_assets += 1
                    try:
                        uploaded_url = target.upload_file(target_ref, options.target_token, output_path)
                        release_links.append({"name": source_name, "url": uploaded_url, "link_type": "other"})
                    except (HTTPRequestError, OSError, ValueError) as exc:
                        self.logger.warn(f"[{tag}] upload failed for source '{source_name}': {exc}")
                        release_links.append({"name": source_name, "url": source_url, "link_type": "other"})
                else:
                    missing_source_assets.append({"name": source_name, "url": source_url})
                    release_links.append({"name": source_name, "url": source_url, "link_type": "other"})

            if legacy_no_manifest:
                tag_url = source.build_tag_url(source_ref, tag)
                release_links.append({"name": f"{tag}-tag-link", "url": tag_url, "link_type": "other"})

            if missing_link_assets or missing_source_assets:
                with notes_file.open("a", encoding="utf-8") as f:
                    f.write("\n\n### Missing Assets During Migration\n")
                    f.write("Some assets could not be downloaded and were not uploaded as binary files.\n")
                    if missing_link_assets:
                        f.write("\n- Missing link assets:\n")
                        for item in missing_link_assets:
                            name = item.get("name", "asset")
                            url = item.get("url", "")
                            f.write(f"  - {name}: {url}\n" if url else f"  - {name}\n")
                    if missing_source_assets:
                        f.write("\n- Missing source assets:\n")
                        for item in missing_source_assets:
                            name = item.get("name", "source")
                            url = item.get("url", "")
                            f.write(f"  - {name}: {url}\n" if url else f"  - {name}\n")

            if expected_assets > 0 and downloaded_assets == 0:
                self.logger.warn(f"[{tag}] failed: no assets downloaded")
                self._log(
                    log_path,
                    status="failed",
                    tag=tag,
                    message="No release assets were downloaded",
                    asset_count=0,
                    duration_ms=0,
                    dry_run=False,
                )
                cleanup_dir(release_dir)
                return "failed"

            try:
                target.create_or_update_release(
                    target_ref,
                    options.target_token,
                    tag,
                    release_name,
                    notes_file.read_text(encoding="utf-8"),
                    release_links,
                )
            except (HTTPRequestError, OSError, ValueError) as exc:
                self.logger.warn(f"[{tag}] failed to create/update release in GitLab: {exc}")
                self._log(
                    log_path,
                    status="failed",
                    tag=tag,
                    message=f"GitLab release operation failed: {exc}",
                    asset_count=downloaded_assets,
                    duration_ms=0,
                    dry_run=False,
                )
                cleanup_dir(release_dir)
                return "failed"

            cleanup_dir(release_dir)

            duration_ms = int((time.time() - start) * 1000)
            if existing_release:
                self._log(
                    log_path,
                    status="updated",
                    tag=tag,
                    message="Release migrated/updated in GitLab",
                    asset_count=downloaded_assets,
                    duration_ms=duration_ms,
                    dry_run=False,
                )
                self.logger.info(f"[{tag}] migrated/updated in GitLab")
                self._checkpoint_mark(
                    checkpoint_path,
                    checkpoint_state,
                    signature=checkpoint_signature,
                    key=checkpoint_key,
                    tag=tag,
                    status="updated",
                    message="Release migrated/updated in GitLab",
                )
                return "updated"

            self._log(
                log_path,
                status="created",
                tag=tag,
                message="Release created in GitLab",
                asset_count=downloaded_assets,
                duration_ms=duration_ms,
                dry_run=False,
            )
            self.logger.info(f"[{tag}] created in GitLab")
            self._checkpoint_mark(
                checkpoint_path,
                checkpoint_state,
                signature=checkpoint_signature,
                key=checkpoint_key,
                tag=tag,
                status="created",
                message="Release created in GitLab",
            )
            return "created"
        finally:
            if spinner_started:
                self.logger.stop_spinner()

    def _migrate_gitlab_to_bitbucket(
        self,
        options: RuntimeOptions,
        source_ref: ProviderRef,
        target_ref: ProviderRef,
        source: GitLabAdapter,
        target: BitbucketAdapter,
    ) -> None:
        workdir = ensure_dir(options.effective_workdir())
        log_path = options.log_file or str(workdir / "migration-log.jsonl")
        Path(log_path).write_text("", encoding="utf-8")
        checkpoint_path = options.effective_checkpoint_file()
        checkpoint_signature = self._checkpoint_signature(options, source_ref, target_ref)
        checkpoint_state = load_checkpoint_state(checkpoint_path, checkpoint_signature)
        self.logger.info(f"Checkpoint loaded: {len(checkpoint_state)} entries")

        self.logger.info(f"Fetching releases from GitLab: {source_ref.resource}")
        releases = source.list_releases(source_ref, options.source_token)
        self.logger.info(f"Releases found in GitLab: {len(releases)}")

        selected_tags = self._collect_selected_tags(releases, options.from_tag, options.to_tag)
        selected_tags = self._apply_tags_filter(selected_tags, options.tags_file)
        if not selected_tags:
            raise RuntimeError("No releases found in selected range")

        if options.from_tag or options.to_tag:
            from_tag = options.from_tag or "<start>"
            to_tag = options.to_tag or "<end>"
            self.logger.info(f"Selected releases in range {from_tag}..{to_tag}: {len(selected_tags)}")
        else:
            self.logger.info(f"Selected releases: {len(selected_tags)}")

        self.logger.info(f"Fetching existing Bitbucket tags: {target_ref.resource}")
        target_tags = set(target.list_tags(target_ref, options.target_token))

        tag_created = 0
        tag_skipped = 0
        tag_failed = 0
        tag_would_create = 0
        failed_tags: set[str] = set()

        if options.skip_tag_migration:
            self.logger.info("Tag migration is disabled (--skip-tags)")
        else:
            self.logger.info("Migrating tags from GitLab to Bitbucket")
            for idx, tag in enumerate(selected_tags, start=1):
                self._progress(idx, len(selected_tags), f"Tag {tag}", progress_bar=options.progress_bar)
                checkpoint_key = f"tag:{tag}"
                checkpoint_status = checkpoint_state.get(checkpoint_key, "")
                if is_terminal_tag_status(checkpoint_status) and tag in target_tags:
                    tag_skipped += 1
                    self._log(
                        log_path,
                        status="tag_skipped_existing",
                        tag=tag,
                        message=f"Checkpoint skip ({checkpoint_status})",
                        asset_count=0,
                        duration_ms=0,
                        dry_run=False,
                    )
                    self.logger.info(f"[{tag}] checkpoint skip: tag already processed")
                    continue

                if tag in target_tags or target.tag_exists(target_ref, options.target_token, tag):
                    target_tags.add(tag)
                    tag_skipped += 1
                    self._checkpoint_mark(
                        checkpoint_path,
                        checkpoint_state,
                        signature=checkpoint_signature,
                        key=checkpoint_key,
                        tag=tag,
                        status="tag_skipped_existing",
                        message="Tag already exists in Bitbucket",
                    )
                    continue

                release_payload = self._release_by_tag(releases, tag)
                canonical = source.to_canonical_release(release_payload or {})
                notes = str(canonical.get("description_markdown", ""))
                try:
                    commit_sha = self._extract_source_commit_sha(
                        source, source_ref, options.source_token, tag, canonical
                    )
                except (HTTPRequestError, OSError, ValueError) as exc:
                    tag_failed += 1
                    failed_tags.add(tag)
                    self.logger.warn(f"[{tag}] failed to migrate tag: commit SHA not found in GitLab: {exc}")
                    continue

                if not commit_sha:
                    tag_failed += 1
                    failed_tags.add(tag)
                    self.logger.warn(f"[{tag}] failed to migrate tag: empty commit SHA")
                    continue

                if options.dry_run:
                    tag_would_create += 1
                    target_tags.add(tag)
                    continue

                try:
                    target.create_tag(target_ref, options.target_token, tag, commit_sha, notes)
                    tag_created += 1
                    target_tags.add(tag)
                    self._checkpoint_mark(
                        checkpoint_path,
                        checkpoint_state,
                        signature=checkpoint_signature,
                        key=checkpoint_key,
                        tag=tag,
                        status="tag_created",
                        message="Tag migrated successfully",
                    )
                except (HTTPRequestError, OSError, ValueError) as exc:
                    if isinstance(exc, AuthenticationError):
                        tag_failed += 1
                        failed_tags.add(tag)
                        self.logger.warn(f"[{tag}] tag creation failed: authentication error: {exc}")
                    elif (
                        "409" in str(exc)
                        or "already exists" in str(exc).lower()
                        or target.tag_exists(target_ref, options.target_token, tag)
                    ):
                        target_tags.add(tag)
                        tag_skipped += 1
                        self._checkpoint_mark(
                            checkpoint_path,
                            checkpoint_state,
                            signature=checkpoint_signature,
                            key=checkpoint_key,
                            tag=tag,
                            status="tag_skipped_existing",
                            message="Tag detected after create attempt",
                        )
                    else:
                        tag_failed += 1
                        failed_tags.add(tag)
                        self.logger.warn(f"[{tag}] failed to create tag in Bitbucket: {exc}")

        ctx = MigrationContext(
            source_ref=source_ref,
            target_ref=target_ref,
            source=source,
            target=target,
            options=options,
            log_path=log_path,
            workdir=workdir,
            checkpoint_path=checkpoint_path,
            checkpoint_signature=checkpoint_signature,
            checkpoint_state=checkpoint_state,
            selected_tags=selected_tags,
            target_tags=target_tags,
            target_release_tags=target_tags,
            failed_tags=failed_tags,
            releases=releases,
        )
        created, updated, skipped, failed, would_create = self._run_release_dispatch(
            ctx, lambda i, t: self._process_release_gl_to_bb(ctx, i, t)
        )

        self._summary_common(
            order="GitLab -> Bitbucket",
            source_ref=source_ref,
            target_ref=target_ref,
            options=options,
            tag_created=tag_created,
            tag_skipped=tag_skipped,
            tag_failed=tag_failed,
            tag_would_create=tag_would_create,
            created=created,
            updated=updated,
            skipped=skipped,
            failed=failed,
            would_create=would_create,
            log_path=log_path,
            workdir=workdir,
            checkpoint_path=checkpoint_path,
            failed_tags=failed_tags,
        )

        if failed > 0 or tag_failed > 0:
            raise RuntimeError("Migration finished with failures")

    def _process_release_gl_to_bb(self, ctx: MigrationContext, idx: int, tag: str) -> str:
        options = ctx.options
        source_ref = ctx.source_ref
        target_ref = ctx.target_ref
        source = cast(GitLabAdapter, ctx.source)
        target = cast(BitbucketAdapter, ctx.target)
        workdir = ctx.workdir
        log_path = ctx.log_path
        checkpoint_path = ctx.checkpoint_path
        checkpoint_signature = ctx.checkpoint_signature
        checkpoint_state = ctx.checkpoint_state
        selected_tags = ctx.selected_tags
        target_tags = ctx.target_tags
        releases = ctx.releases

        start = time.time()
        progress_text = self._progress_message(
            idx, len(selected_tags), f"Release {tag}", progress_bar=options.progress_bar
        )
        spinner_started = False
        if options.release_workers == 1:
            spinner_started = self.logger.start_spinner(progress_text)
        else:
            self._progress(idx, len(selected_tags), f"Release {tag}", progress_bar=options.progress_bar)

        try:
            checkpoint_key = f"release:{tag}"
            checkpoint_status = checkpoint_state.get(checkpoint_key, "")
            manifest = target.read_release_manifest(target_ref, options.target_token, tag)
            if (
                is_terminal_release_status(checkpoint_status)
                and tag in target_tags
                and target.manifest_is_complete(manifest)
            ):
                self._log(
                    log_path,
                    status="skipped_existing",
                    tag=tag,
                    message=f"Checkpoint skip ({checkpoint_status})",
                    asset_count=0,
                    duration_ms=0,
                    dry_run=False,
                )
                self.logger.info(f"[{tag}] checkpoint skip: release already processed")
                return "skipped"

            release_payload = self._release_by_tag(releases, tag)
            if not release_payload:
                self._log(
                    log_path,
                    status="failed",
                    tag=tag,
                    message="Release not found in GitLab payload",
                    asset_count=0,
                    duration_ms=0,
                    dry_run=False,
                )
                self.logger.warn(f"[{tag}] failed: release missing in payload")
                return "failed"

            canonical = source.to_canonical_release(release_payload)
            release_name = str(canonical.get("name") or tag)
            notes_file = workdir / f"release-{tag}-notes.md"
            notes_file.write_text(str(canonical.get("description_markdown", "")), encoding="utf-8")

            canonical_assets = canonical.get("assets")
            links = canonical_assets.get("links", []) if isinstance(canonical_assets, dict) else []
            sources = canonical_assets.get("sources", []) if isinstance(canonical_assets, dict) else []
            expected_link_assets = len(links)
            expected_assets = len(links) + len(sources)

            existing_release = False
            should_retry_existing = False
            existing_reason = ""
            existing_manifest = target.read_release_manifest(target_ref, options.target_token, tag)
            if target.tag_exists(target_ref, options.target_token, tag):
                existing_release = True
                if target.manifest_is_complete(existing_manifest):
                    uploaded_assets = (
                        existing_manifest.get("uploaded_assets", []) if isinstance(existing_manifest, dict) else []
                    )
                    uploaded_count = len(uploaded_assets) if isinstance(uploaded_assets, list) else 0
                    if uploaded_count < expected_link_assets:
                        should_retry_existing = True
                        existing_reason = (
                            "existing Bitbucket release manifest with incomplete assets "
                            f"({uploaded_count}/{expected_link_assets})"
                        )
                else:
                    should_retry_existing = True
                    existing_reason = "existing Bitbucket tag without complete manifest"

            if existing_release and not should_retry_existing:
                self._log(
                    log_path,
                    status="skipped_existing",
                    tag=tag,
                    message="Bitbucket release already exists and is complete",
                    asset_count=expected_assets,
                    duration_ms=0,
                    dry_run=False,
                )
                self._checkpoint_mark(
                    checkpoint_path,
                    checkpoint_state,
                    signature=checkpoint_signature,
                    key=checkpoint_key,
                    tag=tag,
                    status="skipped_existing",
                    message="Bitbucket release already exists and is complete",
                )
                self.logger.info(f"[{tag}] skip: release already exists in Bitbucket and is complete")
                return "skipped"

            if tag not in target_tags:
                self._log(
                    log_path,
                    status="failed",
                    tag=tag,
                    message="Tag missing in Bitbucket after tag migration step",
                    asset_count=0,
                    duration_ms=0,
                    dry_run=False,
                )
                self.logger.warn(f"[{tag}] failed: tag not available in Bitbucket")
                return "failed"

            if options.dry_run:
                if existing_release:
                    self._log(
                        log_path,
                        status="updated",
                        tag=tag,
                        message=f"Dry-run: release would be resumed ({existing_reason})",
                        asset_count=expected_assets,
                        duration_ms=0,
                        dry_run=True,
                    )
                else:
                    self._log(
                        log_path,
                        status="created",
                        tag=tag,
                        message="Dry-run: release would be created",
                        asset_count=expected_assets,
                        duration_ms=0,
                        dry_run=True,
                    )
                return "would_create"

            if not existing_release:
                try:
                    commit_sha = self._extract_source_commit_sha(
                        source, source_ref, options.source_token, tag, canonical
                    )
                    if not commit_sha:
                        raise RuntimeError("Commit SHA not found for tag")
                    target.create_tag(
                        target_ref,
                        options.target_token,
                        tag,
                        commit_sha,
                        str(canonical.get("description_markdown", "")),
                    )
                    target_tags.add(tag)
                except (HTTPRequestError, OSError, ValueError, RuntimeError) as exc:
                    self._log(
                        log_path,
                        status="failed",
                        tag=tag,
                        message=f"Failed to create tag in Bitbucket: {exc}",
                        asset_count=0,
                        duration_ms=0,
                        dry_run=False,
                    )
                    self.logger.warn(f"[{tag}] failed to create Bitbucket tag for release: {exc}")
                    return "failed"

            release_dir = ensure_dir(workdir / f"release-{tag}")
            assets_dir = ensure_dir(release_dir / "assets")

            downloaded_assets = 0
            uploaded_assets: list[dict] = []
            missing_assets: list[dict] = []
            used_output_names: set[str] = set()

            for link in links:
                link_name = str(link.get("name", "")).strip()
                direct_raw = str(link.get("direct_url", "")).strip()
                raw_url = str(link.get("url", "")).strip()

                direct_resolved = source.normalize_url(source_ref, direct_raw) if direct_raw else ""
                raw_resolved = source.normalize_url(source_ref, raw_url) if raw_url else ""

                if not direct_resolved and not raw_resolved:
                    missing_assets.append({"name": link_name or "asset", "url": ""})
                    continue

                if not link_name:
                    base = (direct_resolved or raw_resolved).split("?", 1)[0].split("/")[-1]
                    link_name = base or "asset"

                output_name = self._reserve_output_name(used_output_names, link_name)
                output_path = str((assets_dir / output_name).resolve())

                downloaded = self._download_gitlab_link_asset(
                    source,
                    source_ref,
                    options.source_token,
                    tag,
                    direct_resolved=direct_resolved,
                    raw_resolved=raw_resolved,
                    output_path=output_path,
                )
                if not downloaded:
                    missing_assets.append({"name": link_name, "url": direct_resolved or raw_resolved})
                    continue

                downloaded_assets += 1
                try:
                    upload_payload = target.replace_download(
                        target_ref, options.target_token, output_path, upload_name=output_name
                    )
                    uploaded_url = target.download_url(upload_payload)
                    if not uploaded_url:
                        raise RuntimeError("Bitbucket upload did not return a downloadable URL")
                    uploaded_assets.append({"name": output_name, "url": uploaded_url, "type": "package"})
                except (HTTPRequestError, OSError, ValueError, RuntimeError) as exc:
                    self.logger.warn(f"[{tag}] failed to upload '{link_name}' to Bitbucket Downloads: {exc}")
                    missing_assets.append({"name": link_name, "url": direct_resolved or raw_resolved})

            for source_asset in sources:
                source_url_raw = str(source_asset.get("url", "")).strip()
                source_format = str(source_asset.get("format", "source")).strip()
                source_name = str(source_asset.get("name", "")).strip()

                source_resolved = source.normalize_url(source_ref, source_url_raw) if source_url_raw else ""
                if not source_name:
                    base = source_resolved.split("?", 1)[0].split("/")[-1] if source_resolved else ""
                    source_name = base or f"{tag}.{source_format}"

                output_name = self._reserve_output_name(used_output_names, source_name)
                output_path = str((assets_dir / output_name).resolve())
                downloaded = self._download_gitlab_source_asset(
                    source,
                    source_ref,
                    options.source_token,
                    tag,
                    source_format=source_format,
                    source_resolved=source_resolved,
                    output_path=output_path,
                )
                if not downloaded:
                    missing_assets.append({"name": source_name, "url": source_resolved})
                    continue

                downloaded_assets += 1
                try:
                    upload_payload = target.replace_download(
                        target_ref, options.target_token, output_path, upload_name=output_name
                    )
                    uploaded_url = target.download_url(upload_payload)
                    if not uploaded_url:
                        raise RuntimeError("Bitbucket upload did not return a downloadable URL")
                    uploaded_assets.append({"name": output_name, "url": uploaded_url, "type": "other"})
                except (HTTPRequestError, OSError, ValueError, RuntimeError) as exc:
                    self.logger.warn(f"[{tag}] failed to upload source '{source_name}' to Bitbucket Downloads: {exc}")
                    missing_assets.append({"name": source_name, "url": source_resolved})

            if expected_assets > 0 and downloaded_assets == 0:
                self._log(
                    log_path,
                    status="failed",
                    tag=tag,
                    message="No release assets were downloaded",
                    asset_count=0,
                    duration_ms=0,
                    dry_run=False,
                )
                self.logger.warn(f"[{tag}] failed: no assets downloaded")
                cleanup_dir(release_dir)
                return "failed"

            notes_text = notes_file.read_text(encoding="utf-8")
            manifest = target.build_release_manifest(
                tag=tag,
                release_name=release_name,
                notes=notes_text,
                uploaded_assets=uploaded_assets,
                missing_assets=missing_assets,
            )
            try:
                target.write_release_manifest(target_ref, options.target_token, tag, manifest)
            except (HTTPRequestError, OSError, ValueError, RuntimeError) as exc:
                self._log(
                    log_path,
                    status="failed",
                    tag=tag,
                    message=f"Bitbucket manifest operation failed: {exc}",
                    asset_count=downloaded_assets,
                    duration_ms=0,
                    dry_run=False,
                )
                self.logger.warn(f"[{tag}] failed to write Bitbucket release manifest: {exc}")
                cleanup_dir(release_dir)
                return "failed"

            cleanup_dir(release_dir)
            duration_ms = int((time.time() - start) * 1000)
            if existing_release:
                self._log(
                    log_path,
                    status="updated",
                    tag=tag,
                    message="Release migrated/updated in Bitbucket",
                    asset_count=downloaded_assets,
                    duration_ms=duration_ms,
                    dry_run=False,
                )
                self.logger.info(f"[{tag}] migrated/updated in Bitbucket")
                self._checkpoint_mark(
                    checkpoint_path,
                    checkpoint_state,
                    signature=checkpoint_signature,
                    key=checkpoint_key,
                    tag=tag,
                    status="updated",
                    message="Release migrated/updated in Bitbucket",
                )
                return "updated"

            self._log(
                log_path,
                status="created",
                tag=tag,
                message="Release created in Bitbucket",
                asset_count=downloaded_assets,
                duration_ms=duration_ms,
                dry_run=False,
            )
            self.logger.info(f"[{tag}] created in Bitbucket")
            self._checkpoint_mark(
                checkpoint_path,
                checkpoint_state,
                signature=checkpoint_signature,
                key=checkpoint_key,
                tag=tag,
                status="created",
                message="Release created in Bitbucket",
            )
            return "created"
        finally:
            if spinner_started:
                self.logger.stop_spinner()

    def _append_bitbucket_legacy_notes(self, notes_file: Path, *, source_ref: ProviderRef, tag: str) -> None:
        tag_url = f"{source_ref.base_url.rstrip('/')}/{source_ref.resource}/src/{tag}"
        with notes_file.open("a", encoding="utf-8") as f:
            f.write("\n\n### Legacy Bitbucket Release Metadata\n")
            f.write("This tag had no gfrm manifest in Bitbucket Downloads.\n")
            f.write(f"Bitbucket tag reference: [{tag}]({tag_url})\n")

    def _extract_source_commit_sha(
        self,
        source: Any,
        source_ref: ProviderRef,
        token: str,
        tag: str,
        canonical: dict,
    ) -> str:
        commit_sha = str(canonical.get("commit_sha", "")).strip()
        if commit_sha:
            return commit_sha
        if hasattr(source, "commit_sha_for_ref"):
            return source.commit_sha_for_ref(source_ref, token, tag)
        if hasattr(source, "tag_commit_sha"):
            return source.tag_commit_sha(source_ref, token, tag)
        return ""

    def _migrate_github_to_bitbucket(
        self,
        options: RuntimeOptions,
        source_ref: ProviderRef,
        target_ref: ProviderRef,
        source: GitHubAdapter,
        target: BitbucketAdapter,
    ) -> None:
        workdir = ensure_dir(options.effective_workdir())
        log_path = options.log_file or str(workdir / "migration-log.jsonl")
        Path(log_path).write_text("", encoding="utf-8")
        checkpoint_path = options.effective_checkpoint_file()
        checkpoint_signature = self._checkpoint_signature(options, source_ref, target_ref)
        checkpoint_state = load_checkpoint_state(checkpoint_path, checkpoint_signature)
        self.logger.info(f"Checkpoint loaded: {len(checkpoint_state)} entries")

        self.logger.info(f"Fetching releases from GitHub: {source_ref.resource}")
        releases = source.list_releases(source_ref, options.source_token)
        self.logger.info(f"Releases found in GitHub: {len(releases)}")

        selected_tags = self._collect_selected_tags(releases, options.from_tag, options.to_tag)
        selected_tags = self._apply_tags_filter(selected_tags, options.tags_file)
        if not selected_tags:
            raise RuntimeError("No releases found in selected range")

        self.logger.info(f"Selected releases: {len(selected_tags)}")

        self.logger.info(f"Fetching existing Bitbucket tags: {target_ref.resource}")
        target_tags = set(target.list_tags(target_ref, options.target_token))

        tag_created = 0
        tag_skipped = 0
        tag_failed = 0
        tag_would_create = 0
        failed_tags: set[str] = set()

        if options.skip_tag_migration:
            self.logger.info("Tag migration is disabled (--skip-tags)")
        else:
            self.logger.info("Migrating tags from GitHub to Bitbucket")
            for idx, tag in enumerate(selected_tags, start=1):
                self._progress(idx, len(selected_tags), f"Tag {tag}", progress_bar=options.progress_bar)
                checkpoint_key = f"tag:{tag}"
                checkpoint_status = checkpoint_state.get(checkpoint_key, "")
                if is_terminal_tag_status(checkpoint_status) and tag in target_tags:
                    tag_skipped += 1
                    self._log(
                        log_path,
                        status="tag_skipped_existing",
                        tag=tag,
                        message=f"Checkpoint skip ({checkpoint_status})",
                        asset_count=0,
                        duration_ms=0,
                        dry_run=False,
                    )
                    self.logger.info(f"[{tag}] checkpoint skip: tag already processed")
                    continue

                if tag in target_tags or target.tag_exists(target_ref, options.target_token, tag):
                    target_tags.add(tag)
                    tag_skipped += 1
                    self._checkpoint_mark(
                        checkpoint_path,
                        checkpoint_state,
                        signature=checkpoint_signature,
                        key=checkpoint_key,
                        tag=tag,
                        status="tag_skipped_existing",
                        message="Tag already exists in Bitbucket",
                    )
                    continue

                release_payload = self._release_by_tag(releases, tag)
                canonical = source.to_canonical_release(release_payload or {})
                notes = str(canonical.get("description_markdown", ""))
                try:
                    commit_sha = self._extract_source_commit_sha(
                        source, source_ref, options.source_token, tag, canonical
                    )
                except (HTTPRequestError, OSError, ValueError) as exc:
                    tag_failed += 1
                    failed_tags.add(tag)
                    self.logger.warn(f"[{tag}] failed to migrate tag: commit SHA not found in GitHub: {exc}")
                    continue

                if not commit_sha:
                    tag_failed += 1
                    failed_tags.add(tag)
                    self.logger.warn(f"[{tag}] failed to migrate tag: empty commit SHA")
                    continue

                if options.dry_run:
                    tag_would_create += 1
                    target_tags.add(tag)
                    continue

                try:
                    target.create_tag(target_ref, options.target_token, tag, commit_sha, notes)
                    tag_created += 1
                    target_tags.add(tag)
                    self._checkpoint_mark(
                        checkpoint_path,
                        checkpoint_state,
                        signature=checkpoint_signature,
                        key=checkpoint_key,
                        tag=tag,
                        status="tag_created",
                        message="Tag migrated successfully",
                    )
                except (HTTPRequestError, OSError, ValueError) as exc:
                    if isinstance(exc, AuthenticationError):
                        tag_failed += 1
                        failed_tags.add(tag)
                        self.logger.warn(f"[{tag}] tag creation failed: authentication error: {exc}")
                    elif (
                        "409" in str(exc)
                        or "already exists" in str(exc).lower()
                        or target.tag_exists(target_ref, options.target_token, tag)
                    ):
                        target_tags.add(tag)
                        tag_skipped += 1
                        self._checkpoint_mark(
                            checkpoint_path,
                            checkpoint_state,
                            signature=checkpoint_signature,
                            key=checkpoint_key,
                            tag=tag,
                            status="tag_skipped_existing",
                            message="Tag detected after create attempt",
                        )
                    else:
                        tag_failed += 1
                        failed_tags.add(tag)
                        self.logger.warn(f"[{tag}] failed to create tag in Bitbucket: {exc}")

        ctx = MigrationContext(
            source_ref=source_ref,
            target_ref=target_ref,
            source=source,
            target=target,
            options=options,
            log_path=log_path,
            workdir=workdir,
            checkpoint_path=checkpoint_path,
            checkpoint_signature=checkpoint_signature,
            checkpoint_state=checkpoint_state,
            selected_tags=selected_tags,
            target_tags=target_tags,
            target_release_tags=target_tags,
            failed_tags=failed_tags,
            releases=releases,
        )
        created, updated, skipped, failed, would_create = self._run_release_dispatch(
            ctx, lambda i, t: self._process_release_gh_to_bb(ctx, i, t)
        )

        self._summary_common(
            order="GitHub -> Bitbucket",
            source_ref=source_ref,
            target_ref=target_ref,
            options=options,
            tag_created=tag_created,
            tag_skipped=tag_skipped,
            tag_failed=tag_failed,
            tag_would_create=tag_would_create,
            created=created,
            updated=updated,
            skipped=skipped,
            failed=failed,
            would_create=would_create,
            log_path=log_path,
            workdir=workdir,
            checkpoint_path=checkpoint_path,
            failed_tags=failed_tags,
        )

        if failed > 0 or tag_failed > 0:
            raise RuntimeError("Migration finished with failures")

    def _process_release_gh_to_bb(self, ctx: MigrationContext, idx: int, tag: str) -> str:
        options = ctx.options
        source_ref = ctx.source_ref
        target_ref = ctx.target_ref
        source = cast(GitHubAdapter, ctx.source)
        target = cast(BitbucketAdapter, ctx.target)
        workdir = ctx.workdir
        log_path = ctx.log_path
        checkpoint_path = ctx.checkpoint_path
        checkpoint_signature = ctx.checkpoint_signature
        checkpoint_state = ctx.checkpoint_state
        selected_tags = ctx.selected_tags
        target_tags = ctx.target_tags
        releases = ctx.releases

        start = time.time()
        progress_text = self._progress_message(
            idx, len(selected_tags), f"Release {tag}", progress_bar=options.progress_bar
        )
        spinner_started = False
        if options.release_workers == 1:
            spinner_started = self.logger.start_spinner(progress_text)
        else:
            self._progress(idx, len(selected_tags), f"Release {tag}", progress_bar=options.progress_bar)

        try:
            checkpoint_key = f"release:{tag}"
            checkpoint_status = checkpoint_state.get(checkpoint_key, "")
            manifest = target.read_release_manifest(target_ref, options.target_token, tag)
            if (
                is_terminal_release_status(checkpoint_status)
                and tag in target_tags
                and target.manifest_is_complete(manifest)
            ):
                self._log(
                    log_path,
                    status="skipped_existing",
                    tag=tag,
                    message=f"Checkpoint skip ({checkpoint_status})",
                    asset_count=0,
                    duration_ms=0,
                    dry_run=False,
                )
                self.logger.info(f"[{tag}] checkpoint skip: release already processed")
                return "skipped"

            release_payload = self._release_by_tag(releases, tag)
            if not release_payload:
                self._log(
                    log_path,
                    status="failed",
                    tag=tag,
                    message="Release missing from GitHub payload",
                    asset_count=0,
                    duration_ms=0,
                    dry_run=False,
                )
                self.logger.warn(f"[{tag}] failed: release missing in payload")
                return "failed"

            canonical = source.to_canonical_release(release_payload)
            release_name = str(canonical.get("name") or tag)
            notes_file = workdir / f"release-{tag}-notes.md"
            notes_file.write_text(str(canonical.get("description_markdown", "")), encoding="utf-8")

            canonical_assets = canonical.get("assets")
            links = canonical_assets.get("links", []) if isinstance(canonical_assets, dict) else []
            sources = canonical_assets.get("sources", []) if isinstance(canonical_assets, dict) else []
            expected_link_assets = len(links)
            expected_assets = expected_link_assets + len(sources)

            existing_release = False
            should_retry_existing = False
            existing_reason = ""
            existing_manifest = target.read_release_manifest(target_ref, options.target_token, tag)
            if target.tag_exists(target_ref, options.target_token, tag):
                existing_release = True
                if target.manifest_is_complete(existing_manifest):
                    uploaded_assets = (
                        existing_manifest.get("uploaded_assets", []) if isinstance(existing_manifest, dict) else []
                    )
                    uploaded_count = len(uploaded_assets) if isinstance(uploaded_assets, list) else 0
                    if uploaded_count < expected_link_assets:
                        should_retry_existing = True
                        existing_reason = (
                            "existing Bitbucket release manifest with incomplete assets "
                            f"({uploaded_count}/{expected_link_assets})"
                        )
                else:
                    should_retry_existing = True
                    existing_reason = "existing Bitbucket tag without complete manifest"

            if existing_release and not should_retry_existing:
                self._log(
                    log_path,
                    status="skipped_existing",
                    tag=tag,
                    message="Bitbucket release already exists and is complete",
                    asset_count=expected_assets,
                    duration_ms=0,
                    dry_run=False,
                )
                self._checkpoint_mark(
                    checkpoint_path,
                    checkpoint_state,
                    signature=checkpoint_signature,
                    key=checkpoint_key,
                    tag=tag,
                    status="skipped_existing",
                    message="Bitbucket release already exists and is complete",
                )
                self.logger.info(f"[{tag}] skip: release already exists in Bitbucket and is complete")
                return "skipped"

            if tag not in target_tags:
                self._log(
                    log_path,
                    status="failed",
                    tag=tag,
                    message="Tag missing in Bitbucket after tag migration step",
                    asset_count=0,
                    duration_ms=0,
                    dry_run=False,
                )
                self.logger.warn(f"[{tag}] failed: tag not available in Bitbucket")
                return "failed"

            if options.dry_run:
                if existing_release:
                    self._log(
                        log_path,
                        status="updated",
                        tag=tag,
                        message=f"Dry-run: release would be resumed ({existing_reason})",
                        asset_count=expected_assets,
                        duration_ms=0,
                        dry_run=True,
                    )
                else:
                    self._log(
                        log_path,
                        status="created",
                        tag=tag,
                        message="Dry-run: release would be created",
                        asset_count=expected_assets,
                        duration_ms=0,
                        dry_run=True,
                    )
                return "would_create"

            if not existing_release:
                try:
                    commit_sha = self._extract_source_commit_sha(
                        source, source_ref, options.source_token, tag, canonical
                    )
                    if not commit_sha:
                        raise RuntimeError("Commit SHA not found for tag")
                    target.create_tag(
                        target_ref,
                        options.target_token,
                        tag,
                        commit_sha,
                        str(canonical.get("description_markdown", "")),
                    )
                    target_tags.add(tag)
                except (HTTPRequestError, OSError, ValueError, RuntimeError) as exc:
                    self._log(
                        log_path,
                        status="failed",
                        tag=tag,
                        message=f"Failed to create tag in Bitbucket: {exc}",
                        asset_count=0,
                        duration_ms=0,
                        dry_run=False,
                    )
                    self.logger.warn(f"[{tag}] failed to create Bitbucket tag for release: {exc}")
                    return "failed"

            release_dir = ensure_dir(workdir / f"release-{tag}")
            assets_dir = ensure_dir(release_dir / "assets")

            downloaded_assets = 0
            uploaded_assets: list[dict] = []
            missing_assets: list[dict] = []
            used_output_names: set[str] = set()

            for link in links:
                asset_name = str(link.get("name", "")).strip()
                asset_url = str(link.get("url", "")).strip()
                if not asset_url:
                    missing_assets.append({"name": asset_name or "asset", "url": ""})
                    continue
                if not asset_name:
                    asset_name = asset_url.split("?", 1)[0].split("/")[-1] or "asset"

                output_name = self._reserve_output_name(used_output_names, asset_name)
                output_path = str((assets_dir / output_name).resolve())
                downloaded = source.download_with_token(options.source_token, asset_url, output_path)
                if not downloaded:
                    missing_assets.append({"name": asset_name, "url": asset_url})
                    continue

                downloaded_assets += 1
                try:
                    upload_payload = target.replace_download(
                        target_ref, options.target_token, output_path, upload_name=output_name
                    )
                    uploaded_url = target.download_url(upload_payload)
                    if not uploaded_url:
                        raise RuntimeError("Bitbucket upload did not return a downloadable URL")
                    uploaded_assets.append({"name": output_name, "url": uploaded_url, "type": "package"})
                except (HTTPRequestError, OSError, ValueError, RuntimeError) as exc:
                    self.logger.warn(f"[{tag}] failed to upload '{asset_name}' to Bitbucket Downloads: {exc}")
                    missing_assets.append({"name": asset_name, "url": asset_url})

            for source_asset in sources:
                source_name = str(source_asset.get("name", "")).strip()
                source_url = str(source_asset.get("url", "")).strip()
                source_format = str(source_asset.get("format", "source")).strip()

                if not source_name:
                    source_name = f"{tag}-source.{source_format}"
                if not source_url:
                    missing_assets.append({"name": source_name, "url": ""})
                    continue

                output_name = self._reserve_output_name(used_output_names, source_name)
                output_path = str((assets_dir / output_name).resolve())
                downloaded = source.download_with_token(options.source_token, source_url, output_path)
                if not downloaded:
                    missing_assets.append({"name": source_name, "url": source_url})
                    continue

                downloaded_assets += 1
                try:
                    upload_payload = target.replace_download(
                        target_ref, options.target_token, output_path, upload_name=output_name
                    )
                    uploaded_url = target.download_url(upload_payload)
                    if not uploaded_url:
                        raise RuntimeError("Bitbucket upload did not return a downloadable URL")
                    uploaded_assets.append({"name": output_name, "url": uploaded_url, "type": "other"})
                except (HTTPRequestError, OSError, ValueError, RuntimeError) as exc:
                    self.logger.warn(f"[{tag}] failed to upload source '{source_name}' to Bitbucket Downloads: {exc}")
                    missing_assets.append({"name": source_name, "url": source_url})

            if expected_assets > 0 and downloaded_assets == 0:
                self._log(
                    log_path,
                    status="failed",
                    tag=tag,
                    message="No release assets were downloaded",
                    asset_count=0,
                    duration_ms=0,
                    dry_run=False,
                )
                self.logger.warn(f"[{tag}] failed: no assets downloaded")
                cleanup_dir(release_dir)
                return "failed"

            notes_text = notes_file.read_text(encoding="utf-8")
            manifest = target.build_release_manifest(
                tag=tag,
                release_name=release_name,
                notes=notes_text,
                uploaded_assets=uploaded_assets,
                missing_assets=missing_assets,
            )
            try:
                target.write_release_manifest(target_ref, options.target_token, tag, manifest)
            except (HTTPRequestError, OSError, ValueError, RuntimeError) as exc:
                self._log(
                    log_path,
                    status="failed",
                    tag=tag,
                    message=f"Bitbucket manifest operation failed: {exc}",
                    asset_count=downloaded_assets,
                    duration_ms=0,
                    dry_run=False,
                )
                self.logger.warn(f"[{tag}] failed to write Bitbucket release manifest: {exc}")
                cleanup_dir(release_dir)
                return "failed"

            cleanup_dir(release_dir)
            duration_ms = int((time.time() - start) * 1000)
            if existing_release:
                self._log(
                    log_path,
                    status="updated",
                    tag=tag,
                    message="Release migrated/updated in Bitbucket",
                    asset_count=downloaded_assets,
                    duration_ms=duration_ms,
                    dry_run=False,
                )
                self.logger.info(f"[{tag}] migrated/updated in Bitbucket")
                self._checkpoint_mark(
                    checkpoint_path,
                    checkpoint_state,
                    signature=checkpoint_signature,
                    key=checkpoint_key,
                    tag=tag,
                    status="updated",
                    message="Release migrated/updated in Bitbucket",
                )
                return "updated"

            self._log(
                log_path,
                status="created",
                tag=tag,
                message="Release created in Bitbucket",
                asset_count=downloaded_assets,
                duration_ms=duration_ms,
                dry_run=False,
            )
            self.logger.info(f"[{tag}] created in Bitbucket")
            self._checkpoint_mark(
                checkpoint_path,
                checkpoint_state,
                signature=checkpoint_signature,
                key=checkpoint_key,
                tag=tag,
                status="created",
                message="Release created in Bitbucket",
            )
            return "created"
        finally:
            if spinner_started:
                self.logger.stop_spinner()

    def _migrate_github_to_gitlab(
        self,
        options: RuntimeOptions,
        source_ref: ProviderRef,
        target_ref: ProviderRef,
        source: GitHubAdapter,
        target: GitLabAdapter,
    ) -> None:
        workdir = ensure_dir(options.effective_workdir())
        log_path = options.log_file or str(workdir / "migration-log.jsonl")
        Path(log_path).write_text("", encoding="utf-8")
        checkpoint_path = options.effective_checkpoint_file()
        checkpoint_signature = self._checkpoint_signature(options, source_ref, target_ref)
        checkpoint_state = load_checkpoint_state(checkpoint_path, checkpoint_signature)
        self.logger.info(f"Checkpoint loaded: {len(checkpoint_state)} entries")

        self.logger.info(f"Fetching releases from GitHub: {source_ref.resource}")
        releases = source.list_releases(source_ref, options.source_token)
        self.logger.info(f"Releases found in GitHub: {len(releases)}")

        selected_tags = self._collect_selected_tags(releases, options.from_tag, options.to_tag)
        selected_tags = self._apply_tags_filter(selected_tags, options.tags_file)
        if not selected_tags:
            raise RuntimeError("No releases found in selected range")

        self.logger.info(f"Selected releases: {len(selected_tags)}")

        self.logger.info(f"Fetching existing GitLab tags: {target_ref.resource}")
        target_tags = set(target.list_tags(target_ref, options.target_token))

        tag_created = 0
        tag_skipped = 0
        tag_failed = 0
        tag_would_create = 0
        failed_tags: set[str] = set()

        if options.skip_tag_migration:
            self.logger.info("Tag migration is disabled (--skip-tags)")
        else:
            self.logger.info("Migrating tags from GitHub to GitLab")
            for idx, tag in enumerate(selected_tags, start=1):
                self._progress(idx, len(selected_tags), f"Tag {tag}", progress_bar=options.progress_bar)
                checkpoint_key = f"tag:{tag}"
                checkpoint_status = checkpoint_state.get(checkpoint_key, "")
                if is_terminal_tag_status(checkpoint_status) and tag in target_tags:
                    tag_skipped += 1
                    self._log(
                        log_path,
                        status="tag_skipped_existing",
                        tag=tag,
                        message=f"Checkpoint skip ({checkpoint_status})",
                        asset_count=0,
                        duration_ms=0,
                        dry_run=False,
                    )
                    self.logger.info(f"[{tag}] checkpoint skip: tag already processed")
                    continue

                if tag in target_tags or target.tag_exists(target_ref, options.target_token, tag):
                    target_tags.add(tag)
                    tag_skipped += 1
                    self._checkpoint_mark(
                        checkpoint_path,
                        checkpoint_state,
                        signature=checkpoint_signature,
                        key=checkpoint_key,
                        tag=tag,
                        status="tag_skipped_existing",
                        message="Tag already exists in GitLab",
                    )
                    continue

                try:
                    commit_sha = source.commit_sha_for_ref(source_ref, options.source_token, tag)
                except (HTTPRequestError, OSError, ValueError) as exc:
                    tag_failed += 1
                    failed_tags.add(tag)
                    self.logger.warn(f"[{tag}] failed to migrate tag: commit SHA not found in GitHub: {exc}")
                    continue

                if options.dry_run:
                    tag_would_create += 1
                    continue

                try:
                    target.create_tag(target_ref, options.target_token, tag, commit_sha)
                    tag_created += 1
                    target_tags.add(tag)
                    self._checkpoint_mark(
                        checkpoint_path,
                        checkpoint_state,
                        signature=checkpoint_signature,
                        key=checkpoint_key,
                        tag=tag,
                        status="tag_created",
                        message="Tag migrated successfully",
                    )
                except (HTTPRequestError, OSError, ValueError) as exc:
                    if isinstance(exc, AuthenticationError):
                        tag_failed += 1
                        failed_tags.add(tag)
                        self.logger.warn(f"[{tag}] tag creation failed: authentication error: {exc}")
                    elif (
                        "409" in str(exc)
                        or "already exists" in str(exc).lower()
                        or target.tag_exists(target_ref, options.target_token, tag)
                    ):
                        target_tags.add(tag)
                        tag_skipped += 1
                        self._checkpoint_mark(
                            checkpoint_path,
                            checkpoint_state,
                            signature=checkpoint_signature,
                            key=checkpoint_key,
                            tag=tag,
                            status="tag_skipped_existing",
                            message="Tag detected after create attempt",
                        )
                    else:
                        tag_failed += 1
                        failed_tags.add(tag)
                        self.logger.warn(f"[{tag}] failed to create tag in GitLab: {exc}")

        ctx = MigrationContext(
            source_ref=source_ref,
            target_ref=target_ref,
            source=source,
            target=target,
            options=options,
            log_path=log_path,
            workdir=workdir,
            checkpoint_path=checkpoint_path,
            checkpoint_signature=checkpoint_signature,
            checkpoint_state=checkpoint_state,
            selected_tags=selected_tags,
            target_tags=target_tags,
            target_release_tags=set(),
            failed_tags=failed_tags,
            releases=releases,
        )
        created, updated, skipped, failed, would_create = self._run_release_dispatch(
            ctx, lambda i, t: self._process_release_gh_to_gl(ctx, i, t)
        )

        self._summary_common(
            order="GitHub -> GitLab",
            source_ref=source_ref,
            target_ref=target_ref,
            options=options,
            tag_created=tag_created,
            tag_skipped=tag_skipped,
            tag_failed=tag_failed,
            tag_would_create=tag_would_create,
            created=created,
            updated=updated,
            skipped=skipped,
            failed=failed,
            would_create=would_create,
            log_path=log_path,
            workdir=workdir,
            checkpoint_path=checkpoint_path,
            failed_tags=failed_tags,
        )

        if failed > 0 or tag_failed > 0:
            raise RuntimeError("Migration finished with failures")

    def _process_release_gh_to_gl(self, ctx: MigrationContext, idx: int, tag: str) -> str:
        options = ctx.options
        source_ref = ctx.source_ref
        target_ref = ctx.target_ref
        source = ctx.source
        target = ctx.target
        workdir = ctx.workdir
        log_path = ctx.log_path
        checkpoint_path = ctx.checkpoint_path
        checkpoint_signature = ctx.checkpoint_signature
        checkpoint_state = ctx.checkpoint_state
        selected_tags = ctx.selected_tags
        releases = ctx.releases

        start = time.time()
        progress_text = self._progress_message(
            idx, len(selected_tags), f"Release {tag}", progress_bar=options.progress_bar
        )
        spinner_started = False
        if options.release_workers == 1:
            spinner_started = self.logger.start_spinner(progress_text)
        else:
            self._progress(idx, len(selected_tags), f"Release {tag}", progress_bar=options.progress_bar)

        try:
            checkpoint_key = f"release:{tag}"
            checkpoint_status = checkpoint_state.get(checkpoint_key, "")
            if is_terminal_release_status(checkpoint_status) and target.release_exists(
                target_ref, options.target_token, tag
            ):
                self.logger.info(f"[{tag}] checkpoint skip: release already processed")
                return "skipped"

            release_payload = self._release_by_tag(releases, tag)
            if not release_payload:
                self.logger.warn(f"[{tag}] release missing from GitHub payload")
                self._log(
                    log_path,
                    status="failed",
                    tag=tag,
                    message="Release missing from GitHub payload",
                    asset_count=0,
                    duration_ms=0,
                    dry_run=False,
                )
                return "failed"

            canonical = source.to_canonical_release(release_payload)
            release_name = str(canonical.get("name") or tag)
            notes_file = workdir / f"release-{tag}-notes.md"
            notes_file.write_text(str(canonical.get("description_markdown", "")), encoding="utf-8")

            canonical_assets = canonical.get("assets")
            links = canonical_assets.get("links", []) if isinstance(canonical_assets, dict) else []
            sources = canonical_assets.get("sources", []) if isinstance(canonical_assets, dict) else []
            expected_link_assets = len(links)
            expected_assets = len(links) + len(sources)

            existing_release = False
            should_retry_existing = False
            existing_reason = ""

            if target.release_exists(target_ref, options.target_token, tag):
                existing_release = True
                existing_payload = target.release_by_tag(target_ref, options.target_token, tag)
                existing_links_count = 0
                if isinstance(existing_payload, dict):
                    existing_assets_raw = existing_payload.get("assets")
                    assets = existing_assets_raw if isinstance(existing_assets_raw, dict) else {}
                    links_payload = assets.get("links", []) if isinstance(assets.get("links"), list) else []
                    existing_links_count = len(links_payload)

                if existing_links_count < expected_link_assets:
                    should_retry_existing = True
                    existing_reason = (
                        f"existing release with incomplete links ({existing_links_count}/{expected_link_assets})"
                    )

                if not should_retry_existing:
                    self.logger.info(f"[{tag}] skip: release already exists in GitLab and is complete")
                    self._checkpoint_mark(
                        checkpoint_path,
                        checkpoint_state,
                        signature=checkpoint_signature,
                        key=checkpoint_key,
                        tag=tag,
                        status="skipped_existing",
                        message="Release already exists in GitLab and is complete",
                    )
                    return "skipped"

            if options.dry_run:
                if existing_reason:
                    self.logger.info(f"[{tag}] dry-run: would update release ({existing_reason})")
                else:
                    self.logger.info(f"[{tag}] dry-run: would create release")
                return "would_create"

            release_dir = ensure_dir(workdir / f"release-{tag}")
            assets_dir = ensure_dir(release_dir / "assets")
            release_links: list[dict] = []
            source_fallback_formats: list[str] = []
            source_fallback_url = source.build_tag_url(source_ref, tag)
            downloaded_assets = 0
            missing_link_assets: list[dict[str, str]] = []
            missing_source_assets: list[dict[str, str]] = []

            for asset in links:
                asset_name = str(asset.get("name", "")).strip()
                asset_url = str(asset.get("url", "")).strip()

                if not asset_url:
                    missing_link_assets.append({"name": asset_name or "asset", "url": ""})
                    continue
                if not asset_name:
                    asset_name = asset_url.split("?", 1)[0].split("/")[-1] or "asset"

                output_name = unique_asset_filename(assets_dir, asset_name)
                output_path = str((assets_dir / output_name).resolve())
                downloaded = source.download_with_token(options.source_token, asset_url, output_path)

                if downloaded:
                    downloaded_assets += 1
                    try:
                        uploaded_url = target.upload_file(target_ref, options.target_token, output_path)
                        release_links.append({"name": asset_name, "url": uploaded_url, "link_type": "package"})
                    except (HTTPRequestError, OSError, ValueError) as exc:
                        self.logger.warn(
                            f"[{tag}] upload failed for '{asset_name}', falling back to external link: {exc}"
                        )
                        release_links.append({"name": asset_name, "url": asset_url, "link_type": "other"})
                else:
                    self.logger.warn(
                        f"[{tag}] asset '{asset_name}' could not be uploaded to GitLab, adding external link"
                    )
                    missing_link_assets.append({"name": asset_name, "url": asset_url})
                    release_links.append({"name": asset_name, "url": asset_url, "link_type": "other"})

            for source_asset in sources:
                source_name = str(source_asset.get("name", "")).strip()
                source_url = str(source_asset.get("url", "")).strip()
                source_format = str(source_asset.get("format", "source")).strip()

                if not source_name:
                    source_name = f"{tag}-source.{source_format}"
                if not source_url:
                    missing_source_assets.append({"name": source_name, "url": ""})
                    continue

                output_name = unique_asset_filename(assets_dir, source_name)
                output_path = str((assets_dir / output_name).resolve())

                downloaded = source.download_with_token(options.source_token, source_url, output_path)
                if downloaded:
                    downloaded_assets += 1
                    try:
                        uploaded_url = target.upload_file(target_ref, options.target_token, output_path)
                        release_links.append({"name": source_name, "url": uploaded_url, "link_type": "other"})
                    except (HTTPRequestError, OSError, ValueError) as exc:
                        self.logger.warn(f"[{tag}] upload failed for source '{source_name}', using fallback: {exc}")
                        source_fallback_formats.append(source_format)
                else:
                    source_fallback_formats.append(source_format)
                    missing_source_assets.append({"name": source_name, "url": source_url})

            if source_fallback_formats:
                dedup_formats = sorted(set(source_fallback_formats))
                with notes_file.open("a", encoding="utf-8") as f:
                    f.write("\n\n### Source Archives Fallback\n")
                    f.write("Some source archives could not be downloaded.\n")
                    f.write(f"Fallback formats: `{','.join(dedup_formats)}`\n")
                    f.write(f"GitHub tag: [{tag}]({source_fallback_url})\n")
                release_links.append({"name": f"{tag}-tag-link", "url": source_fallback_url, "link_type": "other"})

            if missing_link_assets or missing_source_assets:
                with notes_file.open("a", encoding="utf-8") as f:
                    f.write("\n\n### Missing Assets During Migration\n")
                    f.write("Some assets could not be downloaded and were not uploaded as binary files.\n")
                    if missing_link_assets:
                        f.write("\n- Missing link assets:\n")
                        for item in missing_link_assets:
                            name = item.get("name", "asset")
                            url = item.get("url", "")
                            f.write(f"  - {name}: {url}\n" if url else f"  - {name}\n")
                    if missing_source_assets:
                        f.write("\n- Missing source assets:\n")
                        for item in missing_source_assets:
                            name = item.get("name", "source")
                            url = item.get("url", "")
                            f.write(f"  - {name}: {url}\n" if url else f"  - {name}\n")

            if expected_assets > 0 and downloaded_assets == 0:
                self.logger.warn(f"[{tag}] failed: no assets downloaded")
                self._log(
                    log_path,
                    status="failed",
                    tag=tag,
                    message="No release assets were downloaded",
                    asset_count=0,
                    duration_ms=0,
                    dry_run=False,
                )
                cleanup_dir(release_dir)
                return "failed"

            try:
                target.create_or_update_release(
                    target_ref,
                    options.target_token,
                    tag,
                    release_name,
                    notes_file.read_text(encoding="utf-8"),
                    release_links,
                )
            except (HTTPRequestError, OSError, ValueError) as exc:
                self.logger.warn(f"[{tag}] failed to create/update release in GitLab: {exc}")
                self._log(
                    log_path,
                    status="failed",
                    tag=tag,
                    message=f"GitLab release operation failed: {exc}",
                    asset_count=downloaded_assets,
                    duration_ms=0,
                    dry_run=False,
                )
                cleanup_dir(release_dir)
                return "failed"

            cleanup_dir(release_dir)

            duration_ms = int((time.time() - start) * 1000)
            if existing_release:
                self._log(
                    log_path,
                    status="updated",
                    tag=tag,
                    message="Release migrated/updated in GitLab",
                    asset_count=downloaded_assets,
                    duration_ms=duration_ms,
                    dry_run=False,
                )
                self.logger.info(f"[{tag}] migrated/updated in GitLab")
                self._checkpoint_mark(
                    checkpoint_path,
                    checkpoint_state,
                    signature=checkpoint_signature,
                    key=checkpoint_key,
                    tag=tag,
                    status="updated",
                    message="Release migrated/updated in GitLab",
                )
                return "updated"

            self._log(
                log_path,
                status="created",
                tag=tag,
                message="Release created in GitLab",
                asset_count=downloaded_assets,
                duration_ms=duration_ms,
                dry_run=False,
            )
            self.logger.info(f"[{tag}] created in GitLab")
            self._checkpoint_mark(
                checkpoint_path,
                checkpoint_state,
                signature=checkpoint_signature,
                key=checkpoint_key,
                tag=tag,
                status="created",
                message="Release created in GitLab",
            )
            return "created"
        finally:
            if spinner_started:
                self.logger.stop_spinner()
