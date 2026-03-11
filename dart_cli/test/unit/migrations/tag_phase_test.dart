import 'dart:io';

import 'package:gfrm_dart/src/core/adapters/provider_adapter.dart';
import 'package:gfrm_dart/src/core/exceptions/authentication_error.dart';
import 'package:gfrm_dart/src/core/logging.dart';
import 'package:gfrm_dart/src/core/types/canonical_release.dart';
import 'package:gfrm_dart/src/core/types/phase.dart';
import 'package:gfrm_dart/src/migrations/tag_phase.dart';
import 'package:gfrm_dart/src/models/migration_context.dart';
import '../../support/logging.dart';
import '../../support/migration_context_fixture.dart';
import '../../support/temp_dir.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Stub adapters
// ---------------------------------------------------------------------------

final class _StubSourceAdapter extends ProviderAdapter {
  _StubSourceAdapter({this.onResolveCommitSha});

  final Future<String> Function(ProviderRef ref, String token, String tag, CanonicalRelease canonical)?
      onResolveCommitSha;

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
  Future<String> resolveCommitShaForMigration(
    ProviderRef ref,
    String token,
    String tag,
    CanonicalRelease canonical,
  ) async {
    if (onResolveCommitSha != null) {
      return onResolveCommitSha!(ref, token, tag, canonical);
    }
    if (canonical.commitSha.isNotEmpty) {
      return canonical.commitSha;
    }
    return 'default-sha';
  }
}

final class _StubTargetAdapter extends ProviderAdapter {
  _StubTargetAdapter({this.onTagExists, this.onCreateTag});

