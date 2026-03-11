import 'dart:io';

import 'package:dio/dio.dart';
import 'package:gfrm_dart/src/core/adapters/provider_adapter.dart';
import 'package:gfrm_dart/src/core/types/canonical_link.dart';
import 'package:gfrm_dart/src/core/types/canonical_release.dart';
import 'package:gfrm_dart/src/core/types/canonical_source.dart';
import 'package:gfrm_dart/src/core/types/download_link_input.dart';
import 'package:gfrm_dart/src/core/types/download_source_input.dart';
import 'package:gfrm_dart/src/core/types/existing_release_info.dart';
import 'package:gfrm_dart/src/core/types/publish_release_input.dart';
import 'package:gfrm_dart/src/core/exceptions/authentication_error.dart';
import 'package:gfrm_dart/src/core/exceptions/http_request_error.dart';
import 'package:gfrm_dart/src/providers/bitbucket.dart';
import '../../support/http_stubs.dart';
import '../../support/temp_dir.dart';
import 'package:test/test.dart';

final class _QueueDio implements Dio {
  _QueueDio({List<Response<dynamic>>? postResults}) : _postResults = postResults ?? <Response<dynamic>>[];

  final List<Response<dynamic>> _postResults;

  @override
  Transformer transformer = BackgroundTransformer();

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    Options? options,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    if (_postResults.isEmpty) {
      throw StateError('No queued post result for $path');
    }

    return _postResults.removeAt(0) as Response<T>;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}

Response<dynamic> _response(String path, int statusCode, {dynamic data}) {
  return Response<dynamic>(
    requestOptions: RequestOptions(path: path),
    statusCode: statusCode,
    data: data,
  );
}

