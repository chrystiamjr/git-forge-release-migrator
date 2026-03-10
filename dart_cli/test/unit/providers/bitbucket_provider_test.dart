import 'package:gfrm_dart/src/core/adapters/provider_adapter.dart';
import 'package:gfrm_dart/src/providers/bitbucket.dart';
import 'package:test/test.dart';

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
  });
}
