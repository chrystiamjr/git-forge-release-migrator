import 'dart:io';

import 'package:dio/dio.dart';
import 'package:gfrm_dart/src/core/adapters/provider_adapter.dart';
import 'package:gfrm_dart/src/core/exceptions/http_request_error.dart';
import 'package:gfrm_dart/src/core/types/canonical_link.dart';
import 'package:gfrm_dart/src/core/types/canonical_release.dart';
import 'package:gfrm_dart/src/core/types/canonical_source.dart';
import 'package:gfrm_dart/src/core/types/phase.dart';
import 'package:gfrm_dart/src/providers/github.dart';
import '../../support/http_stubs.dart';
import '../../support/temp_dir.dart';
import 'package:test/test.dart';

final class _QueuePostDio implements Dio {
  _QueuePostDio(this._responses);

  final List<Response<dynamic>> _responses;
  String? lastUrl;
  Object? lastData;
  Options? lastOptions;

  @override
  Transformer transformer = BackgroundTransformer();

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    lastUrl = path;
    lastData = data;
    lastOptions = options;
    if (_responses.isEmpty) {
      throw StateError('No queued response for $path');
    }
    return _responses.removeAt(0) as Response<T>;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Response<dynamic> _postResponse(String path, int statusCode, {dynamic data}) {
  return Response<dynamic>(
    requestOptions: RequestOptions(path: path),
    statusCode: statusCode,
    data: data,
  );
}

final class _RecordingGitHubAdapter extends GitHubAdapter {
  _RecordingGitHubAdapter();

  int createCalls = 0;
  int uploadCalls = 0;
  int editCalls = 0;

  @override
  Future<void> releaseCreate(ProviderRef ref, String token, String tag, String title, String notesFile) async {
    createCalls += 1;
  }

  @override
  Future<void> releaseUpload(ProviderRef ref, String token, String tag, List<String> assets) async {
    uploadCalls += 1;
  }

