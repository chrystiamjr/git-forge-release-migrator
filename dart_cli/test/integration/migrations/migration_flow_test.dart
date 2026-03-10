import 'dart:io';

import 'package:gfrm_dart/src/core/adapters/provider_adapter.dart';
import 'package:gfrm_dart/src/core/exceptions/authentication_error.dart';
import 'package:gfrm_dart/src/core/exceptions/migration_phase_error.dart';
import 'package:gfrm_dart/src/core/logging.dart';
import 'package:gfrm_dart/src/core/types/canonical_release.dart';
import 'package:gfrm_dart/src/core/types/phase.dart';
import 'package:gfrm_dart/src/migrations/engine.dart';
import 'package:gfrm_dart/src/models/runtime_options.dart';
import 'package:gfrm_dart/src/providers/registry.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Stub adapters
// ---------------------------------------------------------------------------

/// Source adapter that returns a configurable list of releases.
final class _SourceAdapter extends ProviderAdapter {
  _SourceAdapter({required this.releases});

  final List<Map<String, dynamic>> releases;

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
  Future<List<Map<String, dynamic>>> listReleases(ProviderRef ref, String token) async => releases;

  @override
  Future<String> resolveCommitShaForMigration(
    ProviderRef ref,
    String token,
    String tag,
    CanonicalRelease canonical,
  ) async {
    if (canonical.commitSha.isNotEmpty) {
      return canonical.commitSha;
    }
    return 'default-sha';
  }
}

/// Target adapter with configurable tag/release behavior.
final class _TargetAdapter extends ProviderAdapter {
  _TargetAdapter({
    this.onCreateTag,
    this.onTagExists,
  });

  final Future<void> Function(ProviderRef, String, String, String, CanonicalRelease)? onCreateTag;
  final Future<bool> Function(ProviderRef, String, String)? onTagExists;

  final Set<String> _createdTags = <String>{};

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

  @override
  Future<List<String>> listTags(ProviderRef ref, String token) async => <String>[];

  @override
  Future<bool> tagExists(ProviderRef ref, String token, String tag) async {
    if (onTagExists != null) {
      return onTagExists!(ref, token, tag);
    }
    return _createdTags.contains(tag);
  }

  @override
  Future<void> createTagForMigration(
    ProviderRef ref,
    String token,
    String tag,
    String sha,
    CanonicalRelease canonical,
  ) async {
    if (onCreateTag != null) {
      return onCreateTag!(ref, token, tag, sha, canonical);
    }
    _createdTags.add(tag);
  }

  @override
  Future<bool> releaseExists(ProviderRef ref, String token, String tag) async => false;

  @override
  Future<ExistingReleaseInfo> existingReleaseInfo(
    ProviderRef ref,
    String token,
    String tag,
    int expectedLinkAssets,
  ) async =>
      const ExistingReleaseInfo(exists: false, shouldRetry: false, reason: '');

  @override
  Future<String> publishRelease(PublishReleaseInput input) async => 'created';
}

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

Map<String, dynamic> _release(String tag) => <String, dynamic>{
      'tag_name': tag,
      'name': tag,
      'description_markdown': '# $tag',
      'commit_sha': 'abc123',
      'assets': <String, dynamic>{
        'links': <dynamic>[],
        'sources': <dynamic>[],
      },
    };

