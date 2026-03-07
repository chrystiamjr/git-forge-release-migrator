from __future__ import annotations

import json
import os
import stat
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from git_forge_release_migrator.core import settings


class SettingsLoadTests(unittest.TestCase):
    def test_load_effective_settings_merges_global_and_local(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_path = Path(tmp)
            global_path = tmp_path / "global.yaml"
            local_path = tmp_path / ".gfrm" / "settings.yaml"
            local_path.parent.mkdir(parents=True, exist_ok=True)

            global_payload = {
                "version": 1,
                "defaults": {"profile": "team"},
                "profiles": {
                    "team": {
                        "providers": {
                            "github": {"token_env": "GH_TOKEN"},
                            "gitlab": {"token_env": "GL_TOKEN"},
                        }
                    }
                },
            }
            local_payload = {
                "profiles": {
                    "team": {
                        "providers": {
                            "github": {"token_env": "GH_PERSONAL_TOKEN"},
                            "bitbucket": {"token_env": "BB_TOKEN"},
                        }
                    }
                }
            }
            global_path.write_text(json.dumps(global_payload), encoding="utf-8")
            local_path.write_text(json.dumps(local_payload), encoding="utf-8")

            with (
                mock.patch(
                    "git_forge_release_migrator.core.settings.default_global_settings_path", return_value=global_path
                ),
                mock.patch(
                    "git_forge_release_migrator.core.settings.default_local_settings_path", return_value=local_path
                ),
            ):
                merged = settings.load_effective_settings(cwd=tmp_path)

        self.assertEqual(merged["version"], 1)
        self.assertEqual(merged["defaults"]["profile"], "team")
        self.assertEqual(
            merged["profiles"]["team"]["providers"]["github"]["token_env"],
            "GH_PERSONAL_TOKEN",
        )
        self.assertEqual(merged["profiles"]["team"]["providers"]["gitlab"]["token_env"], "GL_TOKEN")
        self.assertEqual(merged["profiles"]["team"]["providers"]["bitbucket"]["token_env"], "BB_TOKEN")

    def test_resolve_profile_name_fallback_chain(self) -> None:
        payload = {"defaults": {"profile": "workspace"}}
        self.assertEqual(settings.resolve_profile_name(payload, "ci"), "ci")
        self.assertEqual(settings.resolve_profile_name(payload, ""), "workspace")
        self.assertEqual(settings.resolve_profile_name({}, ""), "default")


class SettingsTokenTests(unittest.TestCase):
    _ENV_KEYS = [
        "SETTINGS_TOKEN",
        "GFRM_SOURCE_TOKEN",
        "GFRM_TARGET_TOKEN",
        "GITHUB_TOKEN",
        "GH_TOKEN",
        "GH_PERSONAL_TOKEN",
        "GITLAB_TOKEN",
        "GL_TOKEN",
        "BITBUCKET_TOKEN",
        "BB_TOKEN",
    ]

    def setUp(self) -> None:
        self._env_backup = {k: os.environ.get(k) for k in self._ENV_KEYS}
        for key in self._ENV_KEYS:
            os.environ.pop(key, None)

    def tearDown(self) -> None:
        for key in self._ENV_KEYS:
            original = self._env_backup.get(key)
            if original is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = original

    def test_token_from_settings_prefers_token_env_then_plain(self) -> None:
        payload = {
            "profiles": {
                "default": {
                    "providers": {
                        "github": {
                            "token_env": "SETTINGS_TOKEN",
                            "token_plain": "plain-fallback",
                        }
                    }
                }
            }
        }

        self.assertEqual(settings.token_from_settings(payload, "default", "github"), "plain-fallback")
        os.environ["SETTINGS_TOKEN"] = "env-token"
        self.assertEqual(settings.token_from_settings(payload, "default", "github"), "env-token")

    def test_token_from_env_aliases_reads_provider_aliases(self) -> None:
        os.environ["GH_PERSONAL_TOKEN"] = "github-token"
        os.environ["GL_TOKEN"] = "gitlab-token"

        self.assertEqual(settings.token_from_env_aliases("github"), "github-token")
        self.assertEqual(settings.token_from_env_aliases("gitlab"), "gitlab-token")

    def test_env_aliases_include_side_env_and_deduplicate(self) -> None:
        aliases = settings.env_aliases("github", side_env_name="GFRM_SOURCE_TOKEN")
        self.assertEqual(aliases[0], "GFRM_SOURCE_TOKEN")
        self.assertEqual(aliases.count("GFRM_SOURCE_TOKEN"), 1)
        self.assertIn("GH_PERSONAL_TOKEN", aliases)


class SettingsMutationTests(unittest.TestCase):
    def test_set_and_unset_token_helpers(self) -> None:
        payload: dict[str, object] = {}
        updated = settings.set_provider_token_env(payload, profile="default", provider="github", env_name="GH_TOKEN")
        self.assertEqual(updated["version"], 1)
        self.assertEqual(updated["profiles"]["default"]["providers"]["github"]["token_env"], "GH_TOKEN")

        updated = settings.set_provider_token_plain(updated, profile="default", provider="github", token="plain")
        self.assertNotIn("token_env", updated["profiles"]["default"]["providers"]["github"])
        self.assertEqual(updated["profiles"]["default"]["providers"]["github"]["token_plain"], "plain")

        updated = settings.unset_provider_token(updated, profile="default", provider="github")
        self.assertEqual(updated["profiles"], {})

    def test_write_settings_file_uses_restricted_permissions(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / ".gfrm" / "settings.yaml"
            settings.write_settings_file(path, {"version": 1, "defaults": {"profile": "default"}})
            self.assertTrue(path.exists())

            if os.name != "nt":
                file_mode = stat.S_IMODE(path.stat().st_mode)
                dir_mode = stat.S_IMODE(path.parent.stat().st_mode)
                self.assertEqual(file_mode, 0o600)
                self.assertEqual(dir_mode, 0o700)


class SettingsShellScanTests(unittest.TestCase):
    def test_scan_shell_export_names_reads_exports_and_assignments(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            shell_file = Path(tmp) / ".zshrc"
            shell_file.write_text(
                "\n".join(
                    [
                        "export GH_PERSONAL_TOKEN=abc",
                        "BB_TOKEN=xyz",
                        " # comment",
                        "export INVALID-NAME=foo",
                    ]
                )
                + "\n",
                encoding="utf-8",
            )

            names = settings.scan_shell_export_names([shell_file])
            self.assertIn("GH_PERSONAL_TOKEN", names)
            self.assertIn("BB_TOKEN", names)
            self.assertNotIn("INVALID-NAME", names)


if __name__ == "__main__":
    unittest.main()
