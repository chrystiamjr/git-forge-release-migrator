import 'package:gfrm_dart/src/core/types/canonical_assets.dart';
import 'package:gfrm_dart/src/core/types/canonical_link.dart';
import 'package:gfrm_dart/src/core/types/canonical_release.dart';
import 'package:gfrm_dart/src/core/types/canonical_source.dart';
import 'package:test/test.dart';

void main() {
  group('canonical types', () {
    test('CanonicalRelease.fromMap defaults name to tag', () {
      final CanonicalRelease release = CanonicalRelease.fromMap(<String, dynamic>{
        'tag_name': 'v1.0.0',
        'description_markdown': 'notes',
        'commit_sha': 'abc123',
      });

      expect(release.tagName, 'v1.0.0');
      expect(release.name, 'v1.0.0');
      expect(release.descriptionMarkdown, 'notes');
      expect(release.commitSha, 'abc123');
      expect(release.assets.links, isEmpty);
      expect(release.assets.sources, isEmpty);
    });

    test('CanonicalAssets.fromMap parses links and sources', () {
      final CanonicalAssets assets = CanonicalAssets.fromMap(<String, dynamic>{
        'links': <Map<String, dynamic>>[
          <String, dynamic>{
            'name': 'artifact.zip',
            'url': 'https://example.com/artifact.zip',
            'direct_url': 'https://cdn.example.com/artifact.zip',
            'type': 'package',
          },
        ],
        'sources': <Map<String, dynamic>>[
          <String, dynamic>{
            'name': 'src.tar.gz',
            'url': 'https://example.com/src.tar.gz',
            'format': 'tar.gz',
          },
        ],
      });

      expect(assets.links, hasLength(1));
      expect(assets.sources, hasLength(1));
      expect(assets.links.first.directUrl, 'https://cdn.example.com/artifact.zip');
      expect(assets.sources.first.format, 'tar.gz');
    });

    test('CanonicalLink and CanonicalSource map conversions are stable', () {
      final CanonicalLink link = CanonicalLink(
        name: 'a',
        url: 'https://example.com/a',
        directUrl: 'https://cdn.example.com/a',
        type: 'package',
      );
      final CanonicalSource source = CanonicalSource(
        name: 'src',
        url: 'https://example.com/src.zip',
        format: 'zip',
      );

      expect(CanonicalLink.fromMap(link.toMap()).toMap(), link.toMap());
      expect(CanonicalSource.fromMap(source.toMap()).toMap(), source.toMap());
    });

    test('CanonicalRelease.toMap keeps provider metadata and assets', () {
      final CanonicalRelease release = CanonicalRelease(
        tagName: 'v2.0.0',
        name: 'Release v2.0.0',
        descriptionMarkdown: 'notes',
        commitSha: 'def456',
        assets: CanonicalAssets(
          links: <CanonicalLink>[
            CanonicalLink(name: 'bin', url: 'https://u', directUrl: 'https://d', type: 'package'),
          ],
          sources: <CanonicalSource>[
            CanonicalSource(name: 'src', url: 'https://s', format: 'zip'),
          ],
        ),
        providerMetadata: <String, dynamic>{'legacy_no_manifest': false},
      );

      final Map<String, dynamic> payload = release.toMap();
      expect(payload['tag_name'], 'v2.0.0');
      expect(payload['name'], 'Release v2.0.0');
      expect((payload['assets'] as Map<String, dynamic>)['links'], hasLength(1));
      expect((payload['assets'] as Map<String, dynamic>)['sources'], hasLength(1));
      expect((payload['provider_metadata'] as Map<String, dynamic>)['legacy_no_manifest'], isFalse);
    });
  });
}
