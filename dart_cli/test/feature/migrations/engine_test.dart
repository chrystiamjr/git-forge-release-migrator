import 'dart:convert';
import 'dart:io';

import 'package:gfrm_dart/src/core/adapters/provider_adapter.dart';
import 'package:gfrm_dart/src/core/exceptions/migration_phase_error.dart';
import 'package:gfrm_dart/src/core/types/canonical_release.dart';
import 'package:gfrm_dart/src/core/types/existing_release_info.dart';
import 'package:gfrm_dart/src/core/types/publish_release_input.dart';
import 'package:gfrm_dart/src/migrations/engine.dart';
import 'package:gfrm_dart/src/models/migration_context.dart';
import 'package:gfrm_dart/src/models/runtime_options.dart';
import 'package:gfrm_dart/src/providers/registry.dart';
import '../../support/logging.dart';
import '../../support/provider_fixtures.dart';
import '../../support/runtime_options_fixture.dart';
import '../../support/temp_dir.dart';
import 'package:test/test.dart';

final class _EmptySourceAdapter extends ProviderAdapter {
  @override
  String get name => 'empty-source';

  @override
  ProviderRef parseUrl(String url) {
    return ProviderRef(
      provider: 'github',
      rawUrl: url,
      baseUrl: 'https://github.com',
      host: 'github.com',
      resource: 'acme/source',
    );
  }

  @override
  CanonicalRelease toCanonicalRelease(Map<String, dynamic> payload) {
    return CanonicalRelease.fromMap(payload);
  }

  @override
  Future<List<Map<String, dynamic>>> listReleases(ProviderRef ref, String token) async {
    return <Map<String, dynamic>>[];
  }
}

final class _TargetAdapter extends ProviderAdapter {
  _TargetAdapter({
    this.onCreateTag,
  });

  final Future<void> Function(ProviderRef, String, String, String, CanonicalRelease)? onCreateTag;
  final Set<String> _createdTags = <String>{};

  @override
  String get name => 'target';

  @override
  ProviderRef parseUrl(String url) {
    return ProviderRef(
      provider: 'gitlab',
      rawUrl: url,
      baseUrl: 'https://gitlab.com',
      host: 'gitlab.com',
      resource: 'acme/target',
    );
  }

  @override
  CanonicalRelease toCanonicalRelease(Map<String, dynamic> payload) {
    return CanonicalRelease.fromMap(payload);
  }

  @override
  Future<List<String>> listTags(ProviderRef ref, String token) async => _createdTags.toList(growable: false);

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
  Future<bool> tagExists(ProviderRef ref, String token, String tag) async => _createdTags.contains(tag);

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

final class _ReleaseSourceAdapter extends ProviderAdapter {
  _ReleaseSourceAdapter({required this.releases});

  final List<Map<String, dynamic>> releases;

  @override
  String get name => 'release-source';

  @override
  ProviderRef parseUrl(String url) {
    return ProviderRef(
      provider: 'github',
      rawUrl: url,
      baseUrl: 'https://github.com',
      host: 'github.com',
      resource: 'acme/source',
    );
  }

