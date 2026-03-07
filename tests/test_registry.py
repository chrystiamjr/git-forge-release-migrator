from __future__ import annotations

import unittest

from git_forge_release_migrator.providers.registry import ProviderRegistry


class RegistryTests(unittest.TestCase):
    def test_pair_status_matrix(self) -> None:
        registry = ProviderRegistry.default()

        self.assertEqual(registry.pair_status("gitlab", "github"), "enabled")
        self.assertEqual(registry.pair_status("github", "gitlab"), "enabled")
        self.assertEqual(registry.pair_status("github", "bitbucket"), "enabled")
        self.assertEqual(registry.pair_status("bitbucket", "gitlab"), "enabled")
        self.assertEqual(registry.pair_status("gitlab", "bitbucket"), "enabled")
        self.assertEqual(registry.pair_status("bitbucket", "github"), "enabled")
        self.assertEqual(registry.pair_status("gitlab", "gitlab"), "unsupported")
        self.assertEqual(registry.pair_status("bitbucket", "bitbucket"), "unsupported")


if __name__ == "__main__":
    unittest.main()
