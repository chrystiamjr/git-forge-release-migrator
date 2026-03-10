import 'dart:io';

import 'package:gfrm_dart/src/core/adapters/provider_adapter.dart';
import 'package:gfrm_dart/src/core/logging.dart';
import 'package:gfrm_dart/src/core/types/canonical_release.dart';
import 'package:gfrm_dart/src/migrations/release_asset_service.dart';
import 'package:gfrm_dart/src/models/migration_context.dart';
import 'package:gfrm_dart/src/models/runtime_options.dart';
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

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

MigrationContext _buildContext(
  Directory temp,
  ProviderAdapter source,
  ProviderAdapter target, {
  List<Map<String, dynamic>> releases = const <Map<String, dynamic>>[],
}) {
  final ProviderRef sourceRef = source.parseUrl('https://github.com/acme/source');
  final ProviderRef targetRef = target.parseUrl('https://gitlab.com/acme/target');
  final RuntimeOptions options = RuntimeOptions(
    commandName: commandMigrate,
    sourceProvider: 'github',
    sourceUrl: 'https://github.com/acme/source',
    sourceToken: 'src-token',
    targetProvider: 'gitlab',
    targetUrl: 'https://gitlab.com/acme/target',
    targetToken: 'dst-token',
    migrationOrder: 'github-to-gitlab',
    skipTagMigration: false,
    fromTag: '',
    toTag: '',
    dryRun: false,
    nonInteractive: true,
    workdir: temp.path,
    logFile: '${temp.path}/migration.jsonl',
    loadSession: false,
    saveSession: false,
    resumeSession: false,
    sessionFile: '',
    sessionTokenMode: 'env',
    sessionSourceTokenEnv: defaultSourceTokenEnv,
    sessionTargetTokenEnv: defaultTargetTokenEnv,
    settingsProfile: '',
    downloadWorkers: 2,
    releaseWorkers: 1,
    checkpointFile: '',
    tagsFile: '',
    noBanner: true,
    quiet: true,
    jsonOutput: false,
    progressBar: false,
    demoMode: false,
    demoReleases: 5,
    demoSleepSeconds: 1.0,
  );

  return MigrationContext(
    sourceRef: sourceRef,
    targetRef: targetRef,
    source: source,
    target: target,
    options: options,
    logPath: '${temp.path}/migration.jsonl',
    workdir: temp,
    checkpointPath: '${temp.path}/checkpoint.jsonl',
    checkpointSignature: 'test-sig',
    checkpointState: <String, String>{},
    selectedTags: <String>[],
    targetTags: <String>{},
    targetReleaseTags: <String>{},
    failedTags: <String>{},
    releases: List<Map<String, dynamic>>.from(releases),
  );
}

CanonicalRelease _releaseWithLinks(String tag, List<Map<String, dynamic>> links) {
  return CanonicalRelease.fromMap(<String, dynamic>{
    'tag_name': tag,
    'name': tag,
    'description_markdown': '# $tag',
    'commit_sha': 'abc123',
    'assets': <String, dynamic>{
      'links': links,
      'sources': <dynamic>[],
    },
  });
}

