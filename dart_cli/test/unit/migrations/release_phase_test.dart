import 'dart:io';

import 'package:gfrm_dart/src/core/adapters/provider_adapter.dart';
import 'package:gfrm_dart/src/core/exceptions/authentication_error.dart';
import 'package:gfrm_dart/src/core/logging.dart';
import 'package:gfrm_dart/src/core/types/canonical_release.dart';
import 'package:gfrm_dart/src/core/types/phase.dart';
import 'package:gfrm_dart/src/migrations/release_phase.dart';
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
}

final class _StubTargetAdapter extends ProviderAdapter {
  _StubTargetAdapter({
    this.tagExistsResult = true,
    this.releaseExistsResult = false,
    this.publishResult = 'created',
    this.onPublish,
    this.existingReleaseOverride,
  });

  final bool tagExistsResult;
  final bool releaseExistsResult;
  final String publishResult;
  final Future<String> Function(PublishReleaseInput input)? onPublish;
  final ExistingReleaseInfo? existingReleaseOverride;

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
  Future<bool> tagExists(ProviderRef ref, String token, String tag) async => tagExistsResult;

  @override
  Future<bool> releaseExists(ProviderRef ref, String token, String tag) async => releaseExistsResult;

  @override
  Future<ExistingReleaseInfo> existingReleaseInfo(
    ProviderRef ref,
    String token,
    String tag,
    int expectedLinkAssets,
  ) async {
    if (existingReleaseOverride != null) {
      return existingReleaseOverride!;
    }
    return const ExistingReleaseInfo(exists: false, shouldRetry: false, reason: '');
  }

