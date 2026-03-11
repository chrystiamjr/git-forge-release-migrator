import 'dart:io';

import 'package:gfrm_dart/src/core/adapters/provider_adapter.dart';
import 'package:gfrm_dart/src/core/logging.dart';
import 'package:gfrm_dart/src/core/types/canonical_release.dart';
import 'package:gfrm_dart/src/migrations/release_asset_service.dart';
import 'package:gfrm_dart/src/models/migration_context.dart';
import '../../support/logging.dart';
import '../../support/migration_context_fixture.dart';
import '../../support/provider_fixtures.dart';
import '../../support/temp_dir.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Stub adapters
// ---------------------------------------------------------------------------

final class _StubSourceAdapter extends ProviderAdapter {
  _StubSourceAdapter({this.downloadResult = false, this.supportsSourceFallback = false});

  final bool downloadResult;
  final bool supportsSourceFallback;

  @override
  String get name => 'stub-source';

  @override
  ProviderRef parseUrl(String url) => ProviderRef(
        provider: 'github',
        rawUrl: url,
        baseUrl: 'https://github.com',
        host: 'github.com',
        resource: 'acme/source',
      );

  @override
  CanonicalRelease toCanonicalRelease(Map<String, dynamic> payload) => CanonicalRelease.fromMap(payload);

  @override
  Future<bool> downloadWithAuth(String token, String url, String destination) async {
    if (downloadResult) {
      File(destination).writeAsStringSync('fake-content');
    }
    return downloadResult;
  }

  @override
  bool supportsSourceFallbackTagNotes() => supportsSourceFallback;

  @override
  String buildTagUrl(ProviderRef ref, String tag) => '${ref.baseUrl}/${ref.resource}/releases/tag/$tag';
}

final class _StubTargetAdapter extends ProviderAdapter {
  @override
  String get name => 'stub-target';

  @override
  ProviderRef parseUrl(String url) => ProviderRef(
        provider: 'gitlab',
        rawUrl: url,
        baseUrl: 'https://gitlab.com',
        host: 'gitlab.com',
        resource: 'acme/target',
      );

  @override
  CanonicalRelease toCanonicalRelease(Map<String, dynamic> payload) => CanonicalRelease.fromMap(payload);
}

CanonicalRelease _releaseWithLinks(String tag, List<Map<String, dynamic>> links) {
  return buildCanonicalRelease(tag, descriptionMarkdown: '# $tag', links: links);
}

