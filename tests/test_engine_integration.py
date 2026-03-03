from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from git_forge_release_migrator.core.checkpoint import append_checkpoint
from git_forge_release_migrator.core.logging import ConsoleLogger
from git_forge_release_migrator.migrations.engine import MigrationEngine
from git_forge_release_migrator.models import RuntimeOptions
from git_forge_release_migrator.providers.base import ProviderRef
from git_forge_release_migrator.providers.registry import ProviderRegistry


def _source_ref() -> ProviderRef:
    return ProviderRef(
        provider="gitlab",
        raw_url="",
        base_url="https://gitlab.com",
        host="gitlab.com",
        resource="group/proj",
    )


def _target_ref() -> ProviderRef:
    return ProviderRef(
        provider="github",
        raw_url="",
        base_url="https://github.com",
        host="github.com",
        resource="owner/repo",
    )


def _options(tmp: str, *, tags_file: str = "", dry_run: bool = False) -> RuntimeOptions:
    return RuntimeOptions(
        source_provider="gitlab",
        source_url="https://gitlab.com/group/proj",
        source_token="glpat_x",
        target_provider="github",
        target_url="https://github.com/owner/repo",
        target_token="ghp_x",
        migration_order="gitlab-to-github",
        skip_tag_migration=True,
        workdir=tmp,
        checkpoint_file=str(Path(tmp) / "checkpoints" / "state.jsonl"),
        tags_file=tags_file,
        no_banner=True,
        save_session=False,
        dry_run=dry_run,
    )


class _FakeGitLabSource:
    def __init__(self) -> None:
        self._download_calls = 0

    def list_releases(self, ref: ProviderRef, token: str):
        del ref, token
        return [{"tag_name": "v1.0.0", "name": "v1.0.0", "description": "notes"}]

    def list_tags(self, ref: ProviderRef, token: str):
        del ref, token
        return ["v1.0.0"]

    def to_canonical_release(self, payload: dict):
        del payload
        return {
            "tag_name": "v1.0.0",
            "name": "Release 1",
            "description_markdown": "hello",
            "assets": {
                "links": [{"name": "app.apk", "url": "https://example.invalid/app.apk", "direct_url": ""}],
                "sources": [{"name": "src.zip", "url": "https://example.invalid/src.zip", "format": "zip"}],
            },
        }

    def normalize_url(self, ref: ProviderRef, url: str) -> str:
        del ref
        return url

    def download_with_auth(self, token: str, url: str, destination: str) -> bool:
        del token, url
        self._download_calls += 1
        # first download succeeds; second fails to force partial migration path
        if self._download_calls == 1:
            Path(destination).write_text("ok", encoding="utf-8")
            return True
        return False

    def download_no_auth(self, url: str, destination: str) -> bool:
        del url, destination
        return False

    def build_release_download_api_url(self, ref: ProviderRef, tag: str, resolved_url: str):
        del ref, tag, resolved_url
        return None

    def build_project_upload_api_url(self, ref: ProviderRef, resolved_url: str):
        del ref, resolved_url
        return None

    def add_private_token_query(self, url: str, token: str) -> str:
        return f"{url}?private_token={token}"

    def build_repository_archive_api_url(self, ref: ProviderRef, tag: str, fmt: str) -> str:
        del ref, tag, fmt
        return "https://example.invalid/archive"

    def tag_exists(self, ref: ProviderRef, token: str, tag: str) -> bool:
        del ref, token, tag
        return True

    def build_tag_url(self, ref: ProviderRef, tag: str) -> str:
        del ref
        return f"https://gitlab.example/tags/{tag}"

    def tag_commit_sha(self, ref: ProviderRef, token: str, tag: str) -> str:
        del ref, token, tag
        return "abc123"


class _MultiTagGitLabSource(_FakeGitLabSource):
    """Returns several semver releases; all assets download successfully."""

    _TAGS = ["v1.0.0", "v1.1.0", "v1.2.0", "v2.0.0"]

    def list_releases(self, ref: ProviderRef, token: str):
        del ref, token
        return [{"tag_name": t, "name": t, "description": "notes"} for t in self._TAGS]

    def list_tags(self, ref: ProviderRef, token: str):
        del ref, token
        return list(self._TAGS)

    def to_canonical_release(self, payload: dict):
        tag = str(payload.get("tag_name", ""))
        return {
            "tag_name": tag,
            "name": tag,
            "description_markdown": "notes",
            "assets": {
                "links": [{"name": "app.apk", "url": f"https://example.invalid/{tag}/app.apk", "direct_url": ""}],
                "sources": [],
            },
        }

    def download_with_auth(self, token: str, url: str, destination: str) -> bool:
        del token, url
        Path(destination).write_text("ok", encoding="utf-8")
        return True


