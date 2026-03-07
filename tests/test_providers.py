from __future__ import annotations

import unittest
from unittest.mock import patch

from git_forge_release_migrator.providers.base import ProviderRef
from git_forge_release_migrator.providers.bitbucket import BitbucketAdapter
from git_forge_release_migrator.providers.github import GitHubAdapter
from git_forge_release_migrator.providers.gitlab import GitLabAdapter


def _make_github_ref(resource: str = "owner/repo") -> ProviderRef:
    return ProviderRef(
        provider="github",
        raw_url="",
        base_url="https://github.com",
        host="github.com",
        resource=resource,
    )


def _make_gitlab_ref(resource: str = "group/proj") -> ProviderRef:
    return ProviderRef(
        provider="gitlab",
        raw_url="",
        base_url="https://gitlab.com",
        host="gitlab.com",
        resource=resource,
        metadata={"project_path": resource, "project_encoded": resource.replace("/", "%2F")},
    )


def _make_bitbucket_ref(resource: str = "workspace/repo") -> ProviderRef:
    workspace, repo = resource.split("/", 1)
    return ProviderRef(
        provider="bitbucket",
        raw_url="",
        base_url="https://bitbucket.org",
        host="bitbucket.org",
        resource=resource,
        metadata={
            "workspace": workspace,
            "repo": repo,
            "workspace_encoded": workspace,
            "repo_encoded": repo,
            "repo_ref": resource,
        },
    )


class GitHubParseUrlTests(unittest.TestCase):
    def setUp(self) -> None:
        self.adapter = GitHubAdapter()

    def test_https_url(self) -> None:
        ref = self.adapter.parse_url("https://github.com/owner/repo")
        self.assertEqual(ref.provider, "github")
        self.assertEqual(ref.resource, "owner/repo")
        self.assertEqual(ref.host, "github.com")
        self.assertEqual(ref.base_url, "https://github.com")

    def test_https_url_with_git_suffix(self) -> None:
        ref = self.adapter.parse_url("https://github.com/owner/repo.git")
        self.assertEqual(ref.resource, "owner/repo")

    def test_ssh_url(self) -> None:
        ref = self.adapter.parse_url("git@github.com:owner/repo.git")
        self.assertEqual(ref.host, "github.com")
        self.assertEqual(ref.resource, "owner/repo")

    def test_enterprise_host(self) -> None:
        ref = self.adapter.parse_url("https://github.example.com/owner/repo")
        self.assertEqual(ref.host, "github.example.com")
        self.assertEqual(ref.resource, "owner/repo")

    def test_url_with_subpath_stripped(self) -> None:
        ref = self.adapter.parse_url("https://github.com/owner/repo/-/tree/main")
        self.assertEqual(ref.resource, "owner/repo")

    def test_invalid_url_raises(self) -> None:
        with self.assertRaises(ValueError):
            self.adapter.parse_url("not-a-url")

    def test_empty_url_raises(self) -> None:
        with self.assertRaises(ValueError):
            self.adapter.parse_url("")

    def test_single_segment_path_raises(self) -> None:
        with self.assertRaises(ValueError):
            self.adapter.parse_url("https://github.com/onlyowner")

    def test_validate_url_returns_true_for_valid(self) -> None:
        self.assertTrue(self.adapter.validate_url("https://github.com/owner/repo"))

    def test_validate_url_returns_false_for_invalid(self) -> None:
        self.assertFalse(self.adapter.validate_url("not-a-url"))


