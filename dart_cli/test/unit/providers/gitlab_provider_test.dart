import 'dart:io';

import 'package:dio/dio.dart';
import 'package:gfrm_dart/src/core/adapters/provider_adapter.dart';
import 'package:gfrm_dart/src/core/exceptions/authentication_error.dart';
import 'package:gfrm_dart/src/core/exceptions/http_request_error.dart';
import 'package:gfrm_dart/src/core/types/canonical_link.dart';
import 'package:gfrm_dart/src/core/types/canonical_release.dart';
import 'package:gfrm_dart/src/core/types/canonical_source.dart';
import 'package:gfrm_dart/src/core/types/phase.dart';
import 'package:gfrm_dart/src/providers/gitlab.dart';
import '../../support/http_stubs.dart';
import 'package:test/test.dart';

final class _QueuePostDio implements Dio {
  _QueuePostDio(this._responses);

  final List<Response<dynamic>> _responses;
  FormData? lastFormData;
  Options? lastOptions;
  String? lastUrl;

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
    lastFormData = data as FormData?;
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

final class _RecordingGitLabAdapter extends GitLabAdapter {
  _RecordingGitLabAdapter({
    this.uploadOutcomes = const <Object>[],
    this.authDownloadOutcomes = const <bool>[],
    this.noAuthDownloadOutcomes = const <bool>[],
  });

  final List<Object> uploadOutcomes;
  final List<bool> authDownloadOutcomes;
  final List<bool> noAuthDownloadOutcomes;
  final List<String> authCandidates = <String>[];
  final List<String> noAuthCandidates = <String>[];
  List<Map<String, dynamic>>? recordedLinks;
  String? recordedDescription;

  int _uploadIndex = 0;
  int _authIndex = 0;
  int _noAuthIndex = 0;

  @override
  Future<String> uploadFile(ProviderRef ref, String token, String filepath) async {
    final Object next = uploadOutcomes[_uploadIndex];
    _uploadIndex += 1;
    if (next is AuthenticationError) {
      throw next;
    }
    if (next is Exception) {
      throw next;
    }
    if (next is Error) {
      throw next;
    }
    return next as String;
  }

  @override
  Future<void> createOrUpdateRelease(
    ProviderRef ref,
    String token,
    String tag,
    String name,
    String description,
    List<Map<String, dynamic>> links,
  ) async {
    recordedDescription = description;
    recordedLinks = links;
  }

  @override
  Future<bool> downloadWithAuth(String token, String url, String destination) async {
    authCandidates.add(url);
    final bool next = _authIndex < authDownloadOutcomes.length ? authDownloadOutcomes[_authIndex] : false;
    _authIndex += 1;
    return next;
  }

  @override
  Future<bool> downloadNoAuth(String url, String destination) async {
    noAuthCandidates.add(url);
    final bool next = _noAuthIndex < noAuthDownloadOutcomes.length ? noAuthDownloadOutcomes[_noAuthIndex] : false;
    _noAuthIndex += 1;
    return next;
  }
}

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

    test('buildReleaseDownloadApiUrl returns empty string for mismatched release tag', () {
      final GitLabAdapter adapter = GitLabAdapter();
      final ProviderRef ref = adapter.parseUrl('https://gitlab.com/acme/project');

      final String url = adapter.buildReleaseDownloadApiUrl(
        ref,
        'v1.2.3',
        'https://gitlab.com/acme/project/-/releases/v9.9.9/downloads/bin/app.zip',
      );

      expect(url, isEmpty);
    });