RuntimeOptions _buildOptions(String workdirPath, String logPath) {
  return RuntimeOptions(
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
    workdir: workdirPath,
    logFile: logPath,
    loadSession: false,
    saveSession: false,
    resumeSession: false,
    sessionFile: '',
    sessionTokenMode: 'env',
    sessionSourceTokenEnv: defaultSourceTokenEnv,
    sessionTargetTokenEnv: defaultTargetTokenEnv,
    settingsProfile: '',
    downloadWorkers: 4,
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
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('MigrationEngine (integration)', () {
    test('completes full migration with one release and no failures', () async {
      final Directory temp = Directory.systemTemp.createTempSync('gfrm-integration-');
      addTearDown(() => temp.deleteSync(recursive: true));

      final _SourceAdapter source = _SourceAdapter(releases: <Map<String, dynamic>>[_release('v1.0.0')]);
      final _TargetAdapter target = _TargetAdapter();
      final ProviderRegistry registry = ProviderRegistry(<String, ProviderAdapter>{
        'github': source,
        'gitlab': target,
      });
      final MigrationEngine engine = MigrationEngine(
        registry: registry,
        logger: ConsoleLogger(quiet: true, jsonOutput: false),
      );

      final RuntimeOptions options = _buildOptions(
        '${temp.path}/results',
        '${temp.path}/migration.jsonl',
      );

      // Should complete without throwing
      await expectLater(
        engine.run(options, source.parseUrl(options.sourceUrl), target.parseUrl(options.targetUrl)),
        completes,
      );
    });

    test('throws MigrationPhaseError when source has no releases', () async {
      final Directory temp = Directory.systemTemp.createTempSync('gfrm-integration-');
      addTearDown(() => temp.deleteSync(recursive: true));

      final _SourceAdapter source = _SourceAdapter(releases: <Map<String, dynamic>>[]);
      final _TargetAdapter target = _TargetAdapter();
      final ProviderRegistry registry = ProviderRegistry(<String, ProviderAdapter>{
        'github': source,
        'gitlab': target,
      });
      final MigrationEngine engine = MigrationEngine(
        registry: registry,
        logger: ConsoleLogger(quiet: true, jsonOutput: false),
      );

      final RuntimeOptions options = _buildOptions(
        '${temp.path}/results',
        '${temp.path}/migration.jsonl',
      );

      await expectLater(
        engine.run(options, source.parseUrl(options.sourceUrl), target.parseUrl(options.targetUrl)),
        throwsA(isA<MigrationPhaseError>()),
      );
    });

    test('throws MigrationPhaseError when a tag creation fails with generic error', () async {
      final Directory temp = Directory.systemTemp.createTempSync('gfrm-integration-');
      addTearDown(() => temp.deleteSync(recursive: true));

      final _SourceAdapter source = _SourceAdapter(releases: <Map<String, dynamic>>[_release('v1.0.0')]);
      final _TargetAdapter target = _TargetAdapter(
        onCreateTag: (_, __, ___, ____, _____) async => throw Exception('network error'),
      );
      final ProviderRegistry registry = ProviderRegistry(<String, ProviderAdapter>{
        'github': source,
        'gitlab': target,
      });
      final MigrationEngine engine = MigrationEngine(
        registry: registry,
        logger: ConsoleLogger(quiet: true, jsonOutput: false),
      );

      final RuntimeOptions options = _buildOptions(
        '${temp.path}/results',
        '${temp.path}/migration.jsonl',
      );

      await expectLater(
        engine.run(options, source.parseUrl(options.sourceUrl), target.parseUrl(options.targetUrl)),
        throwsA(isA<MigrationPhaseError>()),
      );
    });

    test('propagates AuthenticationError from tag phase without wrapping', () async {
      final Directory temp = Directory.systemTemp.createTempSync('gfrm-integration-');
      addTearDown(() => temp.deleteSync(recursive: true));

      final _SourceAdapter source = _SourceAdapter(releases: <Map<String, dynamic>>[_release('v1.0.0')]);
      final _TargetAdapter target = _TargetAdapter(
        onTagExists: (_, __, ___) async => throw AuthenticationError('401 unauthorized'),
      );
      final ProviderRegistry registry = ProviderRegistry(<String, ProviderAdapter>{
        'github': source,
        'gitlab': target,
      });
      final MigrationEngine engine = MigrationEngine(
        registry: registry,
        logger: ConsoleLogger(quiet: true, jsonOutput: false),
      );

      final RuntimeOptions options = _buildOptions(
        '${temp.path}/results',
        '${temp.path}/migration.jsonl',
      );

      await expectLater(
        engine.run(options, source.parseUrl(options.sourceUrl), target.parseUrl(options.targetUrl)),
        throwsA(isA<AuthenticationError>()),
      );
    });

    test('migrates multiple releases and all are created successfully', () async {
      final Directory temp = Directory.systemTemp.createTempSync('gfrm-integration-');
      addTearDown(() => temp.deleteSync(recursive: true));

      final _SourceAdapter source = _SourceAdapter(releases: <Map<String, dynamic>>[
        _release('v1.0.0'),
        _release('v1.1.0'),
        _release('v1.2.0'),
      ]);
      final _TargetAdapter target = _TargetAdapter();
      final ProviderRegistry registry = ProviderRegistry(<String, ProviderAdapter>{
        'github': source,
        'gitlab': target,
      });
      final MigrationEngine engine = MigrationEngine(
        registry: registry,
        logger: ConsoleLogger(quiet: true, jsonOutput: false),
      );

      final RuntimeOptions options = _buildOptions(
        '${temp.path}/results',
        '${temp.path}/migration.jsonl',
      );

      await expectLater(
        engine.run(options, source.parseUrl(options.sourceUrl), target.parseUrl(options.targetUrl)),
        completes,
      );
    });
  });
}