  @override
  Future<void> releaseEdit(ProviderRef ref, String token, String tag, String title, String notesFile) async {
    editCalls += 1;
  }
}

void main() {
  group('GitHubAdapter', () {
    test('parseUrl supports https repository URLs', () {
      final GitHubAdapter adapter = GitHubAdapter();

      final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo.git');

      expect(ref.provider, 'github');
      expect(ref.baseUrl, 'https://github.com');
      expect(ref.host, 'github.com');
      expect(ref.resource, 'acme/repo');
      expect(ref.metadata['owner'], 'acme');
      expect(ref.metadata['repo'], 'repo');
      expect(ref.metadata['repo_ref'], 'acme/repo');
    });

    test('parseUrl supports ssh enterprise URLs', () {
      final GitHubAdapter adapter = GitHubAdapter();

      final ProviderRef ref = adapter.parseUrl('git@github.enterprise.local:team/service.git');

      expect(ref.baseUrl, 'https://github.enterprise.local');
      expect(ref.host, 'github.enterprise.local');
      expect(ref.resource, 'team/service');
      expect(ref.metadata['repo_ref'], 'github.enterprise.local/team/service');
    });

    test('parseUrl rejects empty values', () {
      final GitHubAdapter adapter = GitHubAdapter();

      expect(() => adapter.parseUrl('   '), throwsArgumentError);
    });

    test('buildTagUrl points to release tag page', () {
      final GitHubAdapter adapter = GitHubAdapter();
      final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo');

      final String url = adapter.buildTagUrl(ref, 'v1.2.3');

      expect(url, 'https://github.com/acme/repo/releases/tag/v1.2.3');
    });

    test('toCanonicalRelease maps assets and source archives', () {
      final GitHubAdapter adapter = GitHubAdapter();

      final Map<String, dynamic> payload = <String, dynamic>{
        'tag_name': 'v1.2.3',
        'name': '',
        'body': 'release notes',
        'target_commitish': 'abc123',
        'zipball_url': 'https://api.github.com/zipball/v1.2.3',
        'tarball_url': 'https://api.github.com/tarball/v1.2.3',
        'assets': <Map<String, dynamic>>[
          <String, dynamic>{
            'name': 'app.zip',
            'browser_download_url': 'https://github.com/acme/repo/releases/download/v1.2.3/app.zip',
          },
        ],
      };

      final dynamic canonical = adapter.toCanonicalRelease(payload);

      expect(canonical.tagName, 'v1.2.3');
      expect(canonical.name, 'v1.2.3');
      expect(canonical.descriptionMarkdown, 'release notes');
      expect(canonical.commitSha, 'abc123');
      expect(canonical.assets.links, hasLength(1));
      expect(canonical.assets.links.first.name, 'app.zip');
      expect(canonical.assets.sources, hasLength(2));
      expect(canonical.assets.sources.first.name, 'v1.2.3-source.zip');
      expect(canonical.assets.sources.last.name, 'v1.2.3-source.tar.gz');
    });

    test('toCanonicalRelease uses tag name when release name is empty', () {
      final GitHubAdapter adapter = GitHubAdapter();

      final dynamic canonical = adapter.toCanonicalRelease(<String, dynamic>{
        'tag_name': 'v3.0.0',
        'name': '',
        'body': '',
        'target_commitish': '',
        'zipball_url': '',
        'tarball_url': '',
        'assets': <dynamic>[],
      });

      expect(canonical.tagName, 'v3.0.0');
      expect(canonical.name, 'v3.0.0');
      expect(canonical.descriptionMarkdown, '');
      expect(canonical.assets.links, isEmpty);
      expect(canonical.assets.sources, isEmpty);
    });

    test('parseUrl supports https URL without .git suffix', () {
      final GitHubAdapter adapter = GitHubAdapter();

      final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo');

      expect(ref.resource, 'acme/repo');
      expect(ref.metadata['owner'], 'acme');
    });

    test('parseUrl rejects URL with no repository path', () {
      final GitHubAdapter adapter = GitHubAdapter();

      expect(() => adapter.parseUrl('https://github.com/onlyone'), throwsArgumentError);
    });

    test('parseUrl rejects URL that is not HTTPS or SSH', () {
      final GitHubAdapter adapter = GitHubAdapter();

      expect(() => adapter.parseUrl('ftp://github.com/owner/repo'), throwsArgumentError);
    });

    test('releaseByTag returns null when requestJson throws non-auth error', () async {
      final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(
          jsonResponses: <dynamic>[Exception('simulated network error')], statusCode: 0, downloadResult: false);
      final GitHubAdapter adapter = GitHubAdapter(http: stub);
      final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo');

      final Map<String, dynamic>? result = await adapter.releaseByTag(ref, 'token', 'v9.9.9');
      expect(result, isNull);
    });

    test('resolveCommitShaForMigration returns canonical sha when non-empty', () async {
      final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper();
      final GitHubAdapter adapter = GitHubAdapter(http: stub);
      final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo');
      final CanonicalRelease canonical = CanonicalRelease.fromMap(<String, dynamic>{
        'tag_name': 'v1.0.0',
        'name': 'v1.0.0',
        'description_markdown': '',
        'commit_sha': 'preexisting-sha',
        'assets': <String, dynamic>{'links': <dynamic>[], 'sources': <dynamic>[]},
        'provider_metadata': <String, dynamic>{},
      });

      expect(await adapter.resolveCommitShaForMigration(ref, 'token', 'v1.0.0', canonical), 'preexisting-sha');
    });

    test('supportsSourceFallbackTagNotes returns true', () {
      expect(GitHubAdapter().supportsSourceFallbackTagNotes(), isTrue);
    });

    group('HTTP methods (via stub)', () {
      test('listTags parses refs/tags/ format', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(
          jsonResponse: <dynamic>[
            <String, dynamic>{'ref': 'refs/tags/v1.0.0'},
            <String, dynamic>{'ref': 'refs/tags/v2.0.0'},
          ],
        );
        final GitHubAdapter adapter = GitHubAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo');

        final List<String> tags = await adapter.listTags(ref, 'token');

        expect(tags, <String>['v1.0.0', 'v2.0.0']);
      });

      test('listTags returns empty list when response is not a List', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(jsonResponse: null);
        final GitHubAdapter adapter = GitHubAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo');

        final List<String> tags = await adapter.listTags(ref, 'token');

        expect(tags, isEmpty);
      });

      test('listReleases returns releases from paginated response', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(
          jsonResponse: <dynamic>[
            <String, dynamic>{'tag_name': 'v1.0.0', 'name': 'Release v1.0.0'},
          ],
        );
        final GitHubAdapter adapter = GitHubAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo');

        final List<Map<String, dynamic>> releases = await adapter.listReleases(ref, 'token');

        expect(releases, hasLength(1));
        expect(releases.first['tag_name'], 'v1.0.0');
      });

      test('listReleases returns empty when response is empty list', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(jsonResponse: <dynamic>[]);
        final GitHubAdapter adapter = GitHubAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo');

        final List<Map<String, dynamic>> releases = await adapter.listReleases(ref, 'token');

        expect(releases, isEmpty);
      });

      test('tagExists returns true when requestJson succeeds', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(
          jsonResponse: <String, dynamic>{
            'ref': 'refs/tags/v1.0.0',
            'object': <String, dynamic>{'sha': 'abc'}
          },
        );
        final GitHubAdapter adapter = GitHubAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo');

        expect(await adapter.tagExists(ref, 'token', 'v1.0.0'), isTrue);
      });