void main() {
  group('BitbucketAdapter', () {
    test('parseUrl supports bitbucket cloud https URLs', () {
      final BitbucketAdapter adapter = BitbucketAdapter();

      final ProviderRef ref = adapter.parseUrl('https://bitbucket.org/workspace/repo.git');

      expect(ref.provider, 'bitbucket');
      expect(ref.baseUrl, 'https://bitbucket.org');
      expect(ref.host, 'bitbucket.org');
      expect(ref.resource, 'workspace/repo');
      expect(ref.metadata['workspace'], 'workspace');
      expect(ref.metadata['repo'], 'repo');
    });

    test('parseUrl supports bitbucket cloud ssh URLs', () {
      final BitbucketAdapter adapter = BitbucketAdapter();

      final ProviderRef ref = adapter.parseUrl('git@bitbucket.org:workspace/repo.git');

      expect(ref.host, 'bitbucket.org');
      expect(ref.resource, 'workspace/repo');
    });

    test('parseUrl rejects non-bitbucket-cloud hosts', () {
      final BitbucketAdapter adapter = BitbucketAdapter();

      expect(
        () => adapter.parseUrl('https://bb.internal.local/workspace/repo'),
        throwsArgumentError,
      );
    });

    test('parseUrl rejects empty and invalid repository paths', () {
      final BitbucketAdapter adapter = BitbucketAdapter();

      expect(() => adapter.parseUrl('   '), throwsArgumentError);
      expect(() => adapter.parseUrl('https://bitbucket.org/workspace'), throwsArgumentError);
    });

    test('downloadUrl prefers links.download href and falls back to links.self', () {
      final BitbucketAdapter adapter = BitbucketAdapter();

      final String preferred = adapter.downloadUrl(<String, dynamic>{
        'links': <String, dynamic>{
          'download': <String, dynamic>{'href': 'https://cdn.example.com/file.tgz'},
          'self': <String, dynamic>{'href': 'https://api.example.com/file.tgz'},
        },
      });
      final String fallback = adapter.downloadUrl(<String, dynamic>{
        'links': <String, dynamic>{
          'download': <String, dynamic>{},
          'self': <String, dynamic>{'href': 'https://api.example.com/file.tgz'},
        },
      });

      expect(preferred, 'https://cdn.example.com/file.tgz');
      expect(fallback, 'https://api.example.com/file.tgz');
    });

    test('buildReleaseManifest sets stable schema fields', () {
      final BitbucketAdapter adapter = BitbucketAdapter();

      final Map<String, dynamic> manifest = adapter.buildReleaseManifest(
        tag: 'v1.0.0',
        releaseName: '',
        notes: 'my notes',
        uploadedAssets: <Map<String, dynamic>>[
          <String, dynamic>{'name': 'bin.zip', 'url': 'https://downloads.example/bin.zip', 'type': 'other'},
        ],
        missingAssets: const <Map<String, dynamic>>[],
      );

      expect(manifest['version'], 1);
      expect(manifest['tag_name'], 'v1.0.0');
      expect(manifest['release_name'], 'v1.0.0');
      expect((manifest['notes_hash'] ?? '').toString().length, 64);
      expect((manifest['uploaded_assets'] as List<dynamic>), hasLength(1));
      expect((manifest['missing_assets'] as List<dynamic>), isEmpty);
      expect((manifest['updated_at'] ?? '').toString(), matches(RegExp(r'^\d{4}-\d{2}-\d{2}T')));
    });

    test('manifestIsComplete validates structure and missing list', () {
      final BitbucketAdapter adapter = BitbucketAdapter();

      expect(adapter.manifestIsComplete(null), isFalse);
      expect(
        adapter.manifestIsComplete(<String, dynamic>{
          'uploaded_assets': <dynamic>[],
          'missing_assets': <dynamic>[],
        }),
        isTrue,
      );
      expect(
        adapter.manifestIsComplete(<String, dynamic>{
          'uploaded_assets': <dynamic>[],
          'missing_assets': <String>['file1'],
        }),
        isFalse,
      );
      expect(adapter.manifestIsComplete(<String, dynamic>{'uploaded_assets': 'x', 'missing_assets': <dynamic>[]}),
          isFalse);
    });

    test('toCanonicalRelease supports legacy payload shape', () {
      final BitbucketAdapter adapter = BitbucketAdapter();

      final dynamic canonical = adapter.toCanonicalRelease(<String, dynamic>{
        'tag_name': 'v1.0.0',
        'name': 'Release name',
        'message': 'tag notes',
        'target': <String, dynamic>{'hash': 'abc123'},
      });

      expect(canonical.tagName, 'v1.0.0');
      expect(canonical.name, 'Release name');
      expect(canonical.descriptionMarkdown, 'tag notes');
      expect(canonical.commitSha, 'abc123');
      expect(canonical.assets.links, isEmpty);
      expect(canonical.providerMetadata['legacy_no_manifest'], isTrue);
      expect(canonical.providerMetadata['manifest_found'], isFalse);
    });

    test('toCanonicalRelease keeps normalized payload shape', () {
      final BitbucketAdapter adapter = BitbucketAdapter();

      final dynamic canonical = adapter.toCanonicalRelease(<String, dynamic>{
        'tag_name': 'v2.0.0',
        'name': 'Release v2.0.0',
        'description_markdown': 'notes',
        'commit_sha': 'def456',
        'assets': <String, dynamic>{
          'links': <Map<String, dynamic>>[
            <String, dynamic>{
              'name': 'artifact',
              'url': 'https://bitbucket.org/workspace/repo/downloads/a.zip',
              'direct_url': 'https://bitbucket.org/workspace/repo/downloads/a.zip',
              'type': 'other',
            },
          ],
          'sources': <Map<String, dynamic>>[
            <String, dynamic>{
              'name': 'src.zip',
              'url': 'https://bitbucket.org/workspace/repo/src/v2.0.0.zip',
              'format': 'zip',
            },
          ],
        },
        'provider_metadata': <String, dynamic>{
          'legacy_no_manifest': false,
          'manifest_found': true,
        },
      });

      expect(canonical.tagName, 'v2.0.0');
      expect(canonical.name, 'Release v2.0.0');
      expect(canonical.descriptionMarkdown, 'notes');
      expect(canonical.commitSha, 'def456');
      expect(canonical.assets.links, hasLength(1));
      expect(canonical.assets.sources, hasLength(1));
      expect(canonical.providerMetadata['legacy_no_manifest'], isFalse);
      expect(canonical.providerMetadata['manifest_found'], isTrue);
    });

    test('listTargetReleaseTags returns provided fallback tags', () async {
      final BitbucketAdapter adapter = BitbucketAdapter();
      final ProviderRef ref = adapter.parseUrl('https://bitbucket.org/workspace/repo');

      final Set<String> tags = await adapter.listTargetReleaseTags(ref, 'token', <String>{'v1.0.0', 'v2.0.0'});

      expect(tags, <String>{'v1.0.0', 'v2.0.0'});
    });

    test('buildTagUrl points to tag source page', () {
      final BitbucketAdapter adapter = BitbucketAdapter();
      final ProviderRef ref = adapter.parseUrl('https://bitbucket.org/workspace/repo');

      expect(adapter.buildTagUrl(ref, 'v1.0.0'), 'https://bitbucket.org/workspace/repo/src/v1.0.0');
    });

    test('buildReleaseManifest uses tag name as release name when name is empty', () {
      final BitbucketAdapter adapter = BitbucketAdapter();

      final Map<String, dynamic> manifest = adapter.buildReleaseManifest(
        tag: 'v2.0.0',
        releaseName: '',
        notes: 'notes',
        uploadedAssets: <Map<String, dynamic>>[],
        missingAssets: const <Map<String, dynamic>>[],
      );

      expect(manifest['release_name'], 'v2.0.0');
    });

    test('buildReleaseManifest preserves explicit release name', () {
      final BitbucketAdapter adapter = BitbucketAdapter();

      final Map<String, dynamic> manifest = adapter.buildReleaseManifest(
        tag: 'v2.0.0',
        releaseName: 'My Release',
        notes: 'notes',
        uploadedAssets: <Map<String, dynamic>>[],
        missingAssets: const <Map<String, dynamic>>[],
      );

      expect(manifest['release_name'], 'My Release');
    });

    test('manifestIsComplete returns false for missing keys', () {
      final BitbucketAdapter adapter = BitbucketAdapter();

      expect(adapter.manifestIsComplete(<String, dynamic>{}), isFalse);
      expect(adapter.manifestIsComplete(<String, dynamic>{'uploaded_assets': <dynamic>[]}), isFalse);
    });

    test('downloadUrl returns empty string when both links are missing', () {
      final BitbucketAdapter adapter = BitbucketAdapter();

      final String url = adapter.downloadUrl(<String, dynamic>{
        'links': <String, dynamic>{
          'download': <String, dynamic>{},
          'self': <String, dynamic>{},
        },
      });

      expect(url, '');
    });

    test('parseUrl supports URL without .git suffix', () {
      final BitbucketAdapter adapter = BitbucketAdapter();

      final ProviderRef ref = adapter.parseUrl('https://bitbucket.org/workspace/repo');

      expect(ref.resource, 'workspace/repo');
      expect(ref.metadata['workspace'], 'workspace');
      expect(ref.metadata['repo'], 'repo');
    });

    test('readReleaseManifest returns null when manifest download is missing a URL', () async {
      final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(
        jsonResponse: <String, dynamic>{
          'values': <dynamic>[
            <String, dynamic>{
              'name': '.gfrm-release-v1.0.0.json',
              'links': <String, dynamic>{
                'download': <String, dynamic>{},
                'self': <String, dynamic>{},
              },
            },
          ],
          'next': '',
        },
      );
      final BitbucketAdapter adapter = BitbucketAdapter(http: stub);
      final ProviderRef ref = adapter.parseUrl('https://bitbucket.org/workspace/repo');

      final Map<String, dynamic>? manifest = await adapter.readReleaseManifest(ref, 'token', 'v1.0.0');
      expect(manifest, isNull);
    });

    test('readReleaseManifest returns parsed payload when manifest exists', () async {
      final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(
        jsonResponses: <dynamic>[
          <String, dynamic>{
            'values': <dynamic>[
              <String, dynamic>{
                'name': '.gfrm-release-v1.0.0.json',
                'links': <String, dynamic>{
                  'download': <String, dynamic>{'href': 'https://downloads.example/manifest.json'},
                },
              },
            ],
            'next': '',
          },
          <String, dynamic>{
            'release_name': 'Release v1.0.0',
            'uploaded_assets': <dynamic>[],
            'missing_assets': <dynamic>[]
          },
        ],
      );
      final BitbucketAdapter adapter = BitbucketAdapter(http: stub);
      final ProviderRef ref = adapter.parseUrl('https://bitbucket.org/workspace/repo');

      final Map<String, dynamic>? manifest = await adapter.readReleaseManifest(ref, 'token', 'v1.0.0');
      expect(manifest, isNotNull);
      expect(manifest!['release_name'], 'Release v1.0.0');
    });

    test('readReleaseManifest rethrows AuthenticationError from manifest fetch', () async {
      final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(
        jsonResponses: <dynamic>[
          <String, dynamic>{
            'values': <dynamic>[
              <String, dynamic>{
                'name': '.gfrm-release-v1.0.0.json',
                'links': <String, dynamic>{
                  'download': <String, dynamic>{'href': 'https://downloads.example/manifest.json'},
                },
              },
            ],
            'next': '',
          },
          AuthenticationError('denied'),
        ],
      );
      final BitbucketAdapter adapter = BitbucketAdapter(http: stub);
      final ProviderRef ref = adapter.parseUrl('https://bitbucket.org/workspace/repo');

      await expectLater(
        adapter.readReleaseManifest(ref, 'token', 'v1.0.0'),
        throwsA(isA<AuthenticationError>()),
      );
    });

    test('uploadDownload returns response payload on success', () async {
      final Directory temp = createTempDir('gfrm-bb-upload-');
      final File payload = File('${temp.path}/artifact.zip')..writeAsStringSync('zip');
      final _QueueDio dio = _QueueDio(
        postResults: <Response<dynamic>>[
          _response(
            'https://api.bitbucket.org/2.0/repositories/workspace/repo/downloads',
            201,
            data: <String, dynamic>{
              'name': 'artifact.zip',
              'links': <String, dynamic>{
                'download': <String, dynamic>{'href': 'https://downloads.example/artifact.zip'},
              },
            },
          ),
        ],
      );
      final BitbucketAdapter adapter = BitbucketAdapter(dio: dio);
      final ProviderRef ref = adapter.parseUrl('https://bitbucket.org/workspace/repo');

      final Map<String, dynamic> uploaded = await adapter.uploadDownload(ref, 'token', payload.path);
      expect(uploaded['name'], 'artifact.zip');
    });

    test('uploadDownload throws AuthenticationError for forbidden status', () async {
      final Directory temp = createTempDir('gfrm-bb-upload-auth-');
      final File payload = File('${temp.path}/artifact.zip')..writeAsStringSync('zip');
      final _QueueDio dio = _QueueDio(
        postResults: <Response<dynamic>>[
          _response('https://api.bitbucket.org/2.0/repositories/workspace/repo/downloads', 403, data: 'denied'),
        ],
      );
      final BitbucketAdapter adapter = BitbucketAdapter(dio: dio);
      final ProviderRef ref = adapter.parseUrl('https://bitbucket.org/workspace/repo');

      await expectLater(
        adapter.uploadDownload(ref, 'token', payload.path),
        throwsA(isA<AuthenticationError>()),
      );
    });

    test('uploadDownload throws HttpRequestError when payload is invalid', () async {
      final Directory temp = createTempDir('gfrm-bb-upload-invalid-');
      final File payload = File('${temp.path}/artifact.zip')..writeAsStringSync('zip');
      final _QueueDio dio = _QueueDio(
        postResults: <Response<dynamic>>[
          _response('https://api.bitbucket.org/2.0/repositories/workspace/repo/downloads', 201, data: 'not-json'),
        ],
      );
      final BitbucketAdapter adapter = BitbucketAdapter(dio: dio);
      final ProviderRef ref = adapter.parseUrl('https://bitbucket.org/workspace/repo');

      await expectLater(
        adapter.uploadDownload(ref, 'token', payload.path),
        throwsA(isA<HttpRequestError>()),
      );
    });

    test('uploadDownload throws HttpRequestError for server errors', () async {
      final Directory temp = createTempDir('gfrm-bb-upload-server-');
      final File payload = File('${temp.path}/artifact.zip')..writeAsStringSync('zip');
      final _QueueDio dio = _QueueDio(
        postResults: <Response<dynamic>>[
          _response('https://api.bitbucket.org/2.0/repositories/workspace/repo/downloads', 500, data: 'boom'),
        ],
      );
      final BitbucketAdapter adapter = BitbucketAdapter(dio: dio);
      final ProviderRef ref = adapter.parseUrl('https://bitbucket.org/workspace/repo');

      await expectLater(
        adapter.uploadDownload(ref, 'token', payload.path),
        throwsA(isA<HttpRequestError>()),
      );
    });

    test('replaceDownload deletes existing item before uploading replacement', () async {
      final Directory temp = createTempDir('gfrm-bb-replace-');
      final File payload = File('${temp.path}/artifact.zip')..writeAsStringSync('zip');
      final ScriptedHttpClientHelper http = ScriptedHttpClientHelper(
        jsonResponses: <dynamic>[
          <String, dynamic>{
            'values': <dynamic>[
              <String, dynamic>{
                'name': 'artifact.zip',
                'links': <String, dynamic>{
                  'download': <String, dynamic>{'href': 'https://downloads.example/artifact.zip'},
                },
              },
            ],
            'next': '',
          },
          <String, dynamic>{},
        ],
      );
      final _QueueDio dio = _QueueDio(
        postResults: <Response<dynamic>>[
          _response(
            'https://api.bitbucket.org/2.0/repositories/workspace/repo/downloads',
            201,
            data: <String, dynamic>{
              'name': 'artifact.zip',
              'links': <String, dynamic>{
                'download': <String, dynamic>{'href': 'https://downloads.example/new-artifact.zip'},
              },
            },
          ),
        ],
      );
      final BitbucketAdapter adapter = BitbucketAdapter(http: http, dio: dio);
      final ProviderRef ref = adapter.parseUrl('https://bitbucket.org/workspace/repo');

      final Map<String, dynamic> replaced = await adapter.replaceDownload(ref, 'token', payload.path);
      expect(replaced['name'], 'artifact.zip');
    });

    test('uploadFile throws when upload response has no downloadable URL', () async {
      final Directory temp = createTempDir('gfrm-bb-upload-file-');
      final File payload = File('${temp.path}/artifact.zip')..writeAsStringSync('zip');
      final ScriptedHttpClientHelper http = ScriptedHttpClientHelper(jsonResponses: <dynamic>[
        <String, dynamic>{'values': <dynamic>[], 'next': ''},
      ]);
      final _QueueDio dio = _QueueDio(
        postResults: <Response<dynamic>>[
          _response(
            'https://api.bitbucket.org/2.0/repositories/workspace/repo/downloads',
            201,
            data: <String, dynamic>{'name': 'artifact.zip', 'links': <String, dynamic>{}},
          ),
        ],
      );
      final BitbucketAdapter adapter = BitbucketAdapter(http: http, dio: dio);
      final ProviderRef ref = adapter.parseUrl('https://bitbucket.org/workspace/repo');

      await expectLater(
        adapter.uploadFile(ref, 'token', payload.path),
        throwsA(isA<HttpRequestError>()),
      );
    });

    test('createOrUpdateRelease throws when tag sha is missing', () async {
      final ScriptedHttpClientHelper stub =
          ScriptedHttpClientHelper(jsonResponse: <String, dynamic>{'target': <String, dynamic>{}});
      final BitbucketAdapter adapter = BitbucketAdapter(http: stub);
      final ProviderRef ref = adapter.parseUrl('https://bitbucket.org/workspace/repo');

      await expectLater(
        adapter.createOrUpdateRelease(ref, 'token', 'v1.0.0', 'Release', 'notes', const <Map<String, dynamic>>[]),
        throwsA(isA<HttpRequestError>()),
      );
    });

    test('writeReleaseManifest uploads a generated manifest file', () async {
      final ScriptedHttpClientHelper http = ScriptedHttpClientHelper(
        jsonResponses: <dynamic>[
          <String, dynamic>{'values': <dynamic>[], 'next': ''},
        ],
      );
      final _QueueDio dio = _QueueDio(
        postResults: <Response<dynamic>>[
          _response(
            'https://api.bitbucket.org/2.0/repositories/workspace/repo/downloads',
            201,
            data: <String, dynamic>{
              'name': '.gfrm-release-v1.0.0.json',
              'links': <String, dynamic>{
                'download': <String, dynamic>{'href': 'https://downloads.example/manifest.json'},
              },
            },
          ),
        ],
      );
      final BitbucketAdapter adapter = BitbucketAdapter(http: http, dio: dio);
      final ProviderRef ref = adapter.parseUrl('https://bitbucket.org/workspace/repo');

      await expectLater(
        adapter.writeReleaseManifest(
          ref,
          'token',
          'v1.0.0',
          <String, dynamic>{
            'release_name': 'Release v1.0.0',
            'uploaded_assets': <dynamic>[],
            'missing_assets': <dynamic>[]
          },
        ),
        completes,
      );
    });

    test('createOrUpdateRelease creates synthetic release manifest with valid links only', () async {
      final ScriptedHttpClientHelper http = ScriptedHttpClientHelper(
        jsonResponses: <dynamic>[
          <String, dynamic>{
            'target': <String, dynamic>{'hash': 'abc123'}
          },
          <String, dynamic>{},
          <String, dynamic>{'values': <dynamic>[], 'next': ''},
        ],
      );
      final _QueueDio dio = _QueueDio(
        postResults: <Response<dynamic>>[
          _response(
            'https://api.bitbucket.org/2.0/repositories/workspace/repo/downloads',
            201,
            data: <String, dynamic>{
              'name': '.gfrm-release-v1.0.0.json',
              'links': <String, dynamic>{
                'download': <String, dynamic>{'href': 'https://downloads.example/manifest.json'},
              },
            },
          ),
        ],
      );
      final BitbucketAdapter adapter = BitbucketAdapter(http: http, dio: dio);
      final ProviderRef ref = adapter.parseUrl('https://bitbucket.org/workspace/repo');

      await expectLater(
        adapter.createOrUpdateRelease(
          ref,
          'token',
          'v1.0.0',
          'Release v1.0.0',
          'notes',
          <Map<String, dynamic>>[
            <String, dynamic>{
              'name': 'artifact.zip',
              'url': 'https://downloads.example/artifact.zip',
              'type': 'binary'
            },
            <String, dynamic>{'name': '', 'url': 'https://downloads.example/ignored.zip'},
            <String, dynamic>{'name': 'missing-url', 'url': ''},
          ],
        ),
        completes,
      );
    });

    test('uploadFile returns downloadable URL on success', () async {
      final Directory temp = createTempDir('gfrm-bb-upload-file-success-');
      final File payload = File('${temp.path}/artifact.zip')..writeAsStringSync('zip');
      final ScriptedHttpClientHelper http = ScriptedHttpClientHelper(
        jsonResponses: <dynamic>[
          <String, dynamic>{'values': <dynamic>[], 'next': ''},
        ],
      );
      final _QueueDio dio = _QueueDio(
        postResults: <Response<dynamic>>[
          _response(
            'https://api.bitbucket.org/2.0/repositories/workspace/repo/downloads',
            201,
            data: <String, dynamic>{
              'name': 'artifact.zip',
              'links': <String, dynamic>{
                'download': <String, dynamic>{'href': 'https://downloads.example/artifact.zip'},
              },
            },
          ),
        ],
      );
      final BitbucketAdapter adapter = BitbucketAdapter(http: http, dio: dio);
      final ProviderRef ref = adapter.parseUrl('https://bitbucket.org/workspace/repo');

      final String uploadedUrl = await adapter.uploadFile(ref, 'token', payload.path);
      expect(uploadedUrl, 'https://downloads.example/artifact.zip');
    });

    test('listReleases hydrates manifest-backed synthetic releases', () async {
      final ScriptedHttpClientHelper http = ScriptedHttpClientHelper(
        jsonResponses: <dynamic>[
          <String, dynamic>{
            'values': <dynamic>[
              <String, dynamic>{
                'name': 'v1.0.0',
                'target': <String, dynamic>{'hash': 'abc123'},
                'message': 'notes'
              },
              <String, dynamic>{
                'name': '',
                'target': <String, dynamic>{'hash': 'ignored'}
              },
            ],
            'next': '',
          },
          <String, dynamic>{
            'values': <dynamic>[
              <String, dynamic>{
                'name': '.gfrm-release-v1.0.0.json',
                'links': <String, dynamic>{
                  'download': <String, dynamic>{'href': 'https://downloads.example/manifest.json'},
                },
              },
              <String, dynamic>{'name': '', 'links': <String, dynamic>{}},
            ],
            'next': '',
          },
          <String, dynamic>{
            'release_name': 'Release v1.0.0',
            'uploaded_assets': <dynamic>[
              <String, dynamic>{
                'name': 'artifact.zip',
                'url': 'https://downloads.example/artifact.zip',
                'type': 'other'
              },
              <String, dynamic>{'name': '', 'url': 'https://downloads.example/ignored.zip'},
            ],
            'missing_assets': <dynamic>[],
          },
        ],
      );
      final BitbucketAdapter adapter = BitbucketAdapter(http: http);
      final ProviderRef ref = adapter.parseUrl('https://bitbucket.org/workspace/repo');

      final List<Map<String, dynamic>> releases = await adapter.listReleases(ref, 'token');

      expect(releases, hasLength(1));
      expect(releases.first['tag_name'], 'v1.0.0');
      expect(releases.first['name'], 'Release v1.0.0');
      expect(((releases.first['assets'] as Map<String, dynamic>)['links'] as List<dynamic>), hasLength(1));
    });

    test('releaseByTag returns matching synthetic release row', () async {
      final ScriptedHttpClientHelper http = ScriptedHttpClientHelper(
        jsonResponses: <dynamic>[
          <String, dynamic>{
            'values': <dynamic>[
              <String, dynamic>{
                'name': 'v1.0.0',
                'target': <String, dynamic>{'hash': 'abc123'},
                'message': 'notes'
              },
            ],
            'next': '',
          },
          <String, dynamic>{'values': <dynamic>[], 'next': ''},
        ],
      );
      final BitbucketAdapter adapter = BitbucketAdapter(http: http);
      final ProviderRef ref = adapter.parseUrl('https://bitbucket.org/workspace/repo');

      final Map<String, dynamic>? release = await adapter.releaseByTag(ref, 'token', 'v1.0.0');
      expect(release, isNotNull);
      expect(release!['tag_name'], 'v1.0.0');
      expect(release['provider_metadata'], containsPair('legacy_no_manifest', true));
    });

    test('releaseExists delegates to tag existence', () async {
      final ScriptedHttpClientHelper http = ScriptedHttpClientHelper(statusCode: 200);
      final BitbucketAdapter adapter = BitbucketAdapter(http: http);
      final ProviderRef ref = adapter.parseUrl('https://bitbucket.org/workspace/repo');

      expect(await adapter.releaseExists(ref, 'token', 'v1.0.0'), isTrue);
    });

    test('createTagForMigration delegates to createTag using canonical notes', () async {
      final ScriptedHttpClientHelper http = ScriptedHttpClientHelper(jsonResponse: <String, dynamic>{});
      final BitbucketAdapter adapter = BitbucketAdapter(http: http);
      final ProviderRef ref = adapter.parseUrl('https://bitbucket.org/workspace/repo');
      final CanonicalRelease canonical = CanonicalRelease.fromMap(<String, dynamic>{
        'tag_name': 'v1.0.0',
        'name': 'Release v1.0.0',
        'description_markdown': 'notes',
        'commit_sha': 'abc123',
        'assets': <String, dynamic>{'links': <dynamic>[], 'sources': <dynamic>[]},
        'provider_metadata': <String, dynamic>{},
      });

      await expectLater(adapter.createTagForMigration(ref, 'token', 'v1.0.0', 'abc123', canonical), completes);
    });

    test('isReleaseAlreadyProcessed short-circuits for non-terminal statuses', () async {
      final BitbucketAdapter adapter = BitbucketAdapter();
      final ProviderRef ref = adapter.parseUrl('https://bitbucket.org/workspace/repo');

      final bool processed = await adapter.isReleaseAlreadyProcessed(ref, 'token', 'v1.0.0', 'pending', <String>{});
      expect(processed, isFalse);
    });

    test('isReleaseAlreadyProcessed returns true when tag exists and manifest is complete', () async {
      final ScriptedHttpClientHelper http = ScriptedHttpClientHelper(
        statusResponses: <int>[200],
        jsonResponses: <dynamic>[
          <String, dynamic>{
            'values': <dynamic>[
              <String, dynamic>{
                'name': '.gfrm-release-v1.0.0.json',
                'links': <String, dynamic>{
                  'download': <String, dynamic>{'href': 'https://downloads.example/manifest.json'},
                },
              },
            ],
            'next': '',
          },
          <String, dynamic>{'uploaded_assets': <dynamic>[], 'missing_assets': <dynamic>[]},
        ],
      );
      final BitbucketAdapter adapter = BitbucketAdapter(http: http);
      final ProviderRef ref = adapter.parseUrl('https://bitbucket.org/workspace/repo');

      final bool processed = await adapter.isReleaseAlreadyProcessed(ref, 'token', 'v1.0.0', 'created', <String>{});
      expect(processed, isTrue);
    });

    test('existingReleaseInfo reports absent tag as non-existent', () async {
      final ScriptedHttpClientHelper http = ScriptedHttpClientHelper(statusCode: 404);
      final BitbucketAdapter adapter = BitbucketAdapter(http: http);
      final ProviderRef ref = adapter.parseUrl('https://bitbucket.org/workspace/repo');

      final ExistingReleaseInfo info = await adapter.existingReleaseInfo(ref, 'token', 'v1.0.0', 1);
      expect(info.exists, isFalse);
      expect(info.shouldRetry, isFalse);
    });

    test('existingReleaseInfo reports incomplete manifest as retryable', () async {
      final ScriptedHttpClientHelper http = ScriptedHttpClientHelper(
        statusResponses: <int>[200],
        jsonResponses: <dynamic>[
          <String, dynamic>{
            'values': <dynamic>[
              <String, dynamic>{
                'name': '.gfrm-release-v1.0.0.json',
                'links': <String, dynamic>{
                  'download': <String, dynamic>{'href': 'https://downloads.example/manifest.json'},
                },
              },
            ],
            'next': '',
          },
          <String, dynamic>{
            'uploaded_assets': <dynamic>[
              <String, dynamic>{'name': 'artifact.zip', 'url': 'https://downloads.example/artifact.zip'}
            ],
            'missing_assets': <dynamic>[
              <String, dynamic>{'name': 'missing.zip', 'url': ''}
            ],
          },
        ],
      );
      final BitbucketAdapter adapter = BitbucketAdapter(http: http);
      final ProviderRef ref = adapter.parseUrl('https://bitbucket.org/workspace/repo');

      final ExistingReleaseInfo info = await adapter.existingReleaseInfo(ref, 'token', 'v1.0.0', 2);
      expect(info.exists, isTrue);
      expect(info.shouldRetry, isTrue);
    });

    test('publishRelease returns failed when all uploads fail', () async {
      final Directory temp = createTempDir('gfrm-bb-publish-failed-');
      final File notes = File('${temp.path}/notes.md')..writeAsStringSync('notes');
      final File firstAsset = File('${temp.path}/first.zip')..writeAsStringSync('first');
      final File secondAsset = File('${temp.path}/second.zip')..writeAsStringSync('second');
      final ScriptedHttpClientHelper http = ScriptedHttpClientHelper(
        jsonResponses: <dynamic>[
          <String, dynamic>{'values': <dynamic>[], 'next': ''},
          <String, dynamic>{'values': <dynamic>[], 'next': ''},
        ],
      );
      final _QueueDio dio = _QueueDio(
        postResults: <Response<dynamic>>[
          _response('https://api.bitbucket.org/2.0/repositories/workspace/repo/downloads', 500, data: 'fail'),
          _response('https://api.bitbucket.org/2.0/repositories/workspace/repo/downloads', 500, data: 'fail'),
        ],
      );
      final BitbucketAdapter adapter = BitbucketAdapter(http: http, dio: dio);
      final ProviderRef ref = adapter.parseUrl('https://bitbucket.org/workspace/repo');

      final String status = await adapter.publishRelease(
        PublishReleaseInput(
          providerRef: ref,
          token: 'token',
          tag: 'v1.0.0',
          releaseName: 'Release v1.0.0',
          notesFile: notes,
          downloadedFiles: <String>[firstAsset.path, secondAsset.path],
          expectedAssets: 2,
          existingInfo: const ExistingReleaseInfo(exists: false, shouldRetry: false, reason: ''),
        ),
      );

      expect(status, 'failed');
    });

    test('publishRelease writes manifest and tolerates partial upload failures', () async {
      final Directory temp = createTempDir('gfrm-bb-publish-ok-');
      final File notes = File('${temp.path}/notes.md')..writeAsStringSync('notes');
      final File firstAsset = File('${temp.path}/first.zip')..writeAsStringSync('first');
      final File secondAsset = File('${temp.path}/second.zip')..writeAsStringSync('second');
      final ScriptedHttpClientHelper http = ScriptedHttpClientHelper(
        jsonResponses: <dynamic>[
          <String, dynamic>{'values': <dynamic>[], 'next': ''},
          <String, dynamic>{'values': <dynamic>[], 'next': ''},
          <String, dynamic>{'values': <dynamic>[], 'next': ''},
        ],
      );
      final _QueueDio dio = _QueueDio(
        postResults: <Response<dynamic>>[
          _response(
            'https://api.bitbucket.org/2.0/repositories/workspace/repo/downloads',
            201,
            data: <String, dynamic>{
              'name': 'first.zip',
              'links': <String, dynamic>{
                'download': <String, dynamic>{'href': 'https://downloads.example/first.zip'},
              },
            },
          ),
          _response('https://api.bitbucket.org/2.0/repositories/workspace/repo/downloads', 500, data: 'fail'),
          _response(
            'https://api.bitbucket.org/2.0/repositories/workspace/repo/downloads',
            201,
            data: <String, dynamic>{
              'name': '.gfrm-release-v1.0.0.json',
              'links': <String, dynamic>{
                'download': <String, dynamic>{'href': 'https://downloads.example/manifest.json'},
              },
            },
          ),
        ],
      );
      final BitbucketAdapter adapter = BitbucketAdapter(http: http, dio: dio);
      final ProviderRef ref = adapter.parseUrl('https://bitbucket.org/workspace/repo');

      final String status = await adapter.publishRelease(
        PublishReleaseInput(
          providerRef: ref,
          token: 'token',
          tag: 'v1.0.0',
          releaseName: 'Release v1.0.0',
          notesFile: notes,
          downloadedFiles: <String>[firstAsset.path, secondAsset.path],
          expectedAssets: 2,
          existingInfo: const ExistingReleaseInfo(exists: false, shouldRetry: false, reason: ''),
        ),
      );

      expect(status, 'ok');
    });

    test('downloadCanonicalLink and downloadCanonicalSource return false when URL is missing', () async {
      final BitbucketAdapter adapter = BitbucketAdapter();
      final ProviderRef ref = adapter.parseUrl('https://bitbucket.org/workspace/repo');

      final bool linkDownloaded = await adapter.downloadCanonicalLink(
        DownloadLinkInput(
          providerRef: ref,
          token: 'token',
          tag: 'v1.0.0',
          link: CanonicalLink(name: 'artifact', url: '', directUrl: '', type: 'other'),
          outputPath: '/tmp/artifact.zip',
        ),
      );
      final bool sourceDownloaded = await adapter.downloadCanonicalSource(
        DownloadSourceInput(
          providerRef: ref,
          token: 'token',
          tag: 'v1.0.0',
          source: CanonicalSource(name: 'src', url: '', format: 'zip'),
          outputPath: '/tmp/src.zip',
        ),
      );

      expect(linkDownloaded, isFalse);
      expect(sourceDownloaded, isFalse);
    });

    group('HTTP methods (via stub)', () {
      test('listTags returns tag names from paginated response', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(
          jsonResponse: <String, dynamic>{
            'values': <dynamic>[
              <String, dynamic>{'name': 'v1.0.0'},
              <String, dynamic>{'name': 'v2.0.0'},
            ],
            'next': '',
          },
        );
        final BitbucketAdapter adapter = BitbucketAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://bitbucket.org/workspace/repo');

        final List<String> tags = await adapter.listTags(ref, 'token');

        expect(tags, <String>['v1.0.0', 'v2.0.0']);
      });

      test('listTags returns empty list when response is not a Map', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(jsonResponse: null);
        final BitbucketAdapter adapter = BitbucketAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://bitbucket.org/workspace/repo');

        final List<String> tags = await adapter.listTags(ref, 'token');

        expect(tags, isEmpty);
      });

      test('tagExists returns true when status is 200', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(statusCode: 200);
        final BitbucketAdapter adapter = BitbucketAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://bitbucket.org/workspace/repo');

        expect(await adapter.tagExists(ref, 'token', 'v1.0.0'), isTrue);
      });

      test('tagExists returns false when status is 404', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(statusCode: 404);
        final BitbucketAdapter adapter = BitbucketAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://bitbucket.org/workspace/repo');

        expect(await adapter.tagExists(ref, 'token', 'v9.9.9'), isFalse);
      });

      test('tagCommitSha returns hash from target field', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(
          jsonResponse: <String, dynamic>{
            'name': 'v1.0.0',
            'target': <String, dynamic>{'hash': 'abc123def'},
          },
        );
        final BitbucketAdapter adapter = BitbucketAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://bitbucket.org/workspace/repo');

        expect(await adapter.tagCommitSha(ref, 'token', 'v1.0.0'), 'abc123def');
      });

      test('tagCommitSha returns empty string when response is not a Map', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(jsonResponse: null);
        final BitbucketAdapter adapter = BitbucketAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://bitbucket.org/workspace/repo');

        expect(await adapter.tagCommitSha(ref, 'token', 'v1.0.0'), '');
      });

      test('downloadWithAuth delegates to downloadFile', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper();
        final BitbucketAdapter adapter = BitbucketAdapter(http: stub);

        expect(
          await adapter.downloadWithAuth('token', 'https://example.com/file.zip', '/tmp/file.zip'),
          isTrue,
        );
      });

      test('findDownloadByName returns null when no matching item found', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(
          jsonResponse: <String, dynamic>{
            'values': <dynamic>[
              <String, dynamic>{
                'name': 'other-file.zip',
                'links': <String, dynamic>{
                  'self': <String, dynamic>{'href': 'https://example.com/other-file.zip'},
                },
              },
            ],
            'next': '',
          },
        );
        final BitbucketAdapter adapter = BitbucketAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://bitbucket.org/workspace/repo');

        final Map<String, dynamic>? result = await adapter.findDownloadByName(ref, 'token', 'missing.zip');
        expect(result, isNull);
      });

      test('findDownloadByName returns matching item', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(
          jsonResponse: <String, dynamic>{
            'values': <dynamic>[
              <String, dynamic>{
                'name': 'target.zip',
                'links': <String, dynamic>{
                  'self': <String, dynamic>{'href': 'https://example.com/target.zip'},
                },
              },
            ],
            'next': '',
          },
        );
        final BitbucketAdapter adapter = BitbucketAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://bitbucket.org/workspace/repo');

        final Map<String, dynamic>? result = await adapter.findDownloadByName(ref, 'token', 'target.zip');
        expect(result, isNotNull);
        expect(result!['name'], 'target.zip');
      });

      test('listTagsPayload returns raw tag maps', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(
          jsonResponse: <String, dynamic>{
            'values': <dynamic>[
              <String, dynamic>{'name': 'v1.0.0', 'type': 'tag'},
            ],
            'next': '',
          },
        );
        final BitbucketAdapter adapter = BitbucketAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://bitbucket.org/workspace/repo');

        final List<Map<String, dynamic>> payload = await adapter.listTagsPayload(ref, 'token');
        expect(payload, hasLength(1));
        expect(payload.first['name'], 'v1.0.0');
      });

      test('createTag completes without error', () async {
        final ScriptedHttpClientHelper stub =
            ScriptedHttpClientHelper(jsonResponse: <String, dynamic>{'name': 'v1.0.0'});
        final BitbucketAdapter adapter = BitbucketAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://bitbucket.org/workspace/repo');

        await expectLater(adapter.createTag(ref, 'token', 'v1.0.0', 'abc123'), completes);
      });

      test('createTag with message completes without error', () async {
        final ScriptedHttpClientHelper stub =
            ScriptedHttpClientHelper(jsonResponse: <String, dynamic>{'name': 'v1.0.0'});
        final BitbucketAdapter adapter = BitbucketAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://bitbucket.org/workspace/repo');

        await expectLater(
          adapter.createTag(ref, 'token', 'v1.0.0', 'abc123', message: 'Release v1.0.0'),
          completes,
        );
      });

      test('listDownloads returns download items', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(
          jsonResponse: <String, dynamic>{
            'values': <dynamic>[
              <String, dynamic>{
                'name': 'app.zip',
                'links': <String, dynamic>{
                  'self': <String, dynamic>{'href': 'https://example.com/app.zip'},
                },
              },
            ],
            'next': '',
          },
        );
        final BitbucketAdapter adapter = BitbucketAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://bitbucket.org/workspace/repo');

        final List<Map<String, dynamic>> downloads = await adapter.listDownloads(ref, 'token');
        expect(downloads, hasLength(1));
        expect(downloads.first['name'], 'app.zip');
      });

      test('deleteDownload completes without error', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(jsonResponse: null);
        final BitbucketAdapter adapter = BitbucketAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://bitbucket.org/workspace/repo');

        await expectLater(adapter.deleteDownload(ref, 'token', 'app.zip'), completes);
      });

      test('tagCommitSha uses hash from nested target map', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(
          jsonResponse: <String, dynamic>{
            'name': 'v1.0.0',
            'target': <String, dynamic>{'hash': 'feedbeef'},
          },
        );
        final BitbucketAdapter adapter = BitbucketAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://bitbucket.org/workspace/repo');

        expect(await adapter.tagCommitSha(ref, 'token', 'v1.0.0'), 'feedbeef');
      });

      test('listTags paginates across multiple pages', () async {
        final List<Map<String, dynamic>> page1 = List<Map<String, dynamic>>.generate(
          100,
          (int i) => <String, dynamic>{'name': 'v${i + 1}.0.0'},
        );
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(
          jsonResponses: <dynamic>[
            <String, dynamic>{'values': page1, 'next': 'https://api.bitbucket.org/page2'},
            <String, dynamic>{
              'values': <dynamic>[
                <String, dynamic>{'name': 'v101.0.0'}
              ],
              'next': ''
            },
          ],
        );
        final BitbucketAdapter adapter = BitbucketAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://bitbucket.org/workspace/repo');

        final List<String> tags = await adapter.listTags(ref, 'token');
        expect(tags, hasLength(101));
      });

      test('listReleases with no tags returns empty list', () async {
        final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(
          jsonResponses: <dynamic>[
            // listTagsPayload: paginatedValues → tags
            <String, dynamic>{'values': <dynamic>[], 'next': ''},
            // listDownloads: paginatedValues → downloads
            <String, dynamic>{'values': <dynamic>[], 'next': ''},
          ],
        );
        final BitbucketAdapter adapter = BitbucketAdapter(http: stub);
        final ProviderRef ref = adapter.parseUrl('https://bitbucket.org/workspace/repo');

        final List<Map<String, dynamic>> releases = await adapter.listReleases(ref, 'token');
        expect(releases, isEmpty);
      });
    });
  });
}