  @override
  CanonicalRelease toCanonicalRelease(Map<String, dynamic> payload) {
    return CanonicalRelease.fromMap(payload);
  }

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

void main() {
  group('engine', () {
    test('creates parent directory for custom --log-file before truncating file', () async {
      final Directory temp = createTempDir('gfrm-engine-log-path-');

      final String workdirPath = '${temp.path}/results';
      final String logPath = '${temp.path}/logs/nested/migration-log.jsonl';
      final RuntimeOptions options = buildRuntimeOptions(workdir: workdirPath, logFile: logPath);

      final _EmptySourceAdapter source = _EmptySourceAdapter();
      final _TargetAdapter target = _TargetAdapter();
      final ProviderRegistry registry = ProviderRegistry(<String, ProviderAdapter>{
        'github': source,
        'gitlab': target,
      });
      final MigrationEngine engine = MigrationEngine(
        registry: registry,
        logger: createSilentLogger(),
      );

      await expectLater(
        engine.run(
          options,
          source.parseUrl(options.sourceUrl),
          target.parseUrl(options.targetUrl),
        ),
        throwsA(isA<MigrationPhaseError>()),
      );

      expect(File(logPath).parent.existsSync(), isTrue);
      expect(File(logPath).existsSync(), isTrue);
    });

    test('createContext builds context with selected and target tag snapshots', () async {
      final Directory temp = createTempDir('gfrm-engine-create-context-');
      final RuntimeOptions options = buildRuntimeOptions(
        workdir: '${temp.path}/results',
        fromTag: 'v1.0.0',
        toTag: 'v1.0.0',
      );

      final _ReleaseSourceAdapter source = _ReleaseSourceAdapter(
        releases: <Map<String, dynamic>>[
          buildMinimalReleasePayload('v1.0.0'),
          buildMinimalReleasePayload('v1.1.0'),
        ],
      );
      final _TargetAdapter target = _TargetAdapter();
      await target.createTagForMigration(
        target.parseUrl(options.targetUrl),
        options.targetToken,
        'v-existing',
        'abc123',
        CanonicalRelease.fromMap(buildMinimalReleasePayload('v-existing')),
      );
      final ProviderRegistry registry = ProviderRegistry(<String, ProviderAdapter>{
        'github': source,
        'gitlab': target,
      });
      final MigrationEngine engine = MigrationEngine(
        registry: registry,
        logger: createSilentLogger(),
      );

      final MigrationContext context = await engine.createContext(
        options,
        source.parseUrl(options.sourceUrl),
        target.parseUrl(options.targetUrl),
      );

      expect(context.selectedTags, <String>['v1.0.0']);
      expect(context.targetTags, contains('v-existing'));
      expect(context.targetReleaseTags, contains('v-existing'));
      expect(File(context.logPath).existsSync(), isTrue);
      expect(context.checkpointSignature, contains('github-to-gitlab'));
    });

    test('run writes summary for successful migrations inside the workdir', () async {
      final Directory temp = createTempDir('gfrm-engine-success-');
      final RuntimeOptions options = buildRuntimeOptions(
        workdir: '${temp.path}/results',
        fromTag: 'v1.0.0',
        toTag: 'v1.0.0',
      );

      final _ReleaseSourceAdapter source = _ReleaseSourceAdapter(
        releases: <Map<String, dynamic>>[
          buildMinimalReleasePayload('v1.0.0'),
          buildMinimalReleasePayload('v1.1.0'),
        ],
      );
      final _TargetAdapter target = _TargetAdapter();
      final ProviderRegistry registry = ProviderRegistry(<String, ProviderAdapter>{
        'github': source,
        'gitlab': target,
      });
      final MigrationEngine engine = MigrationEngine(
        registry: registry,
        logger: createSilentLogger(),
      );

      await engine.run(
        options,
        source.parseUrl(options.sourceUrl),
        target.parseUrl(options.targetUrl),
      );

      final File summaryFile = File('${options.effectiveWorkdir()}/summary.json');
      expect(summaryFile.existsSync(), isTrue);
      final Map<String, dynamic> summary = jsonDecode(summaryFile.readAsStringSync()) as Map<String, dynamic>;

      expect(summary['schema_version'], 2);
      expect((summary['counts'] as Map<String, dynamic>)['releases_created'], 1);
      expect((summary['failed_tags'] as List<dynamic>), isEmpty);
    });

    test('run writes retry metadata before surfacing partial failures', () async {
      final Directory temp = createTempDir('gfrm-engine-partial-failure-');
      final RuntimeOptions options = buildRuntimeOptions(workdir: '${temp.path}/results');

      final _ReleaseSourceAdapter source = _ReleaseSourceAdapter(
        releases: <Map<String, dynamic>>[buildMinimalReleasePayload('v1.0.0')],
      );
      final _TargetAdapter target = _TargetAdapter(
        onCreateTag: (_, __, ___, ____, _____) async => throw Exception('network error'),
      );
      final ProviderRegistry registry = ProviderRegistry(<String, ProviderAdapter>{
        'github': source,
        'gitlab': target,
      });
      final MigrationEngine engine = MigrationEngine(
        registry: registry,
        logger: createSilentLogger(),
      );

      await expectLater(
        engine.run(
          options,
          source.parseUrl(options.sourceUrl),
          target.parseUrl(options.targetUrl),
        ),
        throwsA(
          isA<MigrationPhaseError>().having(
            (MigrationPhaseError error) => error.message,
            'message',
            'Migration finished with failures',
          ),
        ),
      );

      final File summaryFile = File('${options.effectiveWorkdir()}/summary.json');
      expect(summaryFile.existsSync(), isTrue);
      final Map<String, dynamic> summary = jsonDecode(summaryFile.readAsStringSync()) as Map<String, dynamic>;

      expect((summary['counts'] as Map<String, dynamic>)['tags_failed'], 1);
      expect(summary['retry_command'], contains('gfrm resume --tags-file'));
      expect(File('${options.effectiveWorkdir()}/failed-tags.txt').readAsStringSync(), 'v1.0.0\n');
    });
  });
}