class GitLabParseUrlTests(unittest.TestCase):
    def setUp(self) -> None:
        self.adapter = GitLabAdapter()

    def test_https_url(self) -> None:
        ref = self.adapter.parse_url("https://gitlab.com/group/project")
        self.assertEqual(ref.provider, "gitlab")
        self.assertEqual(ref.resource, "group/project")
        self.assertEqual(ref.host, "gitlab.com")

    def test_nested_group_url(self) -> None:
        ref = self.adapter.parse_url("https://gitlab.com/group/subgroup/project")
        self.assertEqual(ref.resource, "group/subgroup/project")

    def test_url_with_subpath_stripped(self) -> None:
        ref = self.adapter.parse_url("https://gitlab.com/group/proj/-/releases")
        self.assertEqual(ref.resource, "group/proj")

    def test_ssh_url(self) -> None:
        ref = self.adapter.parse_url("git@gitlab.com:group/project.git")
        self.assertEqual(ref.host, "gitlab.com")
        self.assertEqual(ref.resource, "group/project")

    def test_git_suffix_stripped(self) -> None:
        ref = self.adapter.parse_url("https://gitlab.com/group/project.git")
        self.assertEqual(ref.resource, "group/project")

    def test_empty_url_raises(self) -> None:
        with self.assertRaises(ValueError):
            self.adapter.parse_url("")

    def test_invalid_url_raises(self) -> None:
        with self.assertRaises(ValueError):
            self.adapter.parse_url("not-a-url")

    def test_metadata_includes_encoded_path(self) -> None:
        ref = self.adapter.parse_url("https://gitlab.com/group/project")
        self.assertIn("project_encoded", ref.metadata)


class BitbucketParseUrlTests(unittest.TestCase):
    def setUp(self) -> None:
        self.adapter = BitbucketAdapter()

    def test_https_url(self) -> None:
        ref = self.adapter.parse_url("https://bitbucket.org/workspace/repo")
        self.assertEqual(ref.provider, "bitbucket")
        self.assertEqual(ref.resource, "workspace/repo")
        self.assertEqual(ref.host, "bitbucket.org")

    def test_ssh_url(self) -> None:
        ref = self.adapter.parse_url("git@bitbucket.org:workspace/repo.git")
        self.assertEqual(ref.resource, "workspace/repo")

    def test_invalid_host_raises(self) -> None:
        with self.assertRaises(ValueError):
            self.adapter.parse_url("https://bb.example.com/workspace/repo")

    def test_invalid_path_raises(self) -> None:
        with self.assertRaises(ValueError):
            self.adapter.parse_url("https://bitbucket.org/workspace")


