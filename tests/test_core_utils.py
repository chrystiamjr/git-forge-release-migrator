from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from git_forge_release_migrator.core.checkpoint import append_checkpoint, load_checkpoint_state
from git_forge_release_migrator.core.files import sanitize_filename, unique_asset_filename
from git_forge_release_migrator.core.jsonl import append_log
from git_forge_release_migrator.core.versioning import version_le


class VersioningTests(unittest.TestCase):
    def test_version_le_ascending(self) -> None:
        self.assertTrue(version_le("v1.0.0", "v2.0.0"))
        self.assertTrue(version_le("v1.0.0", "v1.1.0"))
        self.assertTrue(version_le("v1.0.0", "v1.0.1"))

    def test_version_le_equal(self) -> None:
        self.assertTrue(version_le("v1.0.0", "v1.0.0"))
        self.assertTrue(version_le("1.2.3", "v1.2.3"))

    def test_version_le_descending(self) -> None:
        self.assertFalse(version_le("v2.0.0", "v1.0.0"))
        self.assertFalse(version_le("v1.1.0", "v1.0.0"))
        self.assertFalse(version_le("v1.0.1", "v1.0.0"))

    def test_version_le_no_v_prefix(self) -> None:
        self.assertTrue(version_le("1.0.0", "2.0.0"))
        self.assertTrue(version_le("1.0.0", "1.0.0"))

    def test_version_le_pre_release_tag_raises(self) -> None:
        with self.assertRaises(ValueError):
            version_le("v1.0.0-beta", "v1.0.0")

    def test_version_le_invalid_tag_too_few_parts_raises(self) -> None:
        with self.assertRaises(ValueError):
            version_le("v1.0", "v1.0.0")

    def test_version_le_invalid_tag_too_many_parts_raises(self) -> None:
        with self.assertRaises(ValueError):
            version_le("v1.0.0.0", "v1.0.0")


class SanitizeFilenameTests(unittest.TestCase):
    def test_strips_path_components(self) -> None:
        self.assertEqual(sanitize_filename("path/to/file.zip"), "file.zip")

    def test_strips_query_params(self) -> None:
        self.assertEqual(sanitize_filename("file.zip?token=abc"), "file.zip")

    def test_replaces_spaces(self) -> None:
        self.assertEqual(sanitize_filename("my file.zip"), "my_file.zip")

    def test_replaces_colons(self) -> None:
        self.assertEqual(sanitize_filename("file:name.bin"), "file_name.bin")

    def test_removes_special_chars(self) -> None:
        self.assertEqual(sanitize_filename("file@#!.zip"), "file.zip")

    def test_empty_name_returns_asset(self) -> None:
        self.assertEqual(sanitize_filename("???"), "asset")

    def test_dots_preserved(self) -> None:
        result = sanitize_filename("release.v1.2.3.tar.gz")
        self.assertEqual(result, "release.v1.2.3.tar.gz")

    def test_tabs_replaced(self) -> None:
        result = sanitize_filename("my\tfile.bin")
        self.assertEqual(result, "my_file.bin")


