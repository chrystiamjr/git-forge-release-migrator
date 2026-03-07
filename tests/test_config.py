from __future__ import annotations

import os
import unittest
from unittest import mock

from git_forge_release_migrator.config import RawCLIOptions, parse_raw_args, resolve_runtime_options
from git_forge_release_migrator.core.logging import ConsoleLogger

_TOKEN_ENV_KEYS = [
    "GFRM_SOURCE_TOKEN",
    "GFRM_TARGET_TOKEN",
    "GITHUB_TOKEN",
    "GH_TOKEN",
    "GH_PERSONAL_TOKEN",
    "GITLAB_TOKEN",
    "GL_TOKEN",
    "BITBUCKET_TOKEN",
    "BB_TOKEN",
    "SETTINGS_SOURCE_TOKEN",
    "SETTINGS_TARGET_TOKEN",
]


def _silent_input(_prompt: str) -> str:
    return ""


def _silent_getpass(_prompt: str) -> str:
    return ""


class ConfigTests(unittest.TestCase):
    def test_none_values_do_not_crash_on_strip(self) -> None:
        raw = RawCLIOptions(
            source_provider=None,  # type: ignore[arg-type]
            source_url="https://gitlab.com/acme/project",
            source_token="glpat_x",
            target_provider="github",
            target_url="https://github.com/acme/repo",
            target_token="ghp_x",
            non_interactive=True,
        )

        with self.assertRaises(ValueError) as ctx:
            resolve_runtime_options(raw, logger=ConsoleLogger(), input_fn=_silent_input, getpass_fn=_silent_getpass)

        self.assertIn("Missing required canonical inputs", str(ctx.exception))

    def test_interactive_prompts_for_skip_tags(self) -> None:
        answers = iter(["y"])

        def _input(_prompt: str) -> str:
            return next(answers)

        raw = RawCLIOptions(
            source_provider="gitlab",
            source_url="https://gitlab.com/acme/project",
            source_token="glpat_x",
            target_provider="github",
            target_url="https://github.com/acme/repo",
            target_token="ghp_x",
            non_interactive=False,
        )

        options = resolve_runtime_options(raw, logger=ConsoleLogger(), input_fn=_input, getpass_fn=_silent_getpass)
        self.assertTrue(options.skip_tag_migration)

    def test_resume_session_without_existing_file_continues(self) -> None:
        raw = RawCLIOptions(
            source_provider="gitlab",
            source_url="https://gitlab.com/acme/project",
            source_token="glpat_x",
            target_provider="github",
            target_url="https://github.com/acme/repo",
            target_token="ghp_x",
            non_interactive=True,
            resume_session=True,
            session_file="/tmp/does-not-exist-gfrm-session.json",
        )

        options = resolve_runtime_options(
            raw, logger=ConsoleLogger(), input_fn=_silent_input, getpass_fn=_silent_getpass
        )

        self.assertTrue(options.resume_session)
        self.assertTrue(options.load_session)
        self.assertTrue(options.save_session)
        self.assertEqual(options.session_file, "/tmp/does-not-exist-gfrm-session.json")

    def test_save_session_enabled_by_default(self) -> None:
        raw = RawCLIOptions(
            source_provider="gitlab",
            source_url="https://gitlab.com/acme/project",
            source_token="glpat_x",
            target_provider="github",
            target_url="https://github.com/acme/repo",
            target_token="ghp_x",
            non_interactive=True,
        )

        options = resolve_runtime_options(
            raw, logger=ConsoleLogger(), input_fn=_silent_input, getpass_fn=_silent_getpass
        )

        self.assertTrue(options.save_session)

    def test_can_disable_save_session(self) -> None:
        raw = RawCLIOptions(
            source_provider="gitlab",
            source_url="https://gitlab.com/acme/project",
            source_token="glpat_x",
            target_provider="github",
            target_url="https://github.com/acme/repo",
            target_token="ghp_x",
            non_interactive=True,
            save_session=False,
        )

        options = resolve_runtime_options(
            raw, logger=ConsoleLogger(), input_fn=_silent_input, getpass_fn=_silent_getpass
        )

        self.assertFalse(options.save_session)

    def test_env_session_mode_reads_token_from_env(self) -> None:
        os.environ["GFRM_SOURCE_TOKEN"] = "glpat_env"
        os.environ["GFRM_TARGET_TOKEN"] = "ghp_env"
        self.addCleanup(lambda: os.environ.pop("GFRM_SOURCE_TOKEN", None))
        self.addCleanup(lambda: os.environ.pop("GFRM_TARGET_TOKEN", None))

        raw = RawCLIOptions(
            source_provider="gitlab",
            source_url="https://gitlab.com/acme/project",
            source_token="",
            target_provider="github",
            target_url="https://github.com/acme/repo",
            target_token="",
            non_interactive=True,
            load_session=False,
            session_token_mode="env",
        )

        raw.source_token = os.environ.get(raw.session_source_token_env, "")
        raw.target_token = os.environ.get(raw.session_target_token_env, "")

        options = resolve_runtime_options(
            raw, logger=ConsoleLogger(), input_fn=_silent_input, getpass_fn=_silent_getpass
        )

        self.assertEqual(options.source_token, "glpat_env")
        self.assertEqual(options.target_token, "ghp_env")
        self.assertEqual(options.session_token_mode, "env")

    def test_output_flags_are_carried_to_runtime(self) -> None:
        raw = RawCLIOptions(
            source_provider="gitlab",
            source_url="https://gitlab.com/acme/project",
            source_token="glpat_x",
            target_provider="github",
            target_url="https://github.com/acme/repo",
            target_token="ghp_x",
            non_interactive=True,
            no_banner=True,
            quiet=True,
            json_output=True,
            progress_bar=True,
            tags_file="/tmp/tags.txt",
        )

        options = resolve_runtime_options(
            raw, logger=ConsoleLogger(), input_fn=_silent_input, getpass_fn=_silent_getpass
        )

        self.assertTrue(options.no_banner)
        self.assertTrue(options.quiet)
        self.assertTrue(options.json_output)
        self.assertTrue(options.progress_bar)
        self.assertEqual(options.tags_file, "/tmp/tags.txt")

    def test_demo_mode_flags_are_carried(self) -> None:
        raw = RawCLIOptions(
            source_provider="gitlab",
            source_url="https://gitlab.com/teste",
            source_token="foo",
            target_provider="github",
            target_url="https://github.com/teste",
            target_token="bar",
            non_interactive=True,
            demo_mode=True,
            demo_releases=5,
            demo_sleep_seconds=0.5,
        )

        options = resolve_runtime_options(
            raw, logger=ConsoleLogger(), input_fn=_silent_input, getpass_fn=_silent_getpass
        )

        self.assertTrue(options.demo_mode)
        self.assertEqual(options.demo_releases, 5)
        self.assertEqual(options.demo_sleep_seconds, 0.5)

    def test_demo_releases_validation(self) -> None:
        raw = RawCLIOptions(
            source_provider="gitlab",
            source_url="https://gitlab.com/acme/project",
            source_token="glpat_x",
            target_provider="github",
            target_url="https://github.com/acme/repo",
            target_token="ghp_x",
            non_interactive=True,
            demo_releases=0,
        )

        with self.assertRaises(ValueError) as ctx:
            resolve_runtime_options(raw, logger=ConsoleLogger(), input_fn=_silent_input, getpass_fn=_silent_getpass)

        self.assertIn("--demo-releases must be >= 1", str(ctx.exception))

    def test_download_workers_validation(self) -> None:
        raw = RawCLIOptions(
            source_provider="gitlab",
            source_url="https://gitlab.com/acme/project",
            source_token="glpat_x",
            target_provider="github",
            target_url="https://github.com/acme/repo",
            target_token="ghp_x",
            non_interactive=True,
            download_workers=0,
        )

        with self.assertRaises(ValueError) as ctx:
            resolve_runtime_options(raw, logger=ConsoleLogger(), input_fn=_silent_input, getpass_fn=_silent_getpass)

        self.assertIn("--download-workers must be >= 1", str(ctx.exception))

    def test_release_workers_validation(self) -> None:
        raw = RawCLIOptions(
            source_provider="gitlab",
            source_url="https://gitlab.com/acme/project",
            source_token="glpat_x",
            target_provider="github",
            target_url="https://github.com/acme/repo",
            target_token="ghp_x",
            non_interactive=True,
            release_workers=0,
        )

        with self.assertRaises(ValueError) as ctx:
            resolve_runtime_options(raw, logger=ConsoleLogger(), input_fn=_silent_input, getpass_fn=_silent_getpass)

        self.assertIn("--release-workers must be >= 1", str(ctx.exception))