class BitbucketApiTests(unittest.TestCase):
    def setUp(self) -> None:
        self.adapter = BitbucketAdapter()
        self.ref = _make_bitbucket_ref()

    def test_list_tags_paginates(self) -> None:
        page1 = {
            "values": [{"name": "v1.0.0"}, {"name": "v1.1.0"}],
            "next": "https://api.bitbucket.org/2.0/repositories/workspace/repo/refs/tags?page=2",
        }
        page2 = {"values": [{"name": "v2.0.0"}]}
        calls = {"count": 0}

        def _fake_request_json(url: str, **kwargs) -> dict:
            del kwargs
            calls["count"] += 1
            return page1 if calls["count"] == 1 else page2

        with patch("git_forge_release_migrator.providers.bitbucket.request_json", side_effect=_fake_request_json):
            tags = self.adapter.list_tags(self.ref, "token")

        self.assertEqual(tags, ["v1.0.0", "v1.1.0", "v2.0.0"])
        self.assertEqual(calls["count"], 2)

    def test_create_tag_sends_message_when_present(self) -> None:
        captured: list[dict] = []

        def _fake_request_json(url: str, **kwargs) -> dict:
            captured.append({"url": url, **kwargs})
            return {}

        with patch("git_forge_release_migrator.providers.bitbucket.request_json", side_effect=_fake_request_json):
            self.adapter.create_tag(self.ref, "token", "v1.0.0", "abc123", "release notes")

        self.assertEqual(len(captured), 1)
        payload = captured[0]["json_data"]
        self.assertEqual(payload["name"], "v1.0.0")
        self.assertEqual(payload["target"]["hash"], "abc123")
        self.assertEqual(payload["message"], "release notes")

    def test_build_release_manifest_contains_expected_fields(self) -> None:
        manifest = self.adapter.build_release_manifest(
            tag="v1.0.0",
            release_name="Release 1",
            notes="hello",
            uploaded_assets=[{"name": "app.zip", "url": "https://example/app.zip", "type": "package"}],
            missing_assets=[],
        )
        self.assertEqual(manifest["version"], 1)
        self.assertEqual(manifest["tag_name"], "v1.0.0")
        self.assertEqual(manifest["release_name"], "Release 1")
        self.assertTrue(manifest["notes_hash"])
        self.assertEqual(manifest["uploaded_assets"][0]["name"], "app.zip")
        self.assertEqual(manifest["missing_assets"], [])
        self.assertTrue(manifest["updated_at"])

    def test_manifest_is_complete(self) -> None:
        self.assertTrue(self.adapter.manifest_is_complete({"uploaded_assets": [], "missing_assets": []}))
        self.assertFalse(self.adapter.manifest_is_complete({"uploaded_assets": []}))
        self.assertFalse(self.adapter.manifest_is_complete(None))

    def test_list_releases_without_manifest_returns_legacy_release(self) -> None:
        with (
            patch.object(
                self.adapter,
                "list_tags_payload",
                return_value=[{"name": "v1.0.0", "message": "notes", "target": {"hash": "abc123"}}],
            ),
            patch.object(self.adapter, "list_downloads", return_value=[]),
        ):
            releases = self.adapter.list_releases(self.ref, "token")

        self.assertEqual(len(releases), 1)
        release = releases[0]
        canonical = self.adapter.to_canonical_release(release)
        self.assertEqual(canonical["tag_name"], "v1.0.0")
        self.assertEqual(canonical["description_markdown"], "notes")
        self.assertEqual(canonical["assets"]["links"], [])
        metadata = canonical["provider_metadata"]
        self.assertTrue(metadata["legacy_no_manifest"])

    def test_list_releases_with_manifest_maps_assets(self) -> None:
        manifest = {
            "version": 1,
            "tag_name": "v1.0.0",
            "release_name": "Release 1",
            "uploaded_assets": [{"name": "app.zip", "url": "https://download/app.zip", "type": "package"}],
            "missing_assets": [],
        }
        download_item = {
            "name": ".gfrm-release-v1.0.0.json",
            "links": {"download": {"href": "https://download/manifest.json"}},
        }

        def _fake_request_json(url: str, **kwargs) -> dict:
            del kwargs
            if url == "https://download/manifest.json":
                return manifest
            return {}

        with (
            patch.object(
                self.adapter,
                "list_tags_payload",
                return_value=[{"name": "v1.0.0", "message": "notes", "target": {"hash": "abc123"}}],
            ),
            patch.object(self.adapter, "list_downloads", return_value=[download_item]),
            patch("git_forge_release_migrator.providers.bitbucket.request_json", side_effect=_fake_request_json),
        ):
            releases = self.adapter.list_releases(self.ref, "token")

        self.assertEqual(len(releases), 1)
        canonical = self.adapter.to_canonical_release(releases[0])
        self.assertEqual(canonical["name"], "Release 1")
        self.assertEqual(len(canonical["assets"]["links"]), 1)
        self.assertEqual(canonical["assets"]["links"][0]["url"], "https://download/app.zip")
        self.assertFalse(canonical["provider_metadata"]["legacy_no_manifest"])