class UniqueAssetFilenameTests(unittest.TestCase):
    def test_returns_clean_name_when_no_collision(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = unique_asset_filename(tmp, "app.apk")
            self.assertEqual(result, "app.apk")

    def test_appends_index_on_collision(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            Path(tmp, "app.apk").write_text("", encoding="utf-8")
            result = unique_asset_filename(tmp, "app.apk")
            self.assertEqual(result, "app-2.apk")

    def test_increments_index_on_multiple_collisions(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            Path(tmp, "app.apk").write_text("", encoding="utf-8")
            Path(tmp, "app-2.apk").write_text("", encoding="utf-8")
            result = unique_asset_filename(tmp, "app.apk")
            self.assertEqual(result, "app-3.apk")

    def test_sanitizes_special_characters(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = unique_asset_filename(tmp, "my file@special.zip")
            self.assertEqual(result, "my_filespecial.zip")

    def test_no_collision_for_different_names(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            Path(tmp, "app.apk").write_text("", encoding="utf-8")
            result = unique_asset_filename(tmp, "other.apk")
            self.assertEqual(result, "other.apk")


class CheckpointRoundTripTests(unittest.TestCase):
    def test_append_and_load(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = str(Path(tmp) / "checkpoints" / "state.jsonl")
            sig = "gitlab|group/proj|owner/repo|<start>|<end>"

            append_checkpoint(path, signature=sig, key="tag:v1.0.0", tag="v1.0.0", status="tag_created", message="ok")
            append_checkpoint(path, signature=sig, key="release:v1.0.0", tag="v1.0.0", status="created", message="ok")

            state = load_checkpoint_state(path, sig)
            self.assertEqual(state["tag:v1.0.0"], "tag_created")
            self.assertEqual(state["release:v1.0.0"], "created")

    def test_load_ignores_different_signature(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = str(Path(tmp) / "state.jsonl")
            sig1 = "gitlab|proj-a|repo-a|<start>|<end>"
            sig2 = "gitlab|proj-b|repo-b|<start>|<end>"

            append_checkpoint(path, signature=sig1, key="tag:v1.0.0", tag="v1.0.0", status="tag_created", message="ok")
            state = load_checkpoint_state(path, sig2)
            self.assertEqual(state, {})

    def test_load_from_nonexistent_file_returns_empty(self) -> None:
        state = load_checkpoint_state("/tmp/does-not-exist-gfrm-state.jsonl", "some-sig")
        self.assertEqual(state, {})

    def test_later_status_overwrites_earlier(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = str(Path(tmp) / "state.jsonl")
            sig = "sig"
            append_checkpoint(path, signature=sig, key="release:v1.0.0", tag="v1.0.0", status="failed", message="1st")
            append_checkpoint(path, signature=sig, key="release:v1.0.0", tag="v1.0.0", status="created", message="2nd")
            state = load_checkpoint_state(path, sig)
            self.assertEqual(state["release:v1.0.0"], "created")

    def test_creates_parent_dirs_if_missing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = str(Path(tmp) / "deep" / "nested" / "state.jsonl")
            sig = "sig"
            append_checkpoint(path, signature=sig, key="k", tag="v1.0.0", status="created", message="ok")
            self.assertTrue(Path(path).exists())


class JsonlLogTests(unittest.TestCase):
    def test_append_log_writes_valid_json_lines(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = str(Path(tmp) / "log.jsonl")
            append_log(
                path, status="created", tag="v1.0.0", message="done", asset_count=3, duration_ms=250, dry_run=False
            )
            append_log(path, status="skipped", tag="v1.1.0", message="skip", asset_count=0, duration_ms=0, dry_run=True)

            lines = Path(path).read_text(encoding="utf-8").splitlines()
            self.assertEqual(len(lines), 2)

            record1 = json.loads(lines[0])
            self.assertEqual(record1["status"], "created")
            self.assertEqual(record1["tag"], "v1.0.0")
            self.assertEqual(record1["asset_count"], 3)
            self.assertFalse(record1["dry_run"])
            self.assertIn("timestamp", record1)

            record2 = json.loads(lines[1])
            self.assertEqual(record2["status"], "skipped")
            self.assertTrue(record2["dry_run"])

    def test_creates_parent_dirs_if_missing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = str(Path(tmp) / "run-1" / "migration-log.jsonl")
            append_log(path, status="created", tag="v1.0.0", message="ok", asset_count=1, duration_ms=10, dry_run=False)
            self.assertTrue(Path(path).exists())

    def test_appends_to_existing_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = str(Path(tmp) / "log.jsonl")
            for i in range(5):
                append_log(
                    path, status="created", tag=f"v1.{i}.0", message="ok", asset_count=1, duration_ms=0, dry_run=False
                )
            lines = Path(path).read_text(encoding="utf-8").splitlines()
            self.assertEqual(len(lines), 5)


if __name__ == "__main__":
    unittest.main()