class TokenResolutionPrecedenceTests(unittest.TestCase):
    def setUp(self) -> None:
        self._env_backup = {key: os.environ.get(key) for key in _TOKEN_ENV_KEYS}
        for key in _TOKEN_ENV_KEYS:
            os.environ.pop(key, None)

    def tearDown(self) -> None:
        for key in _TOKEN_ENV_KEYS:
            original = self._env_backup.get(key)
            if original is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = original

    def _base_raw(self, **overrides: object) -> RawCLIOptions:
        raw = RawCLIOptions(
            source_provider="github",
            source_url="https://github.com/acme/source",
            source_token="",
            target_provider="gitlab",
            target_url="https://gitlab.com/acme/target",
            target_token="",
            non_interactive=True,
        )
        for key, value in overrides.items():
            setattr(raw, key, value)
        return raw

    def test_args_tokens_have_highest_precedence(self) -> None:
        os.environ["GH_PERSONAL_TOKEN"] = "env-source"
        os.environ["GL_TOKEN"] = "env-target"
        settings_payload = {
            "version": 1,
            "defaults": {"profile": "default"},
            "profiles": {
                "default": {
                    "providers": {
                        "github": {"token_plain": "settings-source"},
                        "gitlab": {"token_plain": "settings-target"},
                    }
                }
            },
        }

        raw = self._base_raw(
            source_token="arg-source",
            target_token="arg-target",
            load_session=True,
            session_file="/tmp/session.json",
        )

        with (
            mock.patch("git_forge_release_migrator.config.load_session") as load_session_mock,
            mock.patch("git_forge_release_migrator.config.load_effective_settings", return_value=settings_payload),
        ):
            load_session_mock.return_value = {"source_token": "session-source", "target_token": "session-target"}
            options = resolve_runtime_options(
                raw,
                logger=ConsoleLogger(),
                input_fn=_silent_input,
                getpass_fn=_silent_getpass,
            )

        self.assertEqual(options.source_token, "arg-source")
        self.assertEqual(options.target_token, "arg-target")

    def test_session_tokens_override_settings_and_env(self) -> None:
        os.environ["GH_PERSONAL_TOKEN"] = "env-source"
        os.environ["GL_TOKEN"] = "env-target"
        settings_payload = {
            "version": 1,
            "defaults": {"profile": "default"},
            "profiles": {
                "default": {
                    "providers": {
                        "github": {"token_plain": "settings-source"},
                        "gitlab": {"token_plain": "settings-target"},
                    }
                }
            },
        }
        raw = self._base_raw(load_session=True, session_file="/tmp/session.json")

        with (
            mock.patch(
                "git_forge_release_migrator.config.load_session",
                return_value={"source_token": "session-source", "target_token": "session-target"},
            ),
            mock.patch("git_forge_release_migrator.config.load_effective_settings", return_value=settings_payload),
        ):
            options = resolve_runtime_options(
                raw,
                logger=ConsoleLogger(),
                input_fn=_silent_input,
                getpass_fn=_silent_getpass,
            )

        self.assertEqual(options.source_token, "session-source")
        self.assertEqual(options.target_token, "session-target")

    def test_settings_override_environment_aliases(self) -> None:
        os.environ["SETTINGS_SOURCE_TOKEN"] = "settings-env-source"
        os.environ["GH_PERSONAL_TOKEN"] = "alias-source"
        os.environ["GL_TOKEN"] = "alias-target"

        settings_payload = {
            "version": 1,
            "defaults": {"profile": "prod"},
            "profiles": {
                "prod": {
                    "providers": {
                        "github": {"token_env": "SETTINGS_SOURCE_TOKEN"},
                        "gitlab": {"token_plain": "settings-plain-target"},
                    }
                }
            },
        }

        raw = self._base_raw()
        with mock.patch("git_forge_release_migrator.config.load_effective_settings", return_value=settings_payload):
            options = resolve_runtime_options(
                raw,
                logger=ConsoleLogger(),
                input_fn=_silent_input,
                getpass_fn=_silent_getpass,
            )

        self.assertEqual(options.source_token, "settings-env-source")
        self.assertEqual(options.target_token, "settings-plain-target")

    def test_environment_aliases_are_used_when_settings_are_empty(self) -> None:
        os.environ["GH_PERSONAL_TOKEN"] = "alias-source"
        os.environ["GL_TOKEN"] = "alias-target"

        raw = self._base_raw()
        with mock.patch("git_forge_release_migrator.config.load_effective_settings", return_value={}):
            options = resolve_runtime_options(
                raw,
                logger=ConsoleLogger(),
                input_fn=_silent_input,
                getpass_fn=_silent_getpass,
            )

        self.assertEqual(options.source_token, "alias-source")
        self.assertEqual(options.target_token, "alias-target")

    def test_prompt_is_last_fallback_in_interactive_mode(self) -> None:
        prompts: list[str] = []
        getpass_values = iter(["prompt-source", "prompt-target"])

        def _input(prompt: str) -> str:
            prompts.append(prompt)
            return "n"

        def _getpass(_prompt: str) -> str:
            return next(getpass_values)

        raw = self._base_raw(non_interactive=False)
        with mock.patch("git_forge_release_migrator.config.load_effective_settings", return_value={}):
            options = resolve_runtime_options(raw, logger=ConsoleLogger(), input_fn=_input, getpass_fn=_getpass)

        self.assertEqual(options.source_token, "prompt-source")
        self.assertEqual(options.target_token, "prompt-target")
        self.assertTrue(any("Skip tag migration?" in p for p in prompts))


