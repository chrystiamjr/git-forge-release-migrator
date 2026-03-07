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


def _bitbucket_ref() -> ProviderRef:
    return ProviderRef(
        provider="bitbucket",
        raw_url="",
        base_url="https://bitbucket.org",
        host="bitbucket.org",
        resource="workspace/repo",
        metadata={
            "workspace": "workspace",
            "repo": "repo",
            "workspace_encoded": "workspace",
            "repo_encoded": "repo",
            "repo_ref": "workspace/repo",
        },
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


def _options_for(
    tmp: str,
    *,
    source_provider: str,
    source_url: str,
    target_provider: str,
    target_url: str,
    tags_file: str = "",
    dry_run: bool = False,
    skip_tag_migration: bool = True,
) -> RuntimeOptions:
    return RuntimeOptions(
        source_provider=source_provider,
        source_url=source_url,
        source_token="src_tok",
        target_provider=target_provider,
        target_url=target_url,
        target_token="dst_tok",
        migration_order=f"{source_provider}-to-{target_provider}",
        skip_tag_migration=skip_tag_migration,
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


class _FakeGitHubSource:
    def list_releases(self, ref: ProviderRef, token: str):
        del ref, token
        return [
            {
                "tag_name": "v1.0.0",
                "name": "Release 1",
                "body": "notes",
                "assets": [{"name": "app.zip", "browser_download_url": "https://example.invalid/app.zip"}],
                "zipball_url": "",
                "tarball_url": "",
            }
        ]

    def to_canonical_release(self, payload: dict):
        del payload
        return {
            "tag_name": "v1.0.0",
            "name": "Release 1",
            "description_markdown": "notes",
            "commit_sha": "abc123",
            "assets": {
                "links": [{"name": "app.zip", "url": "https://example.invalid/app.zip", "direct_url": ""}],
                "sources": [],
            },
        }

    def commit_sha_for_ref(self, ref: ProviderRef, token: str, ref_name: str) -> str:
        del ref, token, ref_name
        return "abc123"

    def download_with_token(self, token: str, url: str, destination: str) -> bool:
        del token, url
        Path(destination).write_text("ok", encoding="utf-8")
        return True


class _FakeBitbucketTarget:
    def __init__(self) -> None:
        self.tags: set[str] = set()
        self.manifests: dict[str, dict] = {}
        self.uploaded_names: list[str] = []
        self.create_tag_calls = 0

    def list_tags(self, ref: ProviderRef, token: str) -> list[str]:
        del ref, token
        return sorted(self.tags)

    def tag_exists(self, ref: ProviderRef, token: str, tag: str) -> bool:
        del ref, token
        return tag in self.tags

    def create_tag(self, ref: ProviderRef, token: str, tag: str, ref_sha: str, message: str = "") -> None:
        del ref, token, ref_sha, message
        self.create_tag_calls += 1
        self.tags.add(tag)

    def read_release_manifest(self, ref: ProviderRef, token: str, tag: str) -> dict | None:
        del ref, token
        return self.manifests.get(tag)

    def manifest_is_complete(self, manifest: dict | None) -> bool:
        if not isinstance(manifest, dict):
            return False
        missing = manifest.get("missing_assets")
        return isinstance(missing, list) and len(missing) == 0

    def replace_download(self, ref: ProviderRef, token: str, filepath: str, *, upload_name: str = "") -> dict:
        del ref, token, filepath
        name = upload_name or "asset.bin"
        self.uploaded_names.append(name)
        return {"name": name, "links": {"download": {"href": f"https://download.invalid/{name}"}}}

    def download_url(self, item: dict) -> str:
        links = item.get("links", {}) if isinstance(item.get("links"), dict) else {}
        download = links.get("download", {}) if isinstance(links.get("download"), dict) else {}
        return str(download.get("href", ""))

    def build_release_manifest(
        self,
        *,
        tag: str,
        release_name: str,
        notes: str,
        uploaded_assets: list[dict],
        missing_assets: list[dict],
    ) -> dict:
        del notes
        return {
            "version": 1,
            "tag_name": tag,
            "release_name": release_name,
            "notes_hash": "hash",
            "uploaded_assets": uploaded_assets,
            "missing_assets": missing_assets,
            "updated_at": "2026-01-01T00:00:00Z",
        }

    def write_release_manifest(self, ref: ProviderRef, token: str, tag: str, manifest: dict) -> None:
        del ref, token
        self.manifests[tag] = manifest


class _FakeBitbucketSource:
    def __init__(self, *, legacy_no_manifest: bool = False) -> None:
        self.legacy_no_manifest = legacy_no_manifest

    def list_releases(self, ref: ProviderRef, token: str):
        del ref, token
        links = [] if self.legacy_no_manifest else [{"name": "app.zip", "url": "https://example.invalid/app.zip"}]
        return [
            {
                "tag_name": "v1.0.0",
                "name": "Release 1",
                "description_markdown": "notes",
                "commit_sha": "abc123",
                "assets": {"links": links, "sources": []},
                "provider_metadata": {
                    "manifest_found": not self.legacy_no_manifest,
                    "legacy_no_manifest": self.legacy_no_manifest,
                    "manifest": {},
                },
            }
        ]

    def to_canonical_release(self, payload: dict):
        return payload

    def tag_commit_sha(self, ref: ProviderRef, token: str, tag: str) -> str:
        del ref, token, tag
        return "abc123"

    def download_with_auth(self, token: str, url: str, destination: str) -> bool:
        del token, url
        Path(destination).write_text("ok", encoding="utf-8")
        return True

    def build_tag_url(self, ref: ProviderRef, tag: str) -> str:
        del ref
        return f"https://bitbucket.org/workspace/repo/src/{tag}"


class _FakeGitLabTarget:
    def __init__(self) -> None:
        self.updated = 0
        self.last_links: list[dict] = []

    def list_tags(self, ref: ProviderRef, token: str):
        del ref, token
        return ["v1.0.0"]

    def tag_exists(self, ref: ProviderRef, token: str, tag: str) -> bool:
        del ref, token, tag
        return True

    def create_tag(self, ref: ProviderRef, token: str, tag: str, ref_sha: str) -> None:
        del ref, token, tag, ref_sha

    def release_exists(self, ref: ProviderRef, token: str, tag: str) -> bool:
        del ref, token, tag
        return False

    def release_by_tag(self, ref: ProviderRef, token: str, tag: str):
        del ref, token, tag
        return None

    def upload_file(self, ref: ProviderRef, token: str, filepath: str) -> str:
        del ref, token, filepath
        return "https://gitlab.invalid/uploads/file"

    def create_or_update_release(
        self, ref: ProviderRef, token: str, tag: str, name: str, description: str, links: list[dict]
    ) -> None:
        del ref, token, tag, name, description
        self.updated += 1
        self.last_links = links


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


class BitbucketCrossForgeFlowTests(unittest.TestCase):
    def test_github_to_bitbucket_happy_path(self) -> None:
        registry = ProviderRegistry.default()
        engine = MigrationEngine(registry=registry, logger=ConsoleLogger(quiet=True))
        source = _FakeGitHubSource()
        target = _FakeBitbucketTarget()

        with tempfile.TemporaryDirectory() as tmp:
            tags_file = Path(tmp) / "tags.txt"
            tags_file.write_text("v1.0.0\n", encoding="utf-8")
            opts = _options_for(
                tmp,
                source_provider="github",
                source_url="https://github.com/owner/repo",
                target_provider="bitbucket",
                target_url="https://bitbucket.org/workspace/repo",
                tags_file=str(tags_file),
                skip_tag_migration=False,
            )

            engine._migrate_github_to_bitbucket(
                opts,
                source_ref=_target_ref(),
                target_ref=_bitbucket_ref(),
                source=source,
                target=target,
            )

            self.assertIn("v1.0.0", target.tags)
            self.assertIn("v1.0.0", target.manifests)
            manifest = target.manifests["v1.0.0"]
            self.assertEqual(len(manifest["uploaded_assets"]), 1)

    def test_github_to_bitbucket_existing_complete_manifest_skips(self) -> None:
        registry = ProviderRegistry.default()
        engine = MigrationEngine(registry=registry, logger=ConsoleLogger(quiet=True))
        source = _FakeGitHubSource()
        target = _FakeBitbucketTarget()
        target.tags.add("v1.0.0")
        target.manifests["v1.0.0"] = {
            "version": 1,
            "tag_name": "v1.0.0",
            "release_name": "Release 1",
            "notes_hash": "hash",
            "uploaded_assets": [{"name": "app.zip", "url": "https://download.invalid/app.zip", "type": "package"}],
            "missing_assets": [],
            "updated_at": "2026-01-01T00:00:00Z",
        }

        with tempfile.TemporaryDirectory() as tmp:
            tags_file = Path(tmp) / "tags.txt"
            tags_file.write_text("v1.0.0\n", encoding="utf-8")
            opts = _options_for(
                tmp,
                source_provider="github",
                source_url="https://github.com/owner/repo",
                target_provider="bitbucket",
                target_url="https://bitbucket.org/workspace/repo",
                tags_file=str(tags_file),
                skip_tag_migration=True,
            )

            engine._migrate_github_to_bitbucket(
                opts,
                source_ref=_target_ref(),
                target_ref=_bitbucket_ref(),
                source=source,
                target=target,
            )

            self.assertEqual(target.create_tag_calls, 0)
            self.assertEqual(target.uploaded_names, [])

    def test_gitlab_to_bitbucket_dry_run(self) -> None:
        import json

        registry = ProviderRegistry.default()
        engine = MigrationEngine(registry=registry, logger=ConsoleLogger(quiet=True))
        source = _FakeGitLabSource()
        target = _FakeBitbucketTarget()

        with tempfile.TemporaryDirectory() as tmp:
            tags_file = Path(tmp) / "tags.txt"
            tags_file.write_text("v1.0.0\n", encoding="utf-8")
            opts = _options_for(
                tmp,
                source_provider="gitlab",
                source_url="https://gitlab.com/group/proj",
                target_provider="bitbucket",
                target_url="https://bitbucket.org/workspace/repo",
                tags_file=str(tags_file),
                dry_run=True,
                skip_tag_migration=False,
            )

            engine._migrate_gitlab_to_bitbucket(
                opts,
                source_ref=_source_ref(),
                target_ref=_bitbucket_ref(),
                source=source,
                target=target,
            )

            summary = json.loads((Path(tmp) / "summary.json").read_text(encoding="utf-8"))
            self.assertEqual(summary["counts"]["releases_would_create"], 1)
            self.assertEqual(target.create_tag_calls, 0)
            self.assertEqual(target.manifests, {})

    def test_bitbucket_to_github_legacy_without_manifest(self) -> None:
        registry = ProviderRegistry.default()
        engine = MigrationEngine(registry=registry, logger=ConsoleLogger(quiet=True))
        source = _FakeBitbucketSource(legacy_no_manifest=True)
        target = _FakeGitHubTarget()

        with tempfile.TemporaryDirectory() as tmp:
            tags_file = Path(tmp) / "tags.txt"
            tags_file.write_text("v1.0.0\n", encoding="utf-8")
            opts = _options_for(
                tmp,
                source_provider="bitbucket",
                source_url="https://bitbucket.org/workspace/repo",
                target_provider="github",
                target_url="https://github.com/owner/repo",
                tags_file=str(tags_file),
                skip_tag_migration=True,
            )

            engine._migrate_bitbucket_to_github(
                opts,
                source_ref=_bitbucket_ref(),
                target_ref=_target_ref(),
                source=source,
                target=target,
            )

            self.assertEqual(target.created, 1)

    def test_bitbucket_to_gitlab_legacy_adds_tag_link(self) -> None:
        registry = ProviderRegistry.default()
        engine = MigrationEngine(registry=registry, logger=ConsoleLogger(quiet=True))
        source = _FakeBitbucketSource(legacy_no_manifest=True)
        target = _FakeGitLabTarget()

        with tempfile.TemporaryDirectory() as tmp:
            tags_file = Path(tmp) / "tags.txt"
            tags_file.write_text("v1.0.0\n", encoding="utf-8")
            opts = _options_for(
                tmp,
                source_provider="bitbucket",
                source_url="https://bitbucket.org/workspace/repo",
                target_provider="gitlab",
                target_url="https://gitlab.com/group/proj",
                tags_file=str(tags_file),
                skip_tag_migration=True,
            )

            engine._migrate_bitbucket_to_gitlab(
                opts,
                source_ref=_bitbucket_ref(),
                target_ref=_source_ref(),
                source=source,
                target=target,
            )

            self.assertEqual(target.updated, 1)
            self.assertTrue(any(str(link.get("name", "")).endswith("-tag-link") for link in target.last_links))


if __name__ == "__main__":
    unittest.main()