CanonicalRelease _releaseWithSources(String tag, List<Map<String, dynamic>> sources) {
  return buildCanonicalRelease(tag, descriptionMarkdown: '# $tag', sources: sources);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late ConsoleLogger logger;

  setUp(() {
    logger = createSilentLogger();
  });

  group('ReleaseAssetService', () {
    group('prepareNotesFile', () {
      test('writes description_markdown content to notes file', () async {
        final Directory temp = createTempDir('gfrm-asset-svc-');

        final MigrationContext ctx = buildMigrationContext(temp, _StubSourceAdapter(), _StubTargetAdapter());
        final CanonicalRelease canonical = buildCanonicalRelease('v1.0.0', descriptionMarkdown: '## Release notes');

        final ReleaseAssetService service = ReleaseAssetService(logger: logger);
        final File notesFile = await service.prepareNotesFile(ctx, 'v1.0.0', canonical);

        expect(notesFile.existsSync(), isTrue);
        expect(notesFile.readAsStringSync(), contains('## Release notes'));
      });

      test('appends legacy Bitbucket source note when provider requires it', () async {
        final Directory temp = createTempDir('gfrm-asset-svc-');

        final MigrationContext ctx = buildMigrationContext(temp, _StubSourceAdapter(), _StubTargetAdapter());
        final CanonicalRelease canonical = buildCanonicalRelease(
          'v1.0.0',
          descriptionMarkdown: 'notes',
          providerMetadata: <String, dynamic>{'legacy_no_manifest': true},
        );

        final ReleaseAssetService service = ReleaseAssetService(logger: logger);
        final File notesFile = await service.prepareNotesFile(ctx, 'v1.0.0', canonical);
        final String content = notesFile.readAsStringSync();

        expect(content, contains('Legacy Bitbucket Source Tag'));
        expect(content, contains('v1.0.0'));
      });
    });

    group('downloadAssets', () {
      test('returns empty downloaded list when release has no assets', () async {
        final Directory temp = createTempDir('gfrm-asset-svc-');

        final MigrationContext ctx = buildMigrationContext(temp, _StubSourceAdapter(), _StubTargetAdapter());
        final CanonicalRelease canonical = buildCanonicalRelease('v1.0.0');

        final Directory assetsDir = Directory('${temp.path}/assets')..createSync();
        final ReleaseAssetService service = ReleaseAssetService(logger: logger);
        final DownloadedAssetResult result = await service.downloadAssets(ctx, 'v1.0.0', canonical, assetsDir);

        expect(result.downloaded, isEmpty);
        expect(result.missingLinks, isEmpty);
        expect(result.missingSources, isEmpty);
      });

      test('successful link download adds to downloaded list', () async {
        final Directory temp = createTempDir('gfrm-asset-svc-');

        final MigrationContext ctx =
            buildMigrationContext(temp, _StubSourceAdapter(downloadResult: true), _StubTargetAdapter());
        final CanonicalRelease canonical = _releaseWithLinks('v1.0.0', <Map<String, dynamic>>[
          <String, dynamic>{'name': 'binary.zip', 'url': 'https://example.com/binary.zip', 'direct_url': ''},
        ]);

        final Directory assetsDir = Directory('${temp.path}/assets')..createSync();
        final ReleaseAssetService service = ReleaseAssetService(logger: logger);
        final DownloadedAssetResult result = await service.downloadAssets(ctx, 'v1.0.0', canonical, assetsDir);

        expect(result.downloaded.length, 1);
        expect(result.missingLinks, isEmpty);
      });

      test('failed link download adds to missingLinks', () async {
        final Directory temp = createTempDir('gfrm-asset-svc-');

        final MigrationContext ctx =
            buildMigrationContext(temp, _StubSourceAdapter(downloadResult: false), _StubTargetAdapter());
        final CanonicalRelease canonical = _releaseWithLinks('v1.0.0', <Map<String, dynamic>>[
          <String, dynamic>{'name': 'binary.zip', 'url': 'https://example.com/binary.zip', 'direct_url': ''},
        ]);

        final Directory assetsDir = Directory('${temp.path}/assets')..createSync();
        final ReleaseAssetService service = ReleaseAssetService(logger: logger);
        final DownloadedAssetResult result = await service.downloadAssets(ctx, 'v1.0.0', canonical, assetsDir);

        expect(result.downloaded, isEmpty);
        expect(result.missingLinks.length, 1);
        expect(result.missingLinks.first['name'], 'binary.zip');
      });

      test('failed source without fallback support adds to missingSources', () async {
        final Directory temp = createTempDir('gfrm-asset-svc-');

        final MigrationContext ctx =
            buildMigrationContext(temp, _StubSourceAdapter(downloadResult: false), _StubTargetAdapter());
        final CanonicalRelease canonical = _releaseWithSources('v1.0.0', <Map<String, dynamic>>[
          <String, dynamic>{'format': 'zip', 'url': 'https://example.com/source.zip'},
        ]);

        final Directory assetsDir = Directory('${temp.path}/assets')..createSync();
        final ReleaseAssetService service = ReleaseAssetService(logger: logger);
        final DownloadedAssetResult result = await service.downloadAssets(ctx, 'v1.0.0', canonical, assetsDir);

        expect(result.downloaded, isEmpty);
        expect(result.missingSources.length, 1);
        expect(result.sourceFallbackFormats, isEmpty);
      });

      test('failed source with fallback support adds to sourceFallbackFormats', () async {
        final Directory temp = createTempDir('gfrm-asset-svc-');

        final MigrationContext ctx = buildMigrationContext(
          temp,
          _StubSourceAdapter(downloadResult: false, supportsSourceFallback: true),
          _StubTargetAdapter(),
        );
        final CanonicalRelease canonical = _releaseWithSources('v1.0.0', <Map<String, dynamic>>[
          <String, dynamic>{'format': 'tar.gz', 'url': 'https://example.com/source.tar.gz'},
        ]);

        final Directory assetsDir = Directory('${temp.path}/assets')..createSync();
        final ReleaseAssetService service = ReleaseAssetService(logger: logger);
        final DownloadedAssetResult result = await service.downloadAssets(ctx, 'v1.0.0', canonical, assetsDir);

        expect(result.sourceFallbackFormats, contains('tar.gz'));
        expect(result.missingSources, isEmpty);
      });

      test('deduplicates output filenames when two links have the same name', () async {
        final Directory temp = createTempDir('gfrm-asset-svc-');

        final MigrationContext ctx =
            buildMigrationContext(temp, _StubSourceAdapter(downloadResult: true), _StubTargetAdapter());
        final CanonicalRelease canonical = _releaseWithLinks('v1.0.0', <Map<String, dynamic>>[
          <String, dynamic>{'name': 'file.zip', 'url': 'https://example.com/a.zip', 'direct_url': ''},
          <String, dynamic>{'name': 'file.zip', 'url': 'https://example.com/b.zip', 'direct_url': ''},
        ]);

        final Directory assetsDir = Directory('${temp.path}/assets')..createSync();
        final ReleaseAssetService service = ReleaseAssetService(logger: logger);
        final DownloadedAssetResult result = await service.downloadAssets(ctx, 'v1.0.0', canonical, assetsDir);

        expect(result.downloaded.length, 2);
        // Both paths must be distinct
        expect(result.downloaded.toSet().length, 2);
      });
    });

    group('appendSourceFallbackNotes', () {
      test('appends fallback note when formats are provided', () async {
        final Directory temp = createTempDir('gfrm-asset-svc-');

        final MigrationContext ctx = buildMigrationContext(
          temp,
          _StubSourceAdapter(supportsSourceFallback: true),
          _StubTargetAdapter(),
        );
        final File notesFile = File('${temp.path}/notes.md')..writeAsStringSync('Initial notes');
        final ReleaseAssetService service = ReleaseAssetService(logger: logger);
        await service.appendSourceFallbackNotes(ctx, 'v1.0.0', notesFile, <String>['zip', 'tar.gz', 'zip']);

        final String content = notesFile.readAsStringSync();
        expect(content, contains('Source Archives Fallback'));
        // zip deduplication + sorted: deduped list is 'tar.gz,zip'
        expect(content, contains('tar.gz,zip'));
      });

      test('does not modify notes file when formats list is empty', () async {
        final Directory temp = createTempDir('gfrm-asset-svc-');

        final MigrationContext ctx = buildMigrationContext(temp, _StubSourceAdapter(), _StubTargetAdapter());
        final File notesFile = File('${temp.path}/notes.md')..writeAsStringSync('Initial notes');
        final ReleaseAssetService service = ReleaseAssetService(logger: logger);
        await service.appendSourceFallbackNotes(ctx, 'v1.0.0', notesFile, <String>[]);

        expect(notesFile.readAsStringSync(), 'Initial notes');
      });
    });

    group('appendMissingAssetsNotes', () {
      test('appends missing assets section when links and sources are missing', () async {
        final Directory temp = createTempDir('gfrm-asset-svc-');

        final File notesFile = File('${temp.path}/notes.md')..writeAsStringSync('Notes');
        final ReleaseAssetService service = ReleaseAssetService(logger: logger);
        await service.appendMissingAssetsNotes(
          notesFile,
          <Map<String, String>>[
            <String, String>{'name': 'binary.zip', 'url': 'https://example.com/binary.zip'},
          ],
          <Map<String, String>>[
            <String, String>{'name': 'source.tar.gz', 'url': ''},
          ],
        );

        final String content = notesFile.readAsStringSync();
        expect(content, contains('Missing Assets During Migration'));
        expect(content, contains('binary.zip'));
        expect(content, contains('source.tar.gz'));
      });

      test('does not modify notes file when both lists are empty', () async {
        final Directory temp = createTempDir('gfrm-asset-svc-');

        final File notesFile = File('${temp.path}/notes.md')..writeAsStringSync('Notes');
        final ReleaseAssetService service = ReleaseAssetService(logger: logger);
        await service.appendMissingAssetsNotes(notesFile, <Map<String, String>>[], <Map<String, String>>[]);

        expect(notesFile.readAsStringSync(), 'Notes');
      });
    });
  });
}