class _FailingCreateGitLabSource(_FakeGitLabSource):
    """Returns two releases; the second one always fails to download any assets."""

    _TAGS = ["v1.0.0", "v1.1.0"]

    def list_releases(self, ref: ProviderRef, token: str):
        del ref, token
        return [{"tag_name": t, "name": t, "description": "notes"} for t in self._TAGS]

    def list_tags(self, ref: ProviderRef, token: str):
        del ref, token
        return list(self._TAGS)

    def to_canonical_release(self, payload: dict):
        tag = str(payload.get("tag_name", ""))
        return {
            "tag_name": tag,
            "name": tag,
            "description_markdown": "notes",
            "assets": {
                "links": [{"name": "app.apk", "url": f"https://example.invalid/{tag}/app.apk", "direct_url": ""}],
                "sources": [],
            },
        }

    def download_with_auth(self, token: str, url: str, destination: str) -> bool:
        del token
        # v1.1.0 assets always fail to download
        if "v1.1.0" in url:
            return False
        Path(destination).write_text("ok", encoding="utf-8")
        return True


class _FakeGitHubTarget:
    def __init__(self) -> None:
        self.created = 0
        self.uploaded_assets: list[str] = []

    def list_release_tags(self, ref: ProviderRef, token: str):
        del ref, token
        return []

    def list_tags(self, ref: ProviderRef, token: str):
        del ref, token
        return ["v1.0.0", "v1.1.0", "v1.2.0", "v2.0.0"]

    def release_by_tag(self, ref: ProviderRef, token: str, tag: str):
        del ref, token, tag
        return None

    def tag_exists(self, ref: ProviderRef, token: str, tag: str) -> bool:
        del ref, token, tag
        return True

    def release_create(self, ref: ProviderRef, token: str, tag: str, title: str, notes_file: str) -> None:
        del ref, token, tag, title, notes_file
        self.created += 1

    def release_upload(self, ref: ProviderRef, token: str, tag: str, assets: list[str]) -> None:
        del ref, token, tag
        self.uploaded_assets.extend(assets)

    def release_edit(self, ref: ProviderRef, token: str, tag: str, title: str, notes_file: str) -> None:
        del ref, token, tag, title, notes_file

    def create_tag_ref(self, ref: ProviderRef, token: str, tag: str, sha: str) -> None:
        del ref, token, tag, sha


class EngineIntegrationTests(unittest.TestCase):
    def test_gitlab_to_github_partial_assets_still_create_release(self) -> None:
        registry = ProviderRegistry.default()
        engine = MigrationEngine(registry=registry, logger=ConsoleLogger(quiet=True))

        source = _FakeGitLabSource()
        target = _FakeGitHubTarget()

        with tempfile.TemporaryDirectory() as tmp:
            tags_file = Path(tmp) / "tags.txt"
            tags_file.write_text("v1.0.0\n", encoding="utf-8")
            options = RuntimeOptions(
                source_provider="gitlab",
                source_url="https://gitlab.com/group/proj",
                source_token="glpat_x",
                target_provider="github",
                target_url="https://github.com/owner/repo",
                target_token="ghp_x",
                migration_order="gitlab-to-github",
                skip_tag_migration=True,
                workdir=tmp,
                checkpoint_file=str(Path(tmp) / "checkpoints" / "state.jsonl"),
                tags_file=str(tags_file),
                no_banner=True,
                save_session=False,
            )

            engine._migrate_gitlab_to_github(
                options, source_ref=_source_ref(), target_ref=_target_ref(), source=source, target=target
            )

            self.assertEqual(target.created, 1)
            self.assertEqual(len(target.uploaded_assets), 1)
            self.assertTrue((Path(tmp) / "summary.json").exists())
            self.assertTrue((Path(tmp) / "failed-tags.txt").exists())