class GitLabToCanonicalReleaseTests(unittest.TestCase):
    def setUp(self) -> None:
        self.adapter = GitLabAdapter()

    def test_maps_tag_name_and_description(self) -> None:
        payload = {
            "tag_name": "v1.2.3",
            "name": "Release 1.2.3",
            "description": "## Changelog",
            "assets": {},
        }
        canonical = self.adapter.to_canonical_release(payload)
        self.assertEqual(canonical["tag_name"], "v1.2.3")
        self.assertEqual(canonical["name"], "Release 1.2.3")
        self.assertEqual(canonical["description_markdown"], "## Changelog")

    def test_maps_link_assets(self) -> None:
        payload = {
            "tag_name": "v1.0.0",
            "name": "v1.0.0",
            "description": "",
            "assets": {
                "links": [
                    {
                        "name": "app.apk",
                        "url": "https://example.com/app.apk",
                        "direct_asset_url": "https://example.com/direct/app.apk",
                        "link_type": "package",
                    }
                ],
                "sources": [],
            },
        }
        canonical = self.adapter.to_canonical_release(payload)
        links = canonical["assets"]["links"]
        self.assertEqual(len(links), 1)
        self.assertEqual(links[0]["name"], "app.apk")
        self.assertEqual(links[0]["direct_url"], "https://example.com/direct/app.apk")
        self.assertEqual(links[0]["type"], "package")

    def test_maps_source_assets(self) -> None:
        payload = {
            "tag_name": "v1.0.0",
            "name": "v1.0.0",
            "description": "",
            "assets": {
                "links": [],
                "sources": [
                    {"format": "zip", "url": "https://gitlab.com/g/p/-/archive/v1.0.0/p-v1.0.0.zip"},
                    {"format": "tar.gz", "url": "https://gitlab.com/g/p/-/archive/v1.0.0/p-v1.0.0.tar.gz"},
                ],
            },
        }
        canonical = self.adapter.to_canonical_release(payload)
        sources = canonical["assets"]["sources"]
        self.assertEqual(len(sources), 2)
        formats = {s["format"] for s in sources}
        self.assertIn("zip", formats)
        self.assertIn("tar.gz", formats)

    def test_empty_assets_returns_empty_lists(self) -> None:
        payload = {"tag_name": "v1.0.0", "name": "v1.0.0", "description": "", "assets": {}}
        canonical = self.adapter.to_canonical_release(payload)
        self.assertEqual(canonical["assets"]["links"], [])
        self.assertEqual(canonical["assets"]["sources"], [])

    def test_falls_back_to_tag_name_when_name_missing(self) -> None:
        payload = {"tag_name": "v2.0.0", "name": None, "description": "", "assets": {}}
        canonical = self.adapter.to_canonical_release(payload)
        self.assertEqual(canonical["name"], "v2.0.0")

    def test_maps_commit_sha(self) -> None:
        payload = {
            "tag_name": "v1.0.0",
            "name": "v1.0.0",
            "description": "",
            "commit": {"id": "abc123def456"},
            "assets": {},
        }
        canonical = self.adapter.to_canonical_release(payload)
        self.assertEqual(canonical["commit_sha"], "abc123def456")


class GitHubToCanonicalReleaseTests(unittest.TestCase):
    def setUp(self) -> None:
        self.adapter = GitHubAdapter()

    def test_maps_binary_assets(self) -> None:
        payload = {
            "tag_name": "v1.0.0",
            "name": "Release v1.0.0",
            "body": "## Changes",
            "assets": [
                {
                    "name": "app.exe",
                    "browser_download_url": "https://github.com/owner/repo/releases/download/v1.0.0/app.exe",
                }
            ],
            "zipball_url": "https://github.com/owner/repo/archive/v1.0.0.zip",
            "tarball_url": "https://github.com/owner/repo/archive/v1.0.0.tar.gz",
        }
        canonical = self.adapter.to_canonical_release(payload)
        self.assertEqual(canonical["tag_name"], "v1.0.0")
        self.assertEqual(canonical["description_markdown"], "## Changes")
        links = canonical["assets"]["links"]
        self.assertEqual(len(links), 1)
        self.assertEqual(links[0]["name"], "app.exe")
        sources = canonical["assets"]["sources"]
        self.assertEqual(len(sources), 2)

    def test_empty_assets_list(self) -> None:
        payload = {
            "tag_name": "v1.0.0",
            "name": "v1.0.0",
            "body": "",
            "assets": [],
            "zipball_url": "",
            "tarball_url": "",
        }
        canonical = self.adapter.to_canonical_release(payload)
        self.assertEqual(canonical["assets"]["links"], [])
        self.assertEqual(canonical["assets"]["sources"], [])

    def test_maps_commit_sha_from_target_commitish(self) -> None:
        payload = {
            "tag_name": "v1.0.0",
            "name": "v1.0.0",
            "body": "",
            "assets": [],
            "zipball_url": "",
            "tarball_url": "",
            "target_commitish": "main",
        }
        canonical = self.adapter.to_canonical_release(payload)
        self.assertEqual(canonical["commit_sha"], "main")