class ParseRawArgsTests(unittest.TestCase):
    def test_skip_tags_sets_provided_flag(self) -> None:
        raw = parse_raw_args(["--skip-tags"])
        self.assertTrue(raw.skip_tags)
        self.assertTrue(raw.skip_tags_provided)

    def test_skip_tags_not_set_leaves_provided_false(self) -> None:
        raw = parse_raw_args([])
        self.assertFalse(raw.skip_tags)
        self.assertFalse(raw.skip_tags_provided)

    def test_download_workers_sets_provided_flag(self) -> None:
        raw = parse_raw_args(["--download-workers", "8"])
        self.assertEqual(raw.download_workers, 8)
        self.assertTrue(raw.download_workers_provided)

    def test_download_workers_without_flag_leaves_provided_false(self) -> None:
        raw = parse_raw_args([])
        self.assertFalse(raw.download_workers_provided)

    def test_release_workers_sets_provided_flag(self) -> None:
        raw = parse_raw_args(["--release-workers", "4"])
        self.assertEqual(raw.release_workers, 4)
        self.assertTrue(raw.release_workers_provided)

    def test_demo_mode_flags(self) -> None:
        raw = parse_raw_args(["--demo-mode", "--demo-releases", "10", "--demo-sleep-seconds", "0.5"])
        self.assertTrue(raw.demo_mode)
        self.assertEqual(raw.demo_releases, 10)
        self.assertAlmostEqual(raw.demo_sleep_seconds, 0.5)

    def test_dry_run_flag(self) -> None:
        raw = parse_raw_args(["--dry-run"])
        self.assertTrue(raw.dry_run)

    def test_no_save_session_flag(self) -> None:
        raw = parse_raw_args(["--no-save-session"])
        self.assertFalse(raw.save_session)

    def test_default_save_session_is_true(self) -> None:
        raw = parse_raw_args([])
        self.assertTrue(raw.save_session)

    def test_session_token_mode_plain(self) -> None:
        raw = parse_raw_args(["--session-token-mode", "plain"])
        self.assertEqual(raw.session_token_mode, "plain")

    def test_settings_profile_flag(self) -> None:
        raw = parse_raw_args(["--settings-profile", "work"])
        self.assertEqual(raw.settings_profile, "work")

    def test_help_exits_zero(self) -> None:
        with self.assertRaises(SystemExit) as ctx:
            parse_raw_args(["--help"])
        self.assertEqual(ctx.exception.code, 0)

    def test_source_and_target_provider_captured(self) -> None:
        raw = parse_raw_args(
            [
                "--source-provider",
                "gitlab",
                "--source-url",
                "https://gitlab.com/g/p",
                "--source-token",
                "tok",
                "--target-provider",
                "github",
                "--target-url",
                "https://github.com/o/r",
                "--target-token",
                "ghp",
            ]
        )
        self.assertEqual(raw.source_provider, "gitlab")
        self.assertEqual(raw.target_provider, "github")
        self.assertEqual(raw.source_url, "https://gitlab.com/g/p")

    def test_tags_file_captured(self) -> None:
        raw = parse_raw_args(["--tags-file", "/tmp/tags.txt"])
        self.assertEqual(raw.tags_file, "/tmp/tags.txt")

    def test_from_to_tag_captured(self) -> None:
        raw = parse_raw_args(["--from-tag", "v1.0.0", "--to-tag", "v2.0.0"])
        self.assertEqual(raw.from_tag, "v1.0.0")
        self.assertEqual(raw.to_tag, "v2.0.0")

    def test_settings_show_command_is_parsed(self) -> None:
        raw = parse_raw_args(["settings", "show", "--profile", "team"])
        self.assertEqual(raw.command, "settings")
        self.assertEqual(raw.settings_action, "show")
        self.assertEqual(raw.settings_profile, "team")

    def test_settings_set_token_env_command_is_parsed(self) -> None:
        raw = parse_raw_args(
            [
                "settings",
                "set-token-env",
                "--provider",
                "gh",
                "--env-name",
                "GH_PERSONAL_TOKEN",
                "--local",
            ]
        )
        self.assertEqual(raw.command, "settings")
        self.assertEqual(raw.settings_action, "set-token-env")
        self.assertEqual(raw.settings_provider, "github")
        self.assertEqual(raw.settings_env_name, "GH_PERSONAL_TOKEN")
        self.assertTrue(raw.settings_scope_local)


if __name__ == "__main__":
    unittest.main()
