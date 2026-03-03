from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from git_forge_release_migrator.cli import _allocate_run_workdir, main


class AllocateRunWorkdirTests(unittest.TestCase):
    def test_returns_path_under_base(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            result = _allocate_run_workdir(base)
            self.assertEqual(result.parent, base)

    def test_appends_index_on_collision(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            first = _allocate_run_workdir(base)
            first.mkdir(parents=True)
            second = _allocate_run_workdir(base)
            self.assertNotEqual(first, second)
            self.assertTrue(second.name.endswith("-2"))

    def test_increments_index_on_multiple_collisions(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            first = _allocate_run_workdir(base)
            first.mkdir(parents=True)
            second = _allocate_run_workdir(base)
            second.mkdir(parents=True)
            third = _allocate_run_workdir(base)
            self.assertTrue(third.name.endswith("-3"))

    def test_name_is_timestamp_based(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            result = _allocate_run_workdir(base)
            # Timestamp format: YYYYMMDD-HHMMSS (15 chars) or with suffix
            name = result.name.split("-")[0]
            self.assertEqual(len(name), 8)  # YYYYMMDD
            self.assertTrue(name.isdigit())


class MainHelpTests(unittest.TestCase):
    def test_help_exits_zero(self) -> None:
        with self.assertRaises(SystemExit) as ctx:
            main(["--help"])
        self.assertEqual(ctx.exception.code, 0)


class MainMissingFlagsTests(unittest.TestCase):
    def test_missing_all_required_flags_returns_nonzero(self) -> None:
        result = main(["--non-interactive"])
        self.assertNotEqual(result, 0)

    def test_missing_tokens_returns_nonzero(self) -> None:
        result = main(
            [
                "--non-interactive",
                "--source-provider",
                "gitlab",
                "--source-url",
                "https://gitlab.com/g/p",
                "--target-provider",
                "github",
                "--target-url",
                "https://github.com/o/r",
            ]
        )
        self.assertNotEqual(result, 0)

    def test_unsupported_provider_returns_nonzero(self) -> None:
        result = main(
            [
                "--non-interactive",
                "--source-provider",
                "unknown-forge",
                "--source-url",
                "https://example.com/g/p",
                "--source-token",
                "tok",
                "--target-provider",
                "github",
                "--target-url",
                "https://github.com/o/r",
                "--target-token",
                "tok",
            ]
        )
        self.assertNotEqual(result, 0)


class MainDemoModeTests(unittest.TestCase):
    _COMMON_ARGS = [
        "--non-interactive",
        "--no-banner",
        "--quiet",
        "--demo-mode",
        "--demo-sleep-seconds",
        "0",
        "--source-provider",
        "gitlab",
        "--source-url",
        "https://gitlab.com/test/proj",
        "--source-token",
        "glpat_fake",
        "--target-provider",
        "github",
        "--target-url",
        "https://github.com/owner/repo",
        "--target-token",
        "ghp_fake",
        "--no-save-session",
    ]

    def test_demo_mode_runs_without_network(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            result = main([*self._COMMON_ARGS, "--demo-releases", "2", "--workdir", tmp])
        self.assertEqual(result, 0)

    def test_demo_mode_writes_summary_json(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            main([*self._COMMON_ARGS, "--demo-releases", "1", "--workdir", tmp])
            summary_files = list(Path(tmp).rglob("summary.json"))
            self.assertEqual(len(summary_files), 1)

    def test_demo_mode_writes_jsonl_log(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            main([*self._COMMON_ARGS, "--demo-releases", "2", "--workdir", tmp])
            log_files = list(Path(tmp).rglob("migration-log.jsonl"))
            self.assertEqual(len(log_files), 1)

    def test_demo_mode_creates_failed_tags_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            main([*self._COMMON_ARGS, "--demo-releases", "1", "--workdir", tmp])
            failed_files = list(Path(tmp).rglob("failed-tags.txt"))
            self.assertEqual(len(failed_files), 1)

    def test_demo_mode_summary_has_correct_release_count(self) -> None:
        import json

        with tempfile.TemporaryDirectory() as tmp:
            main([*self._COMMON_ARGS, "--demo-releases", "3", "--workdir", tmp])
            summary_file = next(Path(tmp).rglob("summary.json"))
            summary = json.loads(summary_file.read_text(encoding="utf-8"))
            self.assertEqual(summary["counts"]["releases_created"], 3)


if __name__ == "__main__":
    unittest.main()
