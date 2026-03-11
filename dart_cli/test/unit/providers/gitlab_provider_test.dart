import 'package:gfrm_dart/src/core/adapters/provider_adapter.dart';
import 'package:gfrm_dart/src/core/types/canonical_link.dart';
import 'package:gfrm_dart/src/core/types/canonical_release.dart';
import 'package:gfrm_dart/src/core/types/canonical_source.dart';
import 'package:gfrm_dart/src/core/types/phase.dart';
import 'package:gfrm_dart/src/providers/gitlab.dart';
import '../../support/http_stubs.dart';
import 'package:test/test.dart';

void main() {
  group('GitLabAdapter', () {
    test('parseUrl supports https project with subgroup', () {
      final GitLabAdapter adapter = GitLabAdapter();

      final ProviderRef ref = adapter.parseUrl('https://gitlab.com/group/subgroup/project.git');

      expect(ref.provider, 'gitlab');
      expect(ref.baseUrl, 'https://gitlab.com');
      expect(ref.host, 'gitlab.com');
      expect(ref.resource, 'group/subgroup/project');
      expect(ref.metadata['project_path'], 'group/subgroup/project');
      expect(ref.metadata['project_encoded'], 'group%2Fsubgroup%2Fproject');
    });

    test('parseUrl supports ssh project URL', () {
      final GitLabAdapter adapter = GitLabAdapter();

      final ProviderRef ref = adapter.parseUrl('git@gitlab.example.com:team/api.git');

      expect(ref.baseUrl, 'https://gitlab.example.com');
      expect(ref.host, 'gitlab.example.com');
      expect(ref.resource, 'team/api');
      expect(ref.metadata['project_encoded'], 'team%2Fapi');
    });

    test('normalizeUrl keeps absolute and resolves relative URLs', () {
      final GitLabAdapter adapter = GitLabAdapter();
      final ProviderRef ref = adapter.parseUrl('https://gitlab.com/team/app');

      expect(
        adapter.normalizeUrl(ref, 'https://cdn.gitlab.com/file.zip'),
        'https://cdn.gitlab.com/file.zip',
      );
      expect(adapter.normalizeUrl(ref, '/team/app/uploads/abc/file.zip'),
          'https://gitlab.com/team/app/uploads/abc/file.zip');
      expect(adapter.normalizeUrl(ref, 'team/app/uploads/abc/file.zip'),
          'https://gitlab.com/team/app/uploads/abc/file.zip');
    });

    test('buildReleaseDownloadApiUrl maps release download links to API endpoint', () {
      final GitLabAdapter adapter = GitLabAdapter();
      final ProviderRef ref = adapter.parseUrl('https://gitlab.com/acme/project');

      final String url = adapter.buildReleaseDownloadApiUrl(
        ref,
        'v1.2.3',
        'https://gitlab.com/acme/project/-/releases/v1.2.3/downloads/bin/app.zip?download=1',
      );

      expect(
        url,
        'https://gitlab.com/api/v4/projects/acme%2Fproject/releases/v1.2.3/downloads/bin/app.zip',
      );
    });

    test('buildProjectUploadApiUrl maps upload links to API endpoint', () {
      final GitLabAdapter adapter = GitLabAdapter();
      final ProviderRef ref = adapter.parseUrl('https://gitlab.com/acme/project');

      final String url = adapter.buildProjectUploadApiUrl(
        ref,
        'https://gitlab.com/acme/project/uploads/secret/path/to/file.tar.gz?download=1',
      );

      expect(
        url,
        'https://gitlab.com/api/v4/projects/acme%2Fproject/uploads/secret/path%2Fto%2Ffile.tar.gz',
      );
    });

    test('addPrivateTokenQuery appends token without dropping existing params', () {
      final GitLabAdapter adapter = GitLabAdapter();

      final Uri uri = Uri.parse(adapter.addPrivateTokenQuery('https://gitlab.com/path?a=1', 'token-123'));

      expect(uri.queryParameters['a'], '1');
      expect(uri.queryParameters['private_token'], 'token-123');
    });

    test('toCanonicalRelease normalizes assets links and sources', () {
      final GitLabAdapter adapter = GitLabAdapter();

      final dynamic canonical = adapter.toCanonicalRelease(<String, dynamic>{
        'tag_name': 'v1.0.0',
        'name': 'Release v1.0.0',
        'description': 'notes',
        'commit': <String, dynamic>{'id': 'sha123'},
        'assets': <String, dynamic>{
          'links': <Map<String, dynamic>>[
            <String, dynamic>{
              'name': 'binary',
              'url': '/acme/project/-/releases/v1.0.0/downloads/bin',
              'direct_asset_url': '/acme/project/uploads/abc/bin',
              'link_type': 'other',
            },
          ],
          'sources': <Map<String, dynamic>>[
            <String, dynamic>{
              'format': 'zip',
              'url': 'https://gitlab.com/acme/project/-/archive/v1.0.0/project-v1.0.0.zip',
            },
          ],
        },
      });

      expect(canonical.tagName, 'v1.0.0');
      expect(canonical.name, 'Release v1.0.0');
      expect(canonical.descriptionMarkdown, 'notes');
      expect(canonical.commitSha, 'sha123');
      expect(canonical.assets.links, hasLength(1));
      expect(canonical.assets.links.first.directUrl, '/acme/project/uploads/abc/bin');
      expect(canonical.assets.sources, hasLength(1));
      expect(canonical.assets.sources.first.name, 'project-v1.0.0.zip');
    });

    test('supports source fallback tag notes', () {
      final GitLabAdapter adapter = GitLabAdapter();

      expect(adapter.supportsSourceFallbackTagNotes(), isTrue);
    });

    test('buildTagUrl points to tag page', () {
      final GitLabAdapter adapter = GitLabAdapter();
      final ProviderRef ref = adapter.parseUrl('https://gitlab.com/acme/project');

      expect(adapter.buildTagUrl(ref, 'v1.0.0'), 'https://gitlab.com/acme/project/-/tags/v1.0.0');
    });

    test('buildRepositoryArchiveApiUrl builds correct endpoint', () {
      final GitLabAdapter adapter = GitLabAdapter();
      final ProviderRef ref = adapter.parseUrl('https://gitlab.com/acme/project');

      final String url = adapter.buildRepositoryArchiveApiUrl(ref, 'v1.0.0', 'zip');

      expect(url, 'https://gitlab.com/api/v4/projects/acme%2Fproject/repository/archive.zip?sha=v1.0.0');
    });

    test('parseUrl rejects empty URL', () {
      final GitLabAdapter adapter = GitLabAdapter();

      expect(() => adapter.parseUrl('   '), throwsArgumentError);
    });

    test('parseUrl rejects URL that is not HTTPS or SSH', () {
      final GitLabAdapter adapter = GitLabAdapter();

      expect(() => adapter.parseUrl('ftp://gitlab.com/group/project'), throwsArgumentError);
    });

    test('toCanonicalRelease uses tag name when release name is null', () {
      final GitLabAdapter adapter = GitLabAdapter();

      final dynamic canonical = adapter.toCanonicalRelease(<String, dynamic>{
        'tag_name': 'v2.0.0',
        'name': null,
        'description': '',
        'commit': <String, dynamic>{'id': ''},
        'assets': <String, dynamic>{
          'links': <dynamic>[],
          'sources': <dynamic>[],
        },
      });

      expect(canonical.tagName, 'v2.0.0');
      expect(canonical.name, 'v2.0.0');
      expect(canonical.assets.links, isEmpty);
      expect(canonical.assets.sources, isEmpty);
    });

    group('HTTP methods (via stub)', () {
      test('listTags returns tag names from paginated response', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(
          jsonResponse: <dynamic>[
            <String, dynamic>{'name': 'v1.0.0'},
            <String, dynamic>{'name': 'v2.0.0'},
          ],
        );
        final GitLabAdapter adapter = GitLabAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://gitlab.com/acme/project');

        final List<String> tags = await adapter.listTags(ref, 'token');

        expect(tags, <String>['v1.0.0', 'v2.0.0']);
      });

      test('listTags returns empty list when response is not a List', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(jsonResponse: null);
        final GitLabAdapter adapter = GitLabAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://gitlab.com/acme/project');

        final List<String> tags = await adapter.listTags(ref, 'token');

        expect(tags, isEmpty);
      });

      test('listReleases returns releases from paginated response', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(
          jsonResponse: <dynamic>[
            <String, dynamic>{'tag_name': 'v1.0.0', 'name': 'Release v1.0.0'},
          ],
        );
        final GitLabAdapter adapter = GitLabAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://gitlab.com/acme/project');

        final List<Map<String, dynamic>> releases = await adapter.listReleases(ref, 'token');

        expect(releases, hasLength(1));
        expect(releases.first['tag_name'], 'v1.0.0');
      });

      test('listReleases returns empty list when response is empty', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(jsonResponse: <dynamic>[]);
        final GitLabAdapter adapter = GitLabAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://gitlab.com/acme/project');

        final List<Map<String, dynamic>> releases = await adapter.listReleases(ref, 'token');

        expect(releases, isEmpty);
      });

      test('tagExists returns true when status is 200', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(statusCode: 200);
        final GitLabAdapter adapter = GitLabAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://gitlab.com/acme/project');

        expect(await adapter.tagExists(ref, 'token', 'v1.0.0'), isTrue);
      });

      test('tagExists returns false when status is 404', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(statusCode: 404);
        final GitLabAdapter adapter = GitLabAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://gitlab.com/acme/project');

        expect(await adapter.tagExists(ref, 'token', 'v9.9.9'), isFalse);
      });

      test('tagCommitSha returns id from target field', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(
          jsonResponse: <String, dynamic>{
            'name': 'v1.0.0',
            'target': 'abc123',
          },
        );
        final GitLabAdapter adapter = GitLabAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://gitlab.com/acme/project');

        expect(await adapter.tagCommitSha(ref, 'token', 'v1.0.0'), 'abc123');
      });

      test('tagCommitSha returns empty string when response is not a Map', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(jsonResponse: null);
        final GitLabAdapter adapter = GitLabAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://gitlab.com/acme/project');

        expect(await adapter.tagCommitSha(ref, 'token', 'v1.0.0'), '');
      });

      test('releaseExists returns true when status is 200', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(statusCode: 200);
        final GitLabAdapter adapter = GitLabAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://gitlab.com/acme/project');

        expect(await adapter.releaseExists(ref, 'token', 'v1.0.0'), isTrue);
      });

      test('releaseExists returns false when status is 404', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(statusCode: 404);
        final GitLabAdapter adapter = GitLabAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://gitlab.com/acme/project');

        expect(await adapter.releaseExists(ref, 'token', 'v9.9.9'), isFalse);
      });

      test('releaseByTag returns release map when response is a Map', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(
          jsonResponse: <String, dynamic>{'tag_name': 'v1.0.0', 'name': 'Release v1.0.0'},
        );
        final GitLabAdapter adapter = GitLabAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://gitlab.com/acme/project');

        final Map<String, dynamic>? release = await adapter.releaseByTag(ref, 'token', 'v1.0.0');
        expect(release, isNotNull);
        expect(release!['tag_name'], 'v1.0.0');
      });

      test('releaseByTag returns null when response is not a Map', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(jsonResponse: null);
        final GitLabAdapter adapter = GitLabAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://gitlab.com/acme/project');

        expect(await adapter.releaseByTag(ref, 'token', 'v1.0.0'), isNull);
      });

      test('createOrUpdateRelease creates when release does not exist', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(
          statusResponses: <int>[404],
          jsonResponses: <dynamic>[
            <String, dynamic>{'tag_name': 'v1.0.0'}
          ],
        );
        final GitLabAdapter adapter = GitLabAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://gitlab.com/acme/project');

        await expectLater(
          adapter.createOrUpdateRelease(ref, 'token', 'v1.0.0', 'v1.0.0', 'notes', <Map<String, dynamic>>[]),
          completes,
        );
      });

      test('createOrUpdateRelease updates when release exists', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(
          statusResponses: <int>[200],
          jsonResponses: <dynamic>[<String, dynamic>{}],
        );
        final GitLabAdapter adapter = GitLabAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://gitlab.com/acme/project');

        await expectLater(
          adapter.createOrUpdateRelease(ref, 'token', 'v1.0.0', 'v1.0.0', 'notes', <Map<String, dynamic>>[]),
          completes,
        );
      });

      test('downloadWithAuth delegates to downloadFile', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper();
        final GitLabAdapter adapter = GitLabAdapter(http: stub);

        expect(await adapter.downloadWithAuth('token', 'https://cdn.example.com/f.zip', '/tmp/f.zip'), isTrue);
      });

      test('downloadNoAuth delegates to downloadFile without headers', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper();
        final GitLabAdapter adapter = GitLabAdapter(http: stub);

        expect(await adapter.downloadNoAuth('https://cdn.example.com/f.zip', '/tmp/f.zip'), isTrue);
      });

      test('existingReleaseInfo returns not-exists when release not found', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(statusCode: 404);
        final GitLabAdapter adapter = GitLabAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://gitlab.com/acme/project');

        final ExistingReleaseInfo info = await adapter.existingReleaseInfo(ref, 'token', 'v9.9.9', 0);
        expect(info.exists, isFalse);
        expect(info.shouldRetry, isFalse);
      });

      test('existingReleaseInfo returns shouldRetry when links count below expected', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(
          statusResponses: <int>[200],
          jsonResponses: <dynamic>[
            <String, dynamic>{
              'tag_name': 'v1.0.0',
              'assets': <String, dynamic>{
                'links': <dynamic>[
                  <String, dynamic>{'name': 'only.zip'}
                ],
              },
            },
          ],
        );
        final GitLabAdapter adapter = GitLabAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://gitlab.com/acme/project');

        final ExistingReleaseInfo info = await adapter.existingReleaseInfo(ref, 'token', 'v1.0.0', 3);
        expect(info.exists, isTrue);
        expect(info.shouldRetry, isTrue);
      });

      test('existingReleaseInfo returns complete when all links present', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(
          statusResponses: <int>[200],
          jsonResponses: <dynamic>[
            <String, dynamic>{
              'tag_name': 'v1.0.0',
              'assets': <String, dynamic>{
                'links': <dynamic>[
                  <String, dynamic>{'name': 'a.zip'},
                  <String, dynamic>{'name': 'b.zip'},
                ],
              },
            },
          ],
        );
        final GitLabAdapter adapter = GitLabAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://gitlab.com/acme/project');

        final ExistingReleaseInfo info = await adapter.existingReleaseInfo(ref, 'token', 'v1.0.0', 2);
        expect(info.exists, isTrue);
        expect(info.shouldRetry, isFalse);
      });

      test('downloadCanonicalLink uses directUrl when available', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper();
        final GitLabAdapter adapter = GitLabAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://gitlab.com/acme/project');
        final DownloadLinkInput input = DownloadLinkInput(
          providerRef: ref,
          token: 'token',
          tag: 'v1.0.0',
          link: CanonicalLink(
            name: 'app.zip',
            url: '',
            directUrl: 'https://cdn.gitlab.com/app.zip',
            type: 'other',
          ),
          outputPath: '/tmp/app.zip',
        );

        expect(await adapter.downloadCanonicalLink(input), isTrue);
      });

      test('downloadCanonicalSource downloads with auth', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper();
        final GitLabAdapter adapter = GitLabAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://gitlab.com/acme/project');

        final DownloadSourceInput input = DownloadSourceInput(
          providerRef: ref,
          token: 'token',
          tag: 'v1.0.0',
          source: CanonicalSource(
            name: 'v1.0.0.zip',
            url: 'https://gitlab.com/acme/project/-/archive/v1.0.0/project-v1.0.0.zip',
            format: 'zip',
          ),
          outputPath: '/tmp/src.zip',
        );

        expect(await adapter.downloadCanonicalSource(input), isTrue);
      });

      test('listTargetReleaseTags uses base class default (returns fallback tags)', () async {
        // GitLabAdapter does not override listTargetReleaseTags; the base returns fallbackTags.toSet().
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper();
        final GitLabAdapter adapter = GitLabAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://gitlab.com/acme/project');

        final Set<String> tags = await adapter.listTargetReleaseTags(ref, 'token', <String>{'v1.0.0', 'v2.0.0'});
        expect(tags, <String>{'v1.0.0', 'v2.0.0'});
      });

      test('resolveCommitShaForMigration returns canonical sha when non-empty', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper();
        final GitLabAdapter adapter = GitLabAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://gitlab.com/acme/project');
        final CanonicalRelease canonical = CanonicalRelease.fromMap(<String, dynamic>{
          'tag_name': 'v1.0.0',
          'name': 'v1.0.0',
          'description_markdown': '',
          'commit_sha': 'deadc0de',
          'assets': <String, dynamic>{'links': <dynamic>[], 'sources': <dynamic>[]},
          'provider_metadata': <String, dynamic>{},
        });

        expect(
          await adapter.resolveCommitShaForMigration(ref, 'token', 'v1.0.0', canonical),
          'deadc0de',
        );
      });

      test('resolveCommitShaForMigration calls tagCommitSha when canonical sha is empty', () async {
        final ScriptedHttpClientHelper stub =
            ScriptedHttpClientHelper(jsonResponse: <String, dynamic>{'name': 'v1.0.0', 'target': 'abc789'});
        final GitLabAdapter adapter = GitLabAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://gitlab.com/acme/project');
        final CanonicalRelease canonical = CanonicalRelease.fromMap(<String, dynamic>{
          'tag_name': 'v1.0.0',
          'name': 'v1.0.0',
          'description_markdown': '',
          'commit_sha': '',
          'assets': <String, dynamic>{'links': <dynamic>[], 'sources': <dynamic>[]},
          'provider_metadata': <String, dynamic>{},
        });

        expect(await adapter.resolveCommitShaForMigration(ref, 'token', 'v1.0.0', canonical), 'abc789');
      });

      test('listReleases paginates when page has exactly 100 items', () async {
        final List<Map<String, dynamic>> page1 = List<Map<String, dynamic>>.generate(
          100,
          (int i) => <String, dynamic>{'tag_name': 'v${i + 1}.0.0'},
        );
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(
          statusResponses: <int>[],
          jsonResponses: <dynamic>[page1, <dynamic>[]],
        );
        final GitLabAdapter adapter = GitLabAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://gitlab.com/acme/project');

        final List<Map<String, dynamic>> releases = await adapter.listReleases(ref, 'token');
        expect(releases, hasLength(100));
      });

      test('listTags paginates when page has exactly 100 items', () async {
        final List<Map<String, dynamic>> page1 = List<Map<String, dynamic>>.generate(
          100,
          (int i) => <String, dynamic>{'name': 'v${i + 1}.0.0'},
        );
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(
          statusResponses: <int>[],
          jsonResponses: <dynamic>[page1, <dynamic>[]],
        );
        final GitLabAdapter adapter = GitLabAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://gitlab.com/acme/project');

        final List<String> tags = await adapter.listTags(ref, 'token');
        expect(tags, hasLength(100));
      });
    });
  });
}