  @override
  Future<String> publishRelease(PublishReleaseInput input) async {
    if (onPublish != null) {
      return onPublish!(input);
    }
    return publishResult;
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late ConsoleLogger logger;

  setUp(() {
    logger = createSilentLogger();
  });

  group('ReleasePhaseRunner', () {
    test('returns empty counts when selectedTags is empty', () async {
      final Directory temp = createTempDir('gfrm-rel-phase-');

      final MigrationContext ctx = buildMigrationContext(temp, _StubSourceAdapter(), _StubTargetAdapter());

      final ReleaseMigrationCounts counts = await ReleasePhaseRunner(logger: logger).run(ctx);

      expect(counts.created, 0);
      expect(counts.skipped, 0);
      expect(counts.failed, 0);
    });

    test('creates release with no assets successfully', () async {
      final Directory temp = createTempDir('gfrm-rel-phase-');

      bool publishCalled = false;
      final _StubTargetAdapter target = _StubTargetAdapter(
        tagExistsResult: true,
        onPublish: (PublishReleaseInput input) async {
          publishCalled = true;
          return 'created';
        },
      );
      final MigrationContext ctx = buildMigrationContext(
        temp,
        _StubSourceAdapter(),
        target,
        selectedTags: <String>['v1.0.0'],
        targetTags: <String>{'v1.0.0'}, // tag already exists in target
        releases: <Map<String, dynamic>>[buildMinimalReleasePayload('v1.0.0')],
      );

      final ReleaseMigrationCounts counts = await ReleasePhaseRunner(logger: logger).run(ctx);

      expect(counts.created, 1);
      expect(publishCalled, isTrue);
    });

    test('skips release that is already processed via checkpoint', () async {
      final Directory temp = createTempDir('gfrm-rel-phase-');

      bool publishCalled = false;
      final _StubTargetAdapter target = _StubTargetAdapter(
        releaseExistsResult: true, // release exists on remote
        onPublish: (PublishReleaseInput _) async {
          publishCalled = true;
          return 'created';
        },
      );
      final MigrationContext ctx = buildMigrationContext(
        temp,
        _StubSourceAdapter(),
        target,
        selectedTags: <String>['v1.0.0'],
        targetTags: <String>{'v1.0.0'},
        checkpointState: <String, String>{'release:v1.0.0': 'created'}, // terminal status
        releases: <Map<String, dynamic>>[buildMinimalReleasePayload('v1.0.0')],
      );

      final ReleaseMigrationCounts counts = await ReleasePhaseRunner(logger: logger).run(ctx);

      expect(counts.skipped, 1);
      expect(publishCalled, isFalse);
    });

    test('fails release when tag is missing in target after tag phase', () async {
      final Directory temp = createTempDir('gfrm-rel-phase-');

      final _StubTargetAdapter target = _StubTargetAdapter(
        tagExistsResult: false, // tag not on remote
      );
      final MigrationContext ctx = buildMigrationContext(
        temp,
        _StubSourceAdapter(),
        target,
        selectedTags: <String>['v1.0.0'],
        // targetTags is empty — tag never migrated
        releases: <Map<String, dynamic>>[buildMinimalReleasePayload('v1.0.0')],
      );

      final ReleaseMigrationCounts counts = await ReleasePhaseRunner(logger: logger).run(ctx);

      expect(counts.failed, 1);
      expect(ctx.failedTags, contains('v1.0.0'));
    });

    test('dry-run increments wouldCreate without publishing', () async {
      final Directory temp = createTempDir('gfrm-rel-phase-');

      bool publishCalled = false;
      final _StubTargetAdapter target = _StubTargetAdapter(
        tagExistsResult: true,
        onPublish: (PublishReleaseInput _) async {
          publishCalled = true;
          return 'created';
        },
      );
      final MigrationContext ctx = buildMigrationContext(
        temp,
        _StubSourceAdapter(),
        target,
        selectedTags: <String>['v1.0.0'],
        targetTags: <String>{'v1.0.0'},
        releases: <Map<String, dynamic>>[buildMinimalReleasePayload('v1.0.0')],
        dryRun: true,
      );

      final ReleaseMigrationCounts counts = await ReleasePhaseRunner(logger: logger).run(ctx);

      expect(counts.wouldCreate, 1);
      expect(publishCalled, isFalse);
    });

    test('fails release when publishRelease returns "failed"', () async {
      final Directory temp = createTempDir('gfrm-rel-phase-');

      final _StubTargetAdapter target = _StubTargetAdapter(
        tagExistsResult: true,
        publishResult: 'failed',
      );
      final MigrationContext ctx = buildMigrationContext(
        temp,
        _StubSourceAdapter(),
        target,
        selectedTags: <String>['v1.0.0'],
        targetTags: <String>{'v1.0.0'},
        releases: <Map<String, dynamic>>[buildMinimalReleasePayload('v1.0.0')],
      );

      final ReleaseMigrationCounts counts = await ReleasePhaseRunner(logger: logger).run(ctx);

      expect(counts.failed, 1);
      expect(ctx.failedTags, contains('v1.0.0'));
    });

    test('rethrows AuthenticationError from publishRelease', () async {
      final Directory temp = createTempDir('gfrm-rel-phase-');

      final _StubTargetAdapter target = _StubTargetAdapter(
        tagExistsResult: true,
        onPublish: (_) async => throw AuthenticationError('401 from publishRelease'),
      );
      final MigrationContext ctx = buildMigrationContext(
        temp,
        _StubSourceAdapter(),
        target,
        selectedTags: <String>['v1.0.0'],
        targetTags: <String>{'v1.0.0'},
        releases: <Map<String, dynamic>>[buildMinimalReleasePayload('v1.0.0')],
      );

      await expectLater(
        ReleasePhaseRunner(logger: logger).run(ctx),
        throwsA(isA<AuthenticationError>()),
      );
    });

    test('skips release that exists and is complete on remote', () async {
      final Directory temp = createTempDir('gfrm-rel-phase-');

      bool publishCalled = false;
      final _StubTargetAdapter target = _StubTargetAdapter(
        tagExistsResult: true,
        existingReleaseOverride: const ExistingReleaseInfo(exists: true, shouldRetry: false, reason: 'complete'),
        onPublish: (_) async {
          publishCalled = true;
          return 'created';
        },
      );
      final MigrationContext ctx = buildMigrationContext(
        temp,
        _StubSourceAdapter(),
        target,
        selectedTags: <String>['v1.0.0'],
        targetTags: <String>{'v1.0.0'},
        releases: <Map<String, dynamic>>[buildMinimalReleasePayload('v1.0.0')],
      );

      final ReleaseMigrationCounts counts = await ReleasePhaseRunner(logger: logger).run(ctx);

      expect(counts.skipped, 1);
      expect(publishCalled, isFalse);
    });

    test('fails release when payload is missing from releases list', () async {
      final Directory temp = createTempDir('gfrm-rel-phase-');

      final MigrationContext ctx = buildMigrationContext(
        temp,
        _StubSourceAdapter(),
        _StubTargetAdapter(tagExistsResult: true),
        selectedTags: <String>['v1.0.0'],
        targetTags: <String>{'v1.0.0'},
        releases: <Map<String, dynamic>>[], // no release payload for v1.0.0
      );

      final ReleaseMigrationCounts counts = await ReleasePhaseRunner(logger: logger).run(ctx);

      expect(counts.failed, 1);
    });

    test('updates checkpointState after successful release creation', () async {
      final Directory temp = createTempDir('gfrm-rel-phase-');

      final MigrationContext ctx = buildMigrationContext(
        temp,
        _StubSourceAdapter(),
        _StubTargetAdapter(tagExistsResult: true, publishResult: 'created'),
        selectedTags: <String>['v1.0.0'],
        targetTags: <String>{'v1.0.0'},
        releases: <Map<String, dynamic>>[buildMinimalReleasePayload('v1.0.0')],
      );

      await ReleasePhaseRunner(logger: logger).run(ctx);

      expect(ctx.checkpointState['release:v1.0.0'], 'created');
    });

    test('processes multiple tags concurrently with 2 workers', () async {
      final Directory temp = createTempDir('gfrm-rel-phase-');

      final MigrationContext ctx = buildMigrationContext(
        temp,
        _StubSourceAdapter(),
        _StubTargetAdapter(tagExistsResult: true, publishResult: 'created'),
        selectedTags: <String>['v1.0.0', 'v1.1.0'],
        targetTags: <String>{'v1.0.0', 'v1.1.0'},
        releases: <Map<String, dynamic>>[
          buildMinimalReleasePayload('v1.0.0'),
          buildMinimalReleasePayload('v1.1.0'),
        ],
        releaseWorkers: 2,
      );

      final ReleaseMigrationCounts counts = await ReleasePhaseRunner(logger: logger).run(ctx);

      expect(counts.created, 2);
      expect(counts.failed, 0);
    });
  });
}