  final Future<bool> Function(ProviderRef ref, String token, String tag)? onTagExists;
  final Future<void> Function(ProviderRef ref, String token, String tag, String sha, CanonicalRelease canonical)?
      onCreateTag;

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
  Future<bool> tagExists(ProviderRef ref, String token, String tag) async {
    if (onTagExists != null) {
      return onTagExists!(ref, token, tag);
    }
    return false;
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
    // default: success (no-op)
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

  group('TagPhaseRunner', () {
    test('returns empty counts when skipTagMigration is true', () async {
      final Directory temp = createTempDir('gfrm-tag-phase-');

      final MigrationContext ctx = buildMigrationContext(
        temp,
        _StubSourceAdapter(),
        _StubTargetAdapter(),
        selectedTags: <String>['v1.0.0', 'v1.1.0'],
        skipTagMigration: true,
      );

      final TagMigrationCounts counts = await TagPhaseRunner(logger: logger).run(ctx);

      expect(counts.created, 0);
      expect(counts.skipped, 0);
      expect(counts.failed, 0);
      expect(counts.wouldCreate, 0);
    });

    test('returns empty counts when selectedTags is empty', () async {
      final Directory temp = createTempDir('gfrm-tag-phase-');

      final MigrationContext ctx = buildMigrationContext(temp, _StubSourceAdapter(), _StubTargetAdapter());

      final TagMigrationCounts counts = await TagPhaseRunner(logger: logger).run(ctx);

      expect(counts.created, 0);
      expect(counts.skipped, 0);
      expect(counts.failed, 0);
    });

    test('creates tag successfully and increments created count', () async {
      final Directory temp = createTempDir('gfrm-tag-phase-');

      bool createTagCalled = false;
      final _StubTargetAdapter target = _StubTargetAdapter(
        onCreateTag: (_, __, ___, ____, _____) async {
          createTagCalled = true;
        },
      );
      final MigrationContext ctx = buildMigrationContext(
        temp,
        _StubSourceAdapter(),
        target,
        selectedTags: <String>['v1.0.0'],
        releases: <Map<String, dynamic>>[
          <String, dynamic>{'tag_name': 'v1.0.0', 'commit_sha': 'abc123'},
        ],
      );

      final TagMigrationCounts counts = await TagPhaseRunner(logger: logger).run(ctx);

      expect(counts.created, 1);
      expect(counts.failed, 0);
      expect(createTagCalled, isTrue);
    });

    test('skips tag already in targetTags set without calling tagExists', () async {
      final Directory temp = createTempDir('gfrm-tag-phase-');

      bool tagExistsCalled = false;
      final _StubTargetAdapter target = _StubTargetAdapter(
        onTagExists: (_, __, ___) async {
          tagExistsCalled = true;
          return true;
        },
      );
      final MigrationContext ctx = buildMigrationContext(
        temp,
        _StubSourceAdapter(),
        target,
        selectedTags: <String>['v1.0.0'],
        targetTags: <String>{'v1.0.0'},
        releases: <Map<String, dynamic>>[
          <String, dynamic>{'tag_name': 'v1.0.0', 'commit_sha': 'abc123'},
        ],
      );

      final TagMigrationCounts counts = await TagPhaseRunner(logger: logger).run(ctx);

      expect(counts.skipped, 1);
      expect(tagExistsCalled, isFalse); // targetTags set is checked first
    });

    test('skips tag when tagExists returns true on remote', () async {
      final Directory temp = createTempDir('gfrm-tag-phase-');

      final _StubTargetAdapter target = _StubTargetAdapter(
        onTagExists: (_, __, ___) async => true,
      );
      final MigrationContext ctx = buildMigrationContext(
        temp,
        _StubSourceAdapter(),
        target,
        selectedTags: <String>['v1.0.0'],
        releases: <Map<String, dynamic>>[
          <String, dynamic>{'tag_name': 'v1.0.0', 'commit_sha': 'abc123'},
        ],
      );

      final TagMigrationCounts counts = await TagPhaseRunner(logger: logger).run(ctx);

      expect(counts.skipped, 1);
      expect(counts.created, 0);
    });

    test('fails tag when resolveCommitShaForMigration returns empty string', () async {
      final Directory temp = createTempDir('gfrm-tag-phase-');

      final _StubSourceAdapter source = _StubSourceAdapter(
        onResolveCommitSha: (_, __, ___, ____) async => '',
      );
      final MigrationContext ctx = buildMigrationContext(
        temp,
        source,
        _StubTargetAdapter(),
        selectedTags: <String>['v1.0.0'],
        releases: <Map<String, dynamic>>[
          <String, dynamic>{'tag_name': 'v1.0.0'},
        ],
      );

      final TagMigrationCounts counts = await TagPhaseRunner(logger: logger).run(ctx);

      expect(counts.failed, 1);
      expect(ctx.failedTags, contains('v1.0.0'));
    });

    test('dry-run increments wouldCreate without calling createTagForMigration', () async {
      final Directory temp = createTempDir('gfrm-tag-phase-');

      bool createTagCalled = false;
      final _StubTargetAdapter target = _StubTargetAdapter(
        onCreateTag: (_, __, ___, ____, _____) async {
          createTagCalled = true;
        },
      );
      final MigrationContext ctx = buildMigrationContext(
        temp,
        _StubSourceAdapter(),
        target,
        selectedTags: <String>['v1.0.0'],
        releases: <Map<String, dynamic>>[
          <String, dynamic>{'tag_name': 'v1.0.0', 'commit_sha': 'abc123'},
        ],
        dryRun: true,
      );

      final TagMigrationCounts counts = await TagPhaseRunner(logger: logger).run(ctx);

      expect(counts.wouldCreate, 1);
      expect(createTagCalled, isFalse);
    });

    test('rethrows AuthenticationError from tagExists', () async {
      final Directory temp = createTempDir('gfrm-tag-phase-');

      final _StubTargetAdapter target = _StubTargetAdapter(
        onTagExists: (_, __, ___) async => throw AuthenticationError('401 from tagExists'),
      );
      final MigrationContext ctx = buildMigrationContext(
        temp,
        _StubSourceAdapter(),
        target,
        selectedTags: <String>['v1.0.0'],
        releases: <Map<String, dynamic>>[
          <String, dynamic>{'tag_name': 'v1.0.0', 'commit_sha': 'abc123'},
        ],
      );

      await expectLater(
        TagPhaseRunner(logger: logger).run(ctx),
        throwsA(isA<AuthenticationError>()),
      );
    });

    test('rethrows AuthenticationError from resolveCommitShaForMigration', () async {
      final Directory temp = createTempDir('gfrm-tag-phase-');

      final _StubSourceAdapter source = _StubSourceAdapter(
        onResolveCommitSha: (_, __, ___, ____) async => throw AuthenticationError('401 from resolveCommit'),
      );
      final MigrationContext ctx = buildMigrationContext(
        temp,
        source,
        _StubTargetAdapter(),
        selectedTags: <String>['v1.0.0'],
        releases: <Map<String, dynamic>>[
          <String, dynamic>{'tag_name': 'v1.0.0'},
        ],
      );

      await expectLater(
        TagPhaseRunner(logger: logger).run(ctx),
        throwsA(isA<AuthenticationError>()),
      );
    });

    test('records AuthenticationError from createTagForMigration as failed (not rethrown)', () async {
      final Directory temp = createTempDir('gfrm-tag-phase-');

      final _StubTargetAdapter target = _StubTargetAdapter(
        onCreateTag: (_, __, ___, ____, _____) async => throw AuthenticationError('401 from createTag'),
      );
      final MigrationContext ctx = buildMigrationContext(
        temp,
        _StubSourceAdapter(),
        target,
        selectedTags: <String>['v1.0.0'],
        releases: <Map<String, dynamic>>[
          <String, dynamic>{'tag_name': 'v1.0.0', 'commit_sha': 'abc123'},
        ],
      );

      final TagMigrationCounts counts = await TagPhaseRunner(logger: logger).run(ctx);

      expect(counts.failed, 1);
      expect(ctx.failedTags, contains('v1.0.0'));
    });

    test('skips tag via checkpoint when status is terminal and tag is in targetTags', () async {
      final Directory temp = createTempDir('gfrm-tag-phase-');

      bool createTagCalled = false;
      final _StubTargetAdapter target = _StubTargetAdapter(
        onCreateTag: (_, __, ___, ____, _____) async {
          createTagCalled = true;
        },
      );
      final MigrationContext ctx = buildMigrationContext(
        temp,
        _StubSourceAdapter(),
        target,
        selectedTags: <String>['v1.0.0'],
        targetTags: <String>{'v1.0.0'},
        checkpointState: <String, String>{'tag:v1.0.0': 'tag_created'},
        releases: <Map<String, dynamic>>[
          <String, dynamic>{'tag_name': 'v1.0.0', 'commit_sha': 'abc123'},
        ],
      );

      final TagMigrationCounts counts = await TagPhaseRunner(logger: logger).run(ctx);

      expect(counts.skipped, 1);
      expect(createTagCalled, isFalse);
    });

    test('updates checkpointState after successful tag creation', () async {
      final Directory temp = createTempDir('gfrm-tag-phase-');

      final MigrationContext ctx = buildMigrationContext(
        temp,
        _StubSourceAdapter(),
        _StubTargetAdapter(),
        selectedTags: <String>['v1.0.0'],
        releases: <Map<String, dynamic>>[
          <String, dynamic>{'tag_name': 'v1.0.0', 'commit_sha': 'abc123'},
        ],
      );

      await TagPhaseRunner(logger: logger).run(ctx);

      expect(ctx.checkpointState['tag:v1.0.0'], 'tag_created');
    });

    test('processes multiple tags and tallies counts correctly', () async {
      final Directory temp = createTempDir('gfrm-tag-phase-');

      final _StubTargetAdapter target = _StubTargetAdapter(
        onTagExists: (_, __, tag) async => tag == 'v1.0.0', // v1.0.0 already exists
      );
      final MigrationContext ctx = buildMigrationContext(
        temp,
        _StubSourceAdapter(),
        target,
        selectedTags: <String>['v1.0.0', 'v1.1.0', 'v1.2.0'],
        releases: <Map<String, dynamic>>[
          <String, dynamic>{'tag_name': 'v1.0.0', 'commit_sha': 'aaa'},
          <String, dynamic>{'tag_name': 'v1.1.0', 'commit_sha': 'bbb'},
          <String, dynamic>{'tag_name': 'v1.2.0', 'commit_sha': 'ccc'},
        ],
      );

      final TagMigrationCounts counts = await TagPhaseRunner(logger: logger).run(ctx);

      expect(counts.skipped, 1); // v1.0.0 already exists
      expect(counts.created, 2); // v1.1.0 and v1.2.0 created
    });

    test('adds created tag to targetTags set after creation', () async {
      final Directory temp = createTempDir('gfrm-tag-phase-');

      final MigrationContext ctx = buildMigrationContext(
        temp,
        _StubSourceAdapter(),
        _StubTargetAdapter(),
        selectedTags: <String>['v1.0.0'],
        releases: <Map<String, dynamic>>[
          <String, dynamic>{'tag_name': 'v1.0.0', 'commit_sha': 'abc123'},
        ],
      );

      await TagPhaseRunner(logger: logger).run(ctx);

      expect(ctx.targetTags, contains('v1.0.0'));
    });
  });
}