class TagRangeFilteringTests(unittest.TestCase):
    def setUp(self) -> None:
        self.engine = MigrationEngine(registry=ProviderRegistry.default(), logger=ConsoleLogger(quiet=True))

    def _releases(self, tags: list[str]) -> list[dict]:
        return [{"tag_name": t, "name": t} for t in tags]

    def test_from_tag_filters_earlier_releases(self) -> None:
        releases = self._releases(["v1.0.0", "v1.1.0", "v1.2.0", "v2.0.0"])
        selected = self.engine._collect_selected_tags(releases, from_tag="v1.1.0", to_tag="")
        self.assertNotIn("v1.0.0", selected)
        self.assertIn("v1.1.0", selected)
        self.assertIn("v2.0.0", selected)

    def test_to_tag_filters_later_releases(self) -> None:
        releases = self._releases(["v1.0.0", "v1.1.0", "v1.2.0", "v2.0.0"])
        selected = self.engine._collect_selected_tags(releases, from_tag="", to_tag="v1.2.0")
        self.assertIn("v1.0.0", selected)
        self.assertIn("v1.2.0", selected)
        self.assertNotIn("v2.0.0", selected)

    def test_from_and_to_tag_both_inclusive(self) -> None:
        releases = self._releases(["v1.0.0", "v1.1.0", "v1.2.0", "v2.0.0"])
        selected = self.engine._collect_selected_tags(releases, from_tag="v1.1.0", to_tag="v1.2.0")
        self.assertEqual(sorted(selected), ["v1.1.0", "v1.2.0"])

    def test_no_range_returns_all(self) -> None:
        releases = self._releases(["v1.0.0", "v1.1.0", "v2.0.0"])
        selected = self.engine._collect_selected_tags(releases, from_tag="", to_tag="")
        self.assertEqual(len(selected), 3)

    def test_non_semver_tags_are_excluded(self) -> None:
        releases = self._releases(["v1.0.0", "latest", "beta-1", "v2.0.0"])
        selected = self.engine._collect_selected_tags(releases, from_tag="", to_tag="")
        self.assertNotIn("latest", selected)
        self.assertNotIn("beta-1", selected)
        self.assertIn("v1.0.0", selected)
        self.assertIn("v2.0.0", selected)

    def test_selected_tags_are_sorted_ascending(self) -> None:
        releases = self._releases(["v2.0.0", "v1.0.0", "v1.1.0"])
        selected = self.engine._collect_selected_tags(releases, from_tag="", to_tag="")
        self.assertEqual(selected, sorted(selected, key=self.engine._semver_key))


class CheckpointSkipTests(unittest.TestCase):
    def test_already_processed_release_is_skipped(self) -> None:
        registry = ProviderRegistry.default()
        engine = MigrationEngine(registry=registry, logger=ConsoleLogger(quiet=True))
        source = _MultiTagGitLabSource()
        with tempfile.TemporaryDirectory() as tmp:
            tags_file = Path(tmp) / "tags.txt"
            tags_file.write_text("v1.0.0\n", encoding="utf-8")
            checkpoint_file = str(Path(tmp) / "checkpoints" / "state.jsonl")
            opts = _options(tmp, tags_file=str(tags_file))

            # Pre-populate checkpoint so v1.0.0 release appears already processed
            signature = engine._checkpoint_signature(opts, _source_ref(), _target_ref())
            append_checkpoint(
                checkpoint_file,
                signature=signature,
                key="release:v1.0.0",
                tag="v1.0.0",
                status="created",
                message="already done",
            )

            # Patch target to report v1.0.0 as already having a release
            target_with_existing = _FakeGitHubTarget()

            def _list_release_tags_with_v100(ref: ProviderRef, token: str):
                del ref, token
                return ["v1.0.0"]

            target_with_existing.list_release_tags = _list_release_tags_with_v100

            engine._migrate_gitlab_to_github(
                opts, source_ref=_source_ref(), target_ref=_target_ref(), source=source, target=target_with_existing
            )

            # v1.0.0 was in checkpoint+target so should be skipped (not re-created)
            self.assertEqual(target_with_existing.created, 0)

    def test_checkpoint_state_loaded_before_migration(self) -> None:
        """Verify checkpoint file is read at migration start and influences skip logic."""
        registry = ProviderRegistry.default()
        engine = MigrationEngine(registry=registry, logger=ConsoleLogger(quiet=True))
        source = _FakeGitLabSource()

        with tempfile.TemporaryDirectory() as tmp:
            tags_file = Path(tmp) / "tags.txt"
            tags_file.write_text("v1.0.0\n", encoding="utf-8")
            checkpoint_file = str(Path(tmp) / "checkpoints" / "state.jsonl")
            opts = _options(tmp, tags_file=str(tags_file))

            sig = engine._checkpoint_signature(opts, _source_ref(), _target_ref())
            # Write a non-terminal status — should NOT skip
            append_checkpoint(
                checkpoint_file,
                signature=sig,
                key="release:v1.0.0",
                tag="v1.0.0",
                status="failed",
                message="previous failure",
            )

            target = _FakeGitHubTarget()
            engine._migrate_gitlab_to_github(
                opts, source_ref=_source_ref(), target_ref=_target_ref(), source=source, target=target
            )
            # Non-terminal status should NOT prevent retry
            self.assertEqual(target.created, 1)