      test('releaseByTag returns release map when found', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(
          jsonResponse: <String, dynamic>{'tag_name': 'v1.0.0', 'id': 42},
        );
        final GitHubAdapter adapter = GitHubAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo');

        final Map<String, dynamic>? release = await adapter.releaseByTag(ref, 'token', 'v1.0.0');

        expect(release, isNotNull);
        expect(release!['tag_name'], 'v1.0.0');
      });

      test('releaseByTag returns null when response is not a Map', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(jsonResponse: null);
        final GitHubAdapter adapter = GitHubAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo');

        final Map<String, dynamic>? release = await adapter.releaseByTag(ref, 'token', 'v9.9.9');

        expect(release, isNull);
      });

      test('commitShaForRef returns sha from response', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(
          jsonResponse: <String, dynamic>{'sha': 'deadbeef', 'commit': <String, dynamic>{}},
        );
        final GitHubAdapter adapter = GitHubAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo');

        expect(await adapter.commitShaForRef(ref, 'token', 'main'), 'deadbeef');
      });

      test('commitShaForRef throws HttpRequestError when sha is missing', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(jsonResponse: <String, dynamic>{});
        final GitHubAdapter adapter = GitHubAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo');

        await expectLater(adapter.commitShaForRef(ref, 'token', 'main'), throwsA(isA<HttpRequestError>()));
      });

      test('listReleaseTags extracts tag_name from releases', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(
          jsonResponse: <dynamic>[
            <String, dynamic>{'tag_name': 'v1.0.0'},
            <String, dynamic>{'tag_name': 'v2.0.0'},
          ],
        );
        final GitHubAdapter adapter = GitHubAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo');

        final List<String> tags = await adapter.listReleaseTags(ref, 'token');
        expect(tags, <String>['v1.0.0', 'v2.0.0']);
      });

      test('tagExists returns false when requestJson throws non-auth error', () async {
        // ScriptedHttpClientHelper returns null, which causes _apiJson to return null, and
        // tagExists has a catch-all that returns false.
        // We use a throwing stub to simulate any non-auth error.
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(
            jsonResponses: <dynamic>[Exception('simulated network error')], statusCode: 0, downloadResult: false);
        final GitHubAdapter adapter = GitHubAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo');

        expect(await adapter.tagExists(ref, 'token', 'v9.9.9'), isFalse);
      });

      test('releaseExists returns true when releaseByTag returns a map', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(
          jsonResponse: <String, dynamic>{'tag_name': 'v1.0.0', 'id': 1},
        );
        final GitHubAdapter adapter = GitHubAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo');

        expect(await adapter.releaseExists(ref, 'token', 'v1.0.0'), isTrue);
      });

      test('releaseExists returns false when releaseByTag returns null', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(jsonResponse: null);
        final GitHubAdapter adapter = GitHubAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo');

        expect(await adapter.releaseExists(ref, 'token', 'v9.9.9'), isFalse);
      });

      test('createTagRef completes without error', () async {
        final ScriptedHttpClientHelper stub =
            ScriptedHttpClientHelper(jsonResponse: <String, dynamic>{'ref': 'refs/tags/v1.0.0'});
        final GitHubAdapter adapter = GitHubAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo');

        await expectLater(adapter.createTagRef(ref, 'token', 'v1.0.0', 'abc123'), completes);
      });

      test('createTag delegates to createTagRef and completes', () async {
        final ScriptedHttpClientHelper stub =
            ScriptedHttpClientHelper(jsonResponse: <String, dynamic>{'ref': 'refs/tags/v1.0.0'});
        final GitHubAdapter adapter = GitHubAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo');

        await expectLater(adapter.createTag(ref, 'token', 'v1.0.0', 'abc123'), completes);
      });

      test('tagCommitSha delegates to commitShaForRef', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(
          jsonResponse: <String, dynamic>{'sha': 'cafebabe'},
        );
        final GitHubAdapter adapter = GitHubAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo');

        expect(await adapter.tagCommitSha(ref, 'token', 'v1.0.0'), 'cafebabe');
      });

      test('downloadWithToken delegates to downloadFile', () async {
        final ScriptedHttpClientHelper stub = successfulDownloadStub();
        final GitHubAdapter adapter = GitHubAdapter(http: stub);

        expect(await adapter.downloadWithToken('token', 'https://example.com/f.zip', '/tmp/f.zip'), isTrue);
      });

      test('downloadWithAuth delegates to downloadWithToken', () async {
        final ScriptedHttpClientHelper stub = successfulDownloadStub();
        final GitHubAdapter adapter = GitHubAdapter(http: stub);

        expect(await adapter.downloadWithAuth('token', 'https://example.com/f.zip', '/tmp/f.zip'), isTrue);
      });

      test('listTargetReleaseTags returns release tags as set', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(
          jsonResponse: <dynamic>[
            <String, dynamic>{'tag_name': 'v1.0.0', 'name': 'Release v1.0.0'},
            <String, dynamic>{'tag_name': 'v2.0.0', 'name': 'Release v2.0.0'},
          ],
        );
        final GitHubAdapter adapter = GitHubAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo');

        final Set<String> tags = await adapter.listTargetReleaseTags(ref, 'token', <String>{'fallback'});
        expect(tags, containsAll(<String>['v1.0.0', 'v2.0.0']));
      });

      test('createTagForMigration delegates to createTagRef', () async {
        final ScriptedHttpClientHelper stub =
            ScriptedHttpClientHelper(jsonResponse: <String, dynamic>{'ref': 'refs/tags/v1.0.0'});
        final GitHubAdapter adapter = GitHubAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo');
        final CanonicalRelease canonical = CanonicalRelease.fromMap(<String, dynamic>{
          'tag_name': 'v1.0.0',
          'name': 'v1.0.0',
          'description_markdown': '',
          'commit_sha': 'abc',
          'assets': <String, dynamic>{'links': <dynamic>[], 'sources': <dynamic>[]},
          'provider_metadata': <String, dynamic>{},
        });

        await expectLater(adapter.createTagForMigration(ref, 'token', 'v1.0.0', 'abc123', canonical), completes);
      });

      test('isReleaseAlreadyProcessed returns false when status not terminal', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper();
        final GitHubAdapter adapter = GitHubAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo');

        expect(await adapter.isReleaseAlreadyProcessed(ref, 'token', 'v1.0.0', 'in_progress', <String>{}), isFalse);
      });

      test('isReleaseAlreadyProcessed returns true when terminal and tag in set', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper();
        final GitHubAdapter adapter = GitHubAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo');

        expect(
          await adapter.isReleaseAlreadyProcessed(ref, 'token', 'v1.0.0', 'created', <String>{'v1.0.0'}),
          isTrue,
        );
      });

      test('existingReleaseInfo returns not-exists when release not found', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(jsonResponse: null);
        final GitHubAdapter adapter = GitHubAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo');

        final ExistingReleaseInfo info = await adapter.existingReleaseInfo(ref, 'token', 'v1.0.0', 0);
        expect(info.exists, isFalse);
        expect(info.shouldRetry, isFalse);
      });

      test('existingReleaseInfo returns shouldRetry for draft release', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(
          jsonResponse: <String, dynamic>{'tag_name': 'v1.0.0', 'draft': true, 'assets': <dynamic>[]},
        );
        final GitHubAdapter adapter = GitHubAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo');

        final ExistingReleaseInfo info = await adapter.existingReleaseInfo(ref, 'token', 'v1.0.0', 0);
        expect(info.exists, isTrue);
        expect(info.shouldRetry, isTrue);
      });

      test('existingReleaseInfo returns shouldRetry when asset count below expected', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(
          jsonResponse: <String, dynamic>{
            'tag_name': 'v1.0.0',
            'draft': false,
            'assets': <dynamic>[
              <String, dynamic>{'name': 'file.zip'}
            ],
          },
        );
        final GitHubAdapter adapter = GitHubAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo');

        final ExistingReleaseInfo info = await adapter.existingReleaseInfo(ref, 'token', 'v1.0.0', 3);
        expect(info.exists, isTrue);
        expect(info.shouldRetry, isTrue);
      });

      test('existingReleaseInfo returns complete when all assets present', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(
          jsonResponse: <String, dynamic>{
            'tag_name': 'v1.0.0',
            'draft': false,
            'assets': <dynamic>[
              <String, dynamic>{'name': 'a.zip'},
              <String, dynamic>{'name': 'b.zip'}
            ],
          },
        );
        final GitHubAdapter adapter = GitHubAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo');

        final ExistingReleaseInfo info = await adapter.existingReleaseInfo(ref, 'token', 'v1.0.0', 2);
        expect(info.exists, isTrue);
        expect(info.shouldRetry, isFalse);
      });

      test('downloadCanonicalLink uses directUrl when available', () async {
        final ScriptedHttpClientHelper stub = successfulDownloadStub();
        final GitHubAdapter adapter = GitHubAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo');
        final DownloadLinkInput input = DownloadLinkInput(
          providerRef: ref,
          token: 'token',
          tag: 'v1.0.0',
          link: CanonicalLink(name: 'app.zip', url: '', directUrl: 'https://cdn.example.com/app.zip', type: 'other'),
          outputPath: '/tmp/app.zip',
        );

        expect(await adapter.downloadCanonicalLink(input), isTrue);
      });

      test('downloadCanonicalSource downloads source archive', () async {
        final ScriptedHttpClientHelper stub = successfulDownloadStub();
        final GitHubAdapter adapter = GitHubAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo');

        final Directory temp = createTempDir('gfrm-gh-src-');
        addTearDown(() => temp.deleteSync(recursive: true));
        final DownloadSourceInput input = DownloadSourceInput(
          providerRef: ref,
          token: 'token',
          tag: 'v1.0.0',
          source: CanonicalSource(name: 'v1.0.0.zip', url: 'https://example.com/v1.0.0.zip', format: 'zip'),
          outputPath: '${temp.path}/src.zip',
        );

        expect(await adapter.downloadCanonicalSource(input), isTrue);
      });

      test('releaseCreate writes notes and completes', () async {
        final Directory temp = createTempDir('gfrm-gh-create-');
        addTearDown(() => temp.deleteSync(recursive: true));
        final File notes = File('${temp.path}/notes.md')..writeAsStringSync('## Changes\n\n- fix bug');

        final ScriptedHttpClientHelper stub =
            ScriptedHttpClientHelper(jsonResponse: <String, dynamic>{'id': 1, 'tag_name': 'v1.0.0'});
        final GitHubAdapter adapter = GitHubAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo');

        await expectLater(adapter.releaseCreate(ref, 'token', 'v1.0.0', 'v1.0.0', notes.path), completes);
      });

      test('releaseCreate with nonexistent notes file completes', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(jsonResponse: <String, dynamic>{'id': 1});
        final GitHubAdapter adapter = GitHubAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo');

        await expectLater(
          adapter.releaseCreate(ref, 'token', 'v1.0.0', 'v1.0.0', '/tmp/nonexistent-gfrm-notes.md'),
          completes,
        );
      });

      test('releaseEdit with valid release id completes', () async {
        final Directory temp = createTempDir('gfrm-gh-edit-');
        addTearDown(() => temp.deleteSync(recursive: true));
        final File notes = File('${temp.path}/notes.md')..writeAsStringSync('updated notes');

        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(
          jsonResponses: <dynamic>[
            <String, dynamic>{'id': 42, 'tag_name': 'v1.0.0'},
            <String, dynamic>{'id': 42, 'tag_name': 'v1.0.0'},
          ],
        );
        final GitHubAdapter adapter = GitHubAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo');

        await expectLater(adapter.releaseEdit(ref, 'token', 'v1.0.0', 'v1.0.0', notes.path), completes);
      });

      test('releaseEdit throws when release not found', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(jsonResponse: null);
        final GitHubAdapter adapter = GitHubAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo');

        await expectLater(
          adapter.releaseEdit(ref, 'token', 'v9.9.9', 'v9.9.9', '/tmp/notes.md'),
          throwsA(isA<HttpRequestError>()),
        );
      });

      test('releaseEdit throws when release id is missing', () async {
        final ScriptedHttpClientHelper stub =
            ScriptedHttpClientHelper(jsonResponse: <String, dynamic>{'tag_name': 'v1.0.0'});
        final GitHubAdapter adapter = GitHubAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo');

        await expectLater(
          adapter.releaseEdit(ref, 'token', 'v1.0.0', 'v1.0.0', '/tmp/notes.md'),
          throwsA(isA<HttpRequestError>()),
        );
      });

      test('releaseUpload returns immediately when assets list is empty', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(
          jsonResponse: <String, dynamic>{
            'upload_url': 'https://uploads.github.com/repos/acme/repo/releases/1/assets{?name,label}'
          },
        );
        final _QueuePostDio dio = _QueuePostDio(<Response<dynamic>>[]);
        final GitHubAdapter adapter = GitHubAdapter(http: stub, dio: dio);
        final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo');

        await adapter.releaseUpload(ref, 'token', 'v1.0.0', <String>[]);

        expect(dio.lastUrl, isNull);
      });

      test('releaseUpload throws when release is missing', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(jsonResponse: null);
        final _QueuePostDio dio = _QueuePostDio(<Response<dynamic>>[]);
        final GitHubAdapter adapter = GitHubAdapter(http: stub, dio: dio);
        final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo');

        await expectLater(
          adapter.releaseUpload(ref, 'token', 'v1.0.0', <String>['/tmp/missing.zip']),
          throwsA(isA<HttpRequestError>()),
        );
      });

      test('releaseUpload throws when upload_url is missing', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(
          jsonResponse: <String, dynamic>{'id': 1},
        );
        final _QueuePostDio dio = _QueuePostDio(<Response<dynamic>>[]);
        final GitHubAdapter adapter = GitHubAdapter(http: stub, dio: dio);
        final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo');

        await expectLater(
          adapter.releaseUpload(ref, 'token', 'v1.0.0', <String>['/tmp/missing.zip']),
          throwsA(isA<HttpRequestError>()),
        );
      });

      test('releaseUpload skips missing files and uploads existing assets', () async {
        final Directory temp = createTempDir('gfrm-gh-upload-success-');
        addTearDown(() => temp.deleteSync(recursive: true));
        final File asset = File('${temp.path}/asset.zip')..writeAsStringSync('payload');
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(
          jsonResponse: <String, dynamic>{
            'upload_url': 'https://uploads.github.com/repos/acme/repo/releases/1/assets{?name,label}',
          },
        );
        final _QueuePostDio dio = _QueuePostDio(<Response<dynamic>>[
          _postResponse('https://uploads.github.com/repos/acme/repo/releases/1/assets?name=asset.zip', 201),
        ]);
        final GitHubAdapter adapter = GitHubAdapter(http: stub, dio: dio);
        final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo');

        await adapter.releaseUpload(ref, 'token', 'v1.0.0', <String>['${temp.path}/missing.zip', asset.path]);

        expect(dio.lastUrl, contains('name=asset.zip'));
        expect(dio.lastOptions?.headers?['Content-Type'], 'application/octet-stream');
        expect(dio.lastOptions?.validateStatus?.call(HttpStatus.internalServerError), isTrue);
      });

      test('releaseUpload throws when GitHub asset upload returns non-2xx', () async {
        final Directory temp = createTempDir('gfrm-gh-upload-failure-');
        addTearDown(() => temp.deleteSync(recursive: true));
        final File asset = File('${temp.path}/asset.zip')..writeAsStringSync('payload');
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(
          jsonResponse: <String, dynamic>{
            'upload_url': 'https://uploads.github.com/repos/acme/repo/releases/1/assets{?name,label}',
          },
        );
        final _QueuePostDio dio = _QueuePostDio(<Response<dynamic>>[
          _postResponse('https://uploads.github.com/repos/acme/repo/releases/1/assets?name=asset.zip', 500),
        ]);
        final GitHubAdapter adapter = GitHubAdapter(http: stub, dio: dio);
        final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo');

        await expectLater(
          adapter.releaseUpload(ref, 'token', 'v1.0.0', <String>[asset.path]),
          throwsA(isA<HttpRequestError>()),
        );
      });

      test('resolveCommitShaForMigration calls commitShaForRef when canonical sha is empty', () async {
        final ScriptedHttpClientHelper stub =
            ScriptedHttpClientHelper(jsonResponse: <String, dynamic>{'sha': 'feedcafe'});
        final GitHubAdapter adapter = GitHubAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo');
        final CanonicalRelease canonical = CanonicalRelease.fromMap(<String, dynamic>{
          'tag_name': 'v1.0.0',
          'name': 'v1.0.0',
          'description_markdown': '',
          'commit_sha': '',
          'assets': <String, dynamic>{'links': <dynamic>[], 'sources': <dynamic>[]},
          'provider_metadata': <String, dynamic>{},
        });

        expect(await adapter.resolveCommitShaForMigration(ref, 'token', 'v1.0.0', canonical), 'feedcafe');
      });

      test('listReleases paginates when page has exactly 100 items', () async {
        final List<Map<String, dynamic>> page1 = List<Map<String, dynamic>>.generate(
          100,
          (int i) => <String, dynamic>{'tag_name': 'v${i + 1}.0.0', 'name': 'v${i + 1}.0.0'},
        );
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(
          jsonResponses: <dynamic>[page1, <dynamic>[]],
        );
        final GitHubAdapter adapter = GitHubAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo');

        final List<Map<String, dynamic>> releases = await adapter.listReleases(ref, 'token');
        expect(releases, hasLength(100));
      });

      test('publishRelease creates, uploads, edits, and returns ok for new release', () async {
        final Directory temp = createTempDir('gfrm-gh-publish-new-');
        addTearDown(() => temp.deleteSync(recursive: true));
        final File notes = File('${temp.path}/notes.md')..writeAsStringSync('notes');
        final _RecordingGitHubAdapter adapter = _RecordingGitHubAdapter();
        final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo');

        final String result = await adapter.publishRelease(
          PublishReleaseInput(
            providerRef: ref,
            token: 'token',
            tag: 'v1.0.0',
            releaseName: 'Release v1.0.0',
            notesFile: notes,
            downloadedFiles: <String>['${temp.path}/asset.zip'],
            expectedAssets: 1,
            existingInfo: const ExistingReleaseInfo(exists: false, shouldRetry: false, reason: ''),
          ),
        );

        expect(result, 'ok');
        expect(adapter.createCalls, 1);
        expect(adapter.uploadCalls, 1);
        expect(adapter.editCalls, 1);
      });

      test('publishRelease skips create when release already exists', () async {
        final Directory temp = createTempDir('gfrm-gh-publish-existing-');
        addTearDown(() => temp.deleteSync(recursive: true));
        final File notes = File('${temp.path}/notes.md')..writeAsStringSync('notes');
        final _RecordingGitHubAdapter adapter = _RecordingGitHubAdapter();
        final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo');

        final String result = await adapter.publishRelease(
          PublishReleaseInput(
            providerRef: ref,
            token: 'token',
            tag: 'v1.0.0',
            releaseName: 'Release v1.0.0',
            notesFile: notes,
            downloadedFiles: <String>[],
            expectedAssets: 0,
            existingInfo: const ExistingReleaseInfo(exists: true, shouldRetry: false, reason: ''),
          ),
        );

        expect(result, 'ok');
        expect(adapter.createCalls, 0);
        expect(adapter.uploadCalls, 1);
        expect(adapter.editCalls, 1);
      });

      test('downloadCanonicalLink returns false when both URLs are empty', () async {
        final ScriptedHttpClientHelper stub = successfulDownloadStub();
        final GitHubAdapter adapter = GitHubAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo');

        final bool downloaded = await adapter.downloadCanonicalLink(
          DownloadLinkInput(
            providerRef: ref,
            token: 'token',
            tag: 'v1.0.0',
            link: CanonicalLink(name: 'asset.zip', url: '', directUrl: '', type: 'other'),
            outputPath: '/tmp/asset.zip',
          ),
        );

        expect(downloaded, isFalse);
      });
    });
  });
}