    test('buildProjectUploadApiUrl returns empty string when upload format is invalid', () {
      final GitLabAdapter adapter = GitLabAdapter();
      final ProviderRef ref = adapter.parseUrl('https://gitlab.com/acme/project');

      expect(adapter.buildProjectUploadApiUrl(ref, 'https://gitlab.com/acme/project/uploads/no-secret'), isEmpty);
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

      test('releaseByTag rethrows AuthenticationError', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(
          jsonResponse: AuthenticationError('auth failed'),
        );
        final GitLabAdapter adapter = GitLabAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://gitlab.com/acme/project');

        await expectLater(
          () => adapter.releaseByTag(ref, 'token', 'v1.0.0'),
          throwsA(isA<AuthenticationError>()),
        );
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
        final ScriptedHttpClientHelper stub = successfulDownloadStub();
        final GitLabAdapter adapter = GitLabAdapter(http: stub);

        expect(await adapter.downloadWithAuth('token', 'https://cdn.example.com/f.zip', '/tmp/f.zip'), isTrue);
      });

      test('downloadNoAuth delegates to downloadFile without headers', () async {
        final ScriptedHttpClientHelper stub = successfulDownloadStub();
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
        final ScriptedHttpClientHelper stub = successfulDownloadStub();
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
        final ScriptedHttpClientHelper stub = successfulDownloadStub();
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

    group('POST operations', () {
      test('createTag posts tag data and succeeds on 2xx status', () async {
        final _QueuePostDio dio = _QueuePostDio(<Response<dynamic>>[
          _postResponse('https://gitlab.com/api/v4/projects/acme%2Fproject/repository/tags', 201),
        ]);
        final GitLabAdapter adapter = GitLabAdapter(dio: dio);
        final ProviderRef ref = adapter.parseUrl('https://gitlab.com/acme/project');

        await adapter.createTag(ref, 'secret', 'v1.0.0', 'abc123', message: 'annotated');

        expect(dio.lastUrl, contains('/repository/tags'));
        expect(dio.lastFormData, isNotNull);
        expect(dio.lastOptions?.headers?['PRIVATE-TOKEN'], 'secret');
      });

      test('createTag throws HttpRequestError on non-2xx status', () async {
        final _QueuePostDio dio = _QueuePostDio(<Response<dynamic>>[
          _postResponse('https://gitlab.com/api/v4/projects/acme%2Fproject/repository/tags', 500),
        ]);
        final GitLabAdapter adapter = GitLabAdapter(dio: dio);
        final ProviderRef ref = adapter.parseUrl('https://gitlab.com/acme/project');

        await expectLater(
          () => adapter.createTag(ref, 'secret', 'v1.0.0', 'abc123'),
          throwsA(isA<HttpRequestError>()),
        );
      });

      test('uploadFile returns absolute url when GitLab responds with a relative path', () async {
        final Directory temp = Directory.systemTemp.createTempSync('gfrm-gitlab-upload-success-');
        addTearDown(() => temp.deleteSync(recursive: true));
        final File asset = File('${temp.path}/asset.zip')..writeAsStringSync('payload');
        final _QueuePostDio dio = _QueuePostDio(<Response<dynamic>>[
          _postResponse(
            'https://gitlab.com/api/v4/projects/acme%2Fproject/uploads',
            201,
            data: <String, dynamic>{'url': '/uploads/secret/asset.zip'},
          ),
        ]);
        final GitLabAdapter adapter = GitLabAdapter(dio: dio);
        final ProviderRef ref = adapter.parseUrl('https://gitlab.com/acme/project');

        final String uploaded = await adapter.uploadFile(ref, 'secret', asset.path);

        expect(uploaded, 'https://gitlab.com/uploads/secret/asset.zip');
      });

      test('uploadFile throws AuthenticationError on unauthorized response', () async {
        final Directory temp = Directory.systemTemp.createTempSync('gfrm-gitlab-upload-auth-');
        addTearDown(() => temp.deleteSync(recursive: true));
        final File asset = File('${temp.path}/asset.zip')..writeAsStringSync('payload');
        final _QueuePostDio dio = _QueuePostDio(<Response<dynamic>>[
          _postResponse('https://gitlab.com/api/v4/projects/acme%2Fproject/uploads', 401),
        ]);
        final GitLabAdapter adapter = GitLabAdapter(dio: dio);
        final ProviderRef ref = adapter.parseUrl('https://gitlab.com/acme/project');

        await expectLater(
          () => adapter.uploadFile(ref, 'secret', asset.path),
          throwsA(isA<AuthenticationError>()),
        );
      });

      test('uploadFile throws HttpRequestError on non-auth failure', () async {
        final Directory temp = Directory.systemTemp.createTempSync('gfrm-gitlab-upload-error-');
        addTearDown(() => temp.deleteSync(recursive: true));
        final File asset = File('${temp.path}/asset.zip')..writeAsStringSync('payload');
        final _QueuePostDio dio = _QueuePostDio(<Response<dynamic>>[
          _postResponse('https://gitlab.com/api/v4/projects/acme%2Fproject/uploads', 500),
        ]);
        final GitLabAdapter adapter = GitLabAdapter(dio: dio);
        final ProviderRef ref = adapter.parseUrl('https://gitlab.com/acme/project');

        await expectLater(
          () => adapter.uploadFile(ref, 'secret', asset.path),
          throwsA(isA<HttpRequestError>()),
        );
      });

      test('uploadFile throws HttpRequestError when response payload has no url', () async {
        final Directory temp = Directory.systemTemp.createTempSync('gfrm-gitlab-upload-missing-url-');
        addTearDown(() => temp.deleteSync(recursive: true));
        final File asset = File('${temp.path}/asset.zip')..writeAsStringSync('payload');
        final _QueuePostDio dio = _QueuePostDio(<Response<dynamic>>[
          _postResponse(
            'https://gitlab.com/api/v4/projects/acme%2Fproject/uploads',
            201,
            data: <String, dynamic>{'path': '/uploads/secret/asset.zip'},
          ),
        ]);
        final GitLabAdapter adapter = GitLabAdapter(dio: dio);
        final ProviderRef ref = adapter.parseUrl('https://gitlab.com/acme/project');

        await expectLater(
          () => adapter.uploadFile(ref, 'secret', asset.path),
          throwsA(isA<HttpRequestError>()),
        );
      });

      test('publishRelease filters failed uploads and forwards notes plus successful links', () async {
        final Directory temp = Directory.systemTemp.createTempSync('gfrm-gitlab-publish-release-');
        addTearDown(() => temp.deleteSync(recursive: true));
        final File notesFile = File('${temp.path}/notes.md')..writeAsStringSync('release notes');
        final File assetA = File('${temp.path}/asset-a.zip')..writeAsStringSync('a');
        final File assetB = File('${temp.path}/asset-b.zip')..writeAsStringSync('b');
        final _RecordingGitLabAdapter adapter = _RecordingGitLabAdapter(
          uploadOutcomes: <Object>[
            'https://gitlab.com/uploads/a.zip',
            Exception('upload failed'),
          ],
        );
        final ProviderRef ref = adapter.parseUrl('https://gitlab.com/acme/project');

        final String result = await adapter.publishRelease(
          PublishReleaseInput(
            providerRef: ref,
            token: 'secret',
            tag: 'v1.0.0',
            releaseName: 'Release v1.0.0',
            notesFile: notesFile,
            downloadedFiles: <String>[assetA.path, assetB.path],
            expectedAssets: 2,
            existingInfo: const ExistingReleaseInfo(exists: false, shouldRetry: false, reason: ''),
          ),
        );

        expect(result, 'ok');
        expect(adapter.recordedDescription, 'release notes');
        expect(adapter.recordedLinks, hasLength(1));
        expect(adapter.recordedLinks!.single['url'], 'https://gitlab.com/uploads/a.zip');
      });

      test('publishRelease rethrows AuthenticationError from uploadFile', () async {
        final Directory temp = Directory.systemTemp.createTempSync('gfrm-gitlab-publish-auth-');
        addTearDown(() => temp.deleteSync(recursive: true));
        final File notesFile = File('${temp.path}/notes.md')..writeAsStringSync('release notes');
        final File asset = File('${temp.path}/asset.zip')..writeAsStringSync('a');
        final _RecordingGitLabAdapter adapter = _RecordingGitLabAdapter(
          uploadOutcomes: <Object>[AuthenticationError('auth failed')],
        );
        final ProviderRef ref = adapter.parseUrl('https://gitlab.com/acme/project');

        await expectLater(
          () => adapter.publishRelease(
            PublishReleaseInput(
              providerRef: ref,
              token: 'secret',
              tag: 'v1.0.0',
              releaseName: 'Release v1.0.0',
              notesFile: notesFile,
              downloadedFiles: <String>[asset.path],
              expectedAssets: 1,
              existingInfo: const ExistingReleaseInfo(exists: false, shouldRetry: false, reason: ''),
            ),
          ),
          throwsA(isA<AuthenticationError>()),
        );
      });

      test('downloadCanonicalLink falls back to no-auth private-token URL after auth candidates fail', () async {
        final _RecordingGitLabAdapter adapter = _RecordingGitLabAdapter(
          authDownloadOutcomes: <bool>[false, false],
          noAuthDownloadOutcomes: <bool>[true],
        );
        final ProviderRef ref = adapter.parseUrl('https://gitlab.com/acme/project');

        final bool downloaded = await adapter.downloadCanonicalLink(
          DownloadLinkInput(
            providerRef: ref,
            token: 'secret',
            tag: 'v1.0.0',
            link: CanonicalLink(
              name: 'asset.zip',
              url: '/acme/project/uploads/secret/path/to/asset.zip',
              directUrl: '',
              type: 'other',
            ),
            outputPath: '/tmp/asset.zip',
          ),
        );

        expect(downloaded, isTrue);
        expect(adapter.authCandidates, hasLength(2));
        expect(adapter.noAuthCandidates.single, contains('private_token=secret'));
      });

      test('downloadCanonicalSource falls back to no-auth private-token URL after auth download fails', () async {
        final _RecordingGitLabAdapter adapter = _RecordingGitLabAdapter(
          authDownloadOutcomes: <bool>[false],
          noAuthDownloadOutcomes: <bool>[true],
        );
        final ProviderRef ref = adapter.parseUrl('https://gitlab.com/acme/project');

        final bool downloaded = await adapter.downloadCanonicalSource(
          DownloadSourceInput(
            providerRef: ref,
            token: 'secret',
            tag: 'v1.0.0',
            source: CanonicalSource(
              name: 'asset.txt',
              url: '/acme/project/uploads/secret/path/to/asset.txt',
              format: 'txt',
            ),
            outputPath: '/tmp/asset.txt',
          ),
        );

        expect(downloaded, isTrue);
        expect(adapter.authCandidates, hasLength(1));
        expect(adapter.noAuthCandidates.single, contains('private_token=secret'));
      });

      test('downloadCanonicalSource returns false when no source URL is available', () async {
        final _RecordingGitLabAdapter adapter = _RecordingGitLabAdapter();
        final ProviderRef ref = adapter.parseUrl('https://gitlab.com/acme/project');

        final bool downloaded = await adapter.downloadCanonicalSource(
          DownloadSourceInput(
            providerRef: ref,
            token: 'secret',
            tag: 'v1.0.0',
            source: CanonicalSource(
              name: 'asset.txt',
              url: '',
              format: 'txt',
            ),
            outputPath: '/tmp/asset.txt',
          ),
        );

        expect(downloaded, isFalse);
        expect(adapter.noAuthCandidates, isEmpty);
      });
    });
  });
}