class DryRunTests(unittest.TestCase):
    def test_dry_run_does_not_create_releases(self) -> None:
        registry = ProviderRegistry.default()
        engine = MigrationEngine(registry=registry, logger=ConsoleLogger(quiet=True))
        source = _MultiTagGitLabSource()
        target = _FakeGitHubTarget()

        with tempfile.TemporaryDirectory() as tmp:
            tags_file = Path(tmp) / "tags.txt"
            tags_file.write_text("v1.0.0\nv1.1.0\n", encoding="utf-8")
            opts = _options(tmp, tags_file=str(tags_file), dry_run=True)

            engine._migrate_gitlab_to_github(
                opts, source_ref=_source_ref(), target_ref=_target_ref(), source=source, target=target
            )

            self.assertEqual(target.created, 0)
            self.assertEqual(target.uploaded_assets, [])

    def test_dry_run_writes_summary_json(self) -> None:
        registry = ProviderRegistry.default()
        engine = MigrationEngine(registry=registry, logger=ConsoleLogger(quiet=True))
        source = _MultiTagGitLabSource()
        target = _FakeGitHubTarget()

        with tempfile.TemporaryDirectory() as tmp:
            tags_file = Path(tmp) / "tags.txt"
            tags_file.write_text("v1.0.0\n", encoding="utf-8")
            opts = _options(tmp, tags_file=str(tags_file), dry_run=True)

            engine._migrate_gitlab_to_github(
                opts, source_ref=_source_ref(), target_ref=_target_ref(), source=source, target=target
            )

            self.assertTrue((Path(tmp) / "summary.json").exists())

    def test_dry_run_summary_has_would_create_count(self) -> None:
        import json

        registry = ProviderRegistry.default()
        engine = MigrationEngine(registry=registry, logger=ConsoleLogger(quiet=True))
        source = _MultiTagGitLabSource()
        target = _FakeGitHubTarget()

        with tempfile.TemporaryDirectory() as tmp:
            tags_file = Path(tmp) / "tags.txt"
            tags_file.write_text("v1.0.0\nv1.1.0\n", encoding="utf-8")
            opts = _options(tmp, tags_file=str(tags_file), dry_run=True)

            engine._migrate_gitlab_to_github(
                opts, source_ref=_source_ref(), target_ref=_target_ref(), source=source, target=target
            )

            summary = json.loads((Path(tmp) / "summary.json").read_text(encoding="utf-8"))
            self.assertEqual(summary["counts"]["releases_would_create"], 2)
            self.assertEqual(summary["dry_run"], True)


class FailedTagsFileTests(unittest.TestCase):
    def test_failed_tags_file_written_on_partial_failure(self) -> None:
        registry = ProviderRegistry.default()
        engine = MigrationEngine(registry=registry, logger=ConsoleLogger(quiet=True))
        source = _FailingCreateGitLabSource()
        target = _FakeGitHubTarget()

        with tempfile.TemporaryDirectory() as tmp:
            tags_file = Path(tmp) / "tags.txt"
            tags_file.write_text("v1.0.0\nv1.1.0\n", encoding="utf-8")
            opts = _options(tmp, tags_file=str(tags_file))

            try:
                engine._migrate_gitlab_to_github(
                    opts, source_ref=_source_ref(), target_ref=_target_ref(), source=source, target=target
                )
            except RuntimeError:
                pass  # expected: "Migration finished with failures"

            failed_tags_path = Path(tmp) / "failed-tags.txt"
            self.assertTrue(failed_tags_path.exists())
            failed = failed_tags_path.read_text(encoding="utf-8").strip().splitlines()
            self.assertIn("v1.1.0", failed)
            self.assertNotIn("v1.0.0", failed)

    def test_failed_tags_file_empty_on_full_success(self) -> None:
        registry = ProviderRegistry.default()
        engine = MigrationEngine(registry=registry, logger=ConsoleLogger(quiet=True))
        source = _FakeGitLabSource()
        target = _FakeGitHubTarget()

        with tempfile.TemporaryDirectory() as tmp:
            tags_file = Path(tmp) / "tags.txt"
            tags_file.write_text("v1.0.0\n", encoding="utf-8")
            opts = _options(tmp, tags_file=str(tags_file))

            engine._migrate_gitlab_to_github(
                opts, source_ref=_source_ref(), target_ref=_target_ref(), source=source, target=target
            )

            failed_tags_path = Path(tmp) / "failed-tags.txt"
            self.assertTrue(failed_tags_path.exists())
            content = failed_tags_path.read_text(encoding="utf-8").strip()
            self.assertEqual(content, "")


if __name__ == "__main__":
    unittest.main()