class GitHubListReleasesTests(unittest.TestCase):
    def setUp(self) -> None:
        self.adapter = GitHubAdapter()
        self.ref = _make_github_ref()

    def test_single_page(self) -> None:
        page1 = [{"tag_name": f"v1.{i}.0", "name": f"Release {i}"} for i in range(3)]

        with patch.object(self.adapter, "gh_api_json", return_value=page1):
            releases = self.adapter.list_releases(self.ref, "token")
        self.assertEqual(len(releases), 3)

    def test_paginates_when_page_full(self) -> None:
        page1 = [{"tag_name": f"v1.{i}.0"} for i in range(100)]
        page2 = [{"tag_name": "v2.0.0"}]
        call_count = [0]

        def _fake(token: str, path: str) -> list:
            call_count[0] += 1
            return page1 if call_count[0] == 1 else page2

        with patch.object(self.adapter, "gh_api_json", side_effect=_fake):
            releases = self.adapter.list_releases(self.ref, "token")
        self.assertEqual(len(releases), 101)
        self.assertEqual(call_count[0], 2)

    def test_stops_at_empty_page(self) -> None:
        with patch.object(self.adapter, "gh_api_json", return_value=[]):
            releases = self.adapter.list_releases(self.ref, "token")
        self.assertEqual(releases, [])

    def test_ignores_non_dict_items(self) -> None:
        mixed = [{"tag_name": "v1.0.0"}, "bad_item", None, {"tag_name": "v1.1.0"}]
        with patch.object(self.adapter, "gh_api_json", return_value=mixed):
            releases = self.adapter.list_releases(self.ref, "token")
        self.assertEqual(len(releases), 2)


class GitHubCreateTagRefTests(unittest.TestCase):
    def setUp(self) -> None:
        self.adapter = GitHubAdapter()
        self.ref = _make_github_ref()

    def test_calls_gh_api_with_correct_args(self) -> None:
        captured: list[list] = []

        def _fake_run_cmd(cmd: list, env: dict | None = None, check: bool = True) -> object:
            captured.append(list(cmd))

            class _Proc:
                returncode = 0
                stdout = ""
                stderr = ""

            return _Proc()

        with patch("git_forge_release_migrator.providers.github.run_cmd", side_effect=_fake_run_cmd):
            self.adapter.create_tag_ref(self.ref, "my-token", "v1.0.0", "abc123")

        self.assertEqual(len(captured), 1)
        cmd = captured[0]
        self.assertIn("gh", cmd)
        self.assertIn("POST", cmd)
        self.assertTrue(any("refs/tags/v1.0.0" in arg for arg in cmd))
        self.assertTrue(any("abc123" in arg for arg in cmd))


class GitLabReleaseExistsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.adapter = GitLabAdapter()
        self.ref = _make_gitlab_ref()

    def test_returns_true_when_status_200(self) -> None:
        with patch("git_forge_release_migrator.providers.gitlab.request_status", return_value=200):
            self.assertTrue(self.adapter.release_exists(self.ref, "token", "v1.0.0"))

    def test_returns_false_when_status_404(self) -> None:
        with patch("git_forge_release_migrator.providers.gitlab.request_status", return_value=404):
            self.assertFalse(self.adapter.release_exists(self.ref, "token", "v1.0.0"))

    def test_returns_false_when_status_401(self) -> None:
        with patch("git_forge_release_migrator.providers.gitlab.request_status", return_value=401):
            self.assertFalse(self.adapter.release_exists(self.ref, "token", "v1.0.0"))


if __name__ == "__main__":
    unittest.main()