CanonicalRelease _releaseWithSources(String tag, List<Map<String, dynamic>> sources) {
  return CanonicalRelease.fromMap(<String, dynamic>{
    'tag_name': tag,
    'name': tag,
    'description_markdown': '# $tag',
    'commit_sha': 'abc123',
    'assets': <String, dynamic>{
      'links': <dynamic>[],
      'sources': sources,
    },
  });
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late ConsoleLogger logger;

  setUp(() {
    logger = ConsoleLogger(quiet: true, jsonOutput: false);
  });

  group('ReleaseAssetService', () {
    group('prepareNotesFile', () {
      test('writes description_markdown content to notes file', () async {
        final Directory temp = Directory.systemTemp.createTempSync('gfrm-asset-svc-');
        addTearDown(() => temp.deleteSync(recursive: true));

        final MigrationContext ctx = _buildContext(temp, _StubSourceAdapter(), _StubTargetAdapter());
        final CanonicalRelease canonical = CanonicalRelease.fromMap(<String, dynamic>{
          'tag_name': 'v1.0.0',
          'description_markdown': '## Release notes',
          'assets': <String, dynamic>{'links': <dynamic>[], 'sources': <dynamic>[]},
        });

        final ReleaseAssetService service = ReleaseAssetService(logger: logger);
        final File notesFile = await service.prepareNotesFile(ctx, 'v1.0.0', canonical);

        expect(notesFile.existsSync(), isTrue);
        expect(notesFile.readAsStringSync(), contains('## Release notes'));
      });

      test('appends legacy Bitbucket source note when provider requires it', () async {
        final Directory temp = Directory.systemTemp.createTempSync('gfrm-asset-svc-');
        addTearDown(() => temp.deleteSync(recursive: true));

        final MigrationContext ctx = _buildContext(temp, _StubSourceAdapter(), _StubTargetAdapter());
        final CanonicalRelease canonical = CanonicalRelease.fromMap(<String, dynamic>{
          'tag_name': 'v1.0.0',
          'description_markdown': 'notes',
          'provider_metadata': <String, dynamic>{'legacy_no_manifest': true},
          'assets': <String, dynamic>{'links': <dynamic>[], 'sources': <dynamic>[]},
        });

        final ReleaseAssetService service = ReleaseAssetService(logger: logger);
        final File notesFile = await service.prepareNotesFile(ctx, 'v1.0.0', canonical);
        final String content = notesFile.readAsStringSync();

        expect(content, contains('Legacy Bitbucket Source Tag'));
        expect(content, contains('v1.0.0'));
      });
    });

    group('downloadAssets', () {
      test('returns empty downloaded list when release has no assets', () async {
        final Directory temp = Directory.systemTemp.createTempSync('gfrm-asset-svc-');
        addTearDown(() => temp.deleteSync(recursive: true));

        final MigrationContext ctx = _buildContext(temp, _StubSourceAdapter(), _StubTargetAdapter());
        final CanonicalRelease canonical = CanonicalRelease.fromMap(<String, dynamic>{
          'tag_name': 'v1.0.0',
          'assets': <String, dynamic>{'links': <dynamic>[], 'sources': <dynamic>[]},
        });

        final Directory assetsDir = Directory('${temp.path}/assets')..createSync();
        final ReleaseAssetService service = ReleaseAssetService(logger: logger);
        final DownloadedAssetResult result = await service.downloadAssets(ctx, 'v1.0.0', canonical, assetsDir);

        expect(result.downloaded, isEmpty);
        expect(result.missingLinks, isEmpty);
        expect(result.missingSources, isEmpty);
      });

      test('successful link download adds to downloaded list', () async {
        final Directory temp = Directory.systemTemp.createTempSync('gfrm-asset-svc-');
        addTearDown(() => temp.deleteSync(recursive: true));

        final MigrationContext ctx =
            _buildContext(temp, _StubSourceAdapter(downloadResult: true), _StubTargetAdapter());
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
        final Directory temp = Directory.systemTemp.createTempSync('gfrm-asset-svc-');
        addTearDown(() => temp.deleteSync(recursive: true));

        final MigrationContext ctx =
            _buildContext(temp, _StubSourceAdapter(downloadResult: false), _StubTargetAdapter());
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
        final Directory temp = Directory.systemTemp.createTempSync('gfrm-asset-svc-');
        addTearDown(() => temp.deleteSync(recursive: true));

        final MigrationContext ctx =
            _buildContext(temp, _StubSourceAdapter(downloadResult: false), _StubTargetAdapter());
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
        final Directory temp = Directory.systemTemp.createTempSync('gfrm-asset-svc-');
        addTearDown(() => temp.deleteSync(recursive: true));

        final MigrationContext ctx = _buildContext(
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
        final Directory temp = Directory.systemTemp.createTempSync('gfrm-asset-svc-');
        addTearDown(() => temp.deleteSync(recursive: true));

        final MigrationContext ctx =
            _buildContext(temp, _StubSourceAdapter(downloadResult: true), _StubTargetAdapter());
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
        final Directory temp = Directory.systemTemp.createTempSync('gfrm-asset-svc-');
        addTearDown(() => temp.deleteSync(recursive: true));

        final MigrationContext ctx = _buildContext(
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
        final Directory temp = Directory.systemTemp.createTempSync('gfrm-asset-svc-');
        addTearDown(() => temp.deleteSync(recursive: true));

        final MigrationContext ctx = _buildContext(temp, _StubSourceAdapter(), _StubTargetAdapter());
        final File notesFile = File('${temp.path}/notes.md')..writeAsStringSync('Initial notes');
        final ReleaseAssetService service = ReleaseAssetService(logger: logger);
        await service.appendSourceFallbackNotes(ctx, 'v1.0.0', notesFile, <String>[]);

        expect(notesFile.readAsStringSync(), 'Initial notes');
      });
    });

    group('appendMissingAssetsNotes', () {
      test('appends missing assets section when links and sources are missing', () async {
        final Directory temp = Directory.systemTemp.createTempSync('gfrm-asset-svc-');
        addTearDown(() => temp.deleteSync(recursive: true));

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
        final Directory temp = Directory.systemTemp.createTempSync('gfrm-asset-svc-');
        addTearDown(() => temp.deleteSync(recursive: true));

        final File notesFile = File('${temp.path}/notes.md')..writeAsStringSync('Notes');
        final ReleaseAssetService service = ReleaseAssetService(logger: logger);
        await service.appendMissingAssetsNotes(notesFile, <Map<String, String>>[], <Map<String, String>>[]);

        expect(notesFile.readAsStringSync(), 'Notes');
      });
    });
  });
}
