import 'package:gfrm_dart/src/application/preflight_check.dart';
import 'package:gfrm_dart/src/application/missing_target_commit.dart';
import 'package:gfrm_dart/src/application/preflight_service.dart';
import 'package:gfrm_dart/src/models/migration_context.dart';
import 'package:gfrm_dart/src/models/runtime_options.dart';
import 'package:gfrm_dart/src/core/adapters/provider_adapter.dart';
import 'package:gfrm_dart/src/core/types/canonical_release.dart';
import 'package:gfrm_dart/src/providers/registry.dart';
import 'package:test/test.dart';

import '../../support/migration_context_fixture.dart';
import '../../support/runtime_options_fixture.dart';
import '../../support/temp_dir.dart';

final class _SourceAdapter extends ProviderAdapter {
  @override
  String get name => 'stub-source';

  @override
  ProviderRef parseUrl(String url) {
    if (!url.startsWith('https://github.com/')) {
      throw ArgumentError('Invalid GitHub repository URL: $url');
    }

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
}

final class _TargetAdapter extends ProviderAdapter {
  _TargetAdapter({this.commitExistsResult = true});

  final bool commitExistsResult;

  @override
  String get name => 'stub-target';

  @override
  ProviderRef parseUrl(String url) {
    if (!url.startsWith('https://gitlab.com/')) {
      throw ArgumentError('Invalid GitLab repository URL: $url');
    }

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
    throw UnimplementedError();
  }

  @override
  Future<bool> commitExists(ProviderRef ref, String token, String sha) async {
    return commitExistsResult;
  }
}

final class _BuggyTargetAdapter extends ProviderAdapter {
  @override
  String get name => 'buggy-target';

  @override
  ProviderRef parseUrl(String url) {
    throw StateError('unexpected parser failure');
  }

  @override
  CanonicalRelease toCanonicalRelease(Map<String, dynamic> payload) {
    throw UnimplementedError();
  }
}

ProviderRegistry _buildRegistry() {
  return ProviderRegistry(<String, ProviderAdapter>{
    'github': _SourceAdapter(),
    'gitlab': _TargetAdapter(),
  });
}

ProviderRegistry _buildBuggyRegistry() {
  return ProviderRegistry(<String, ProviderAdapter>{
    'github': _SourceAdapter(),
    'gitlab': _BuggyTargetAdapter(),
  });
}

void main() {
  group('PreflightService', () {
    test('classifies supported startup checks as ok', () {
      final PreflightService service = PreflightService(
        settingsLoader: () => <String, dynamic>{
          'profiles': <String, dynamic>{
            'work': <String, dynamic>{},
          },
        },
      );
      final ProviderRegistry registry = _buildRegistry();

      final List<PreflightCheck> checks = service.evaluateStartup(
        buildRuntimeOptions(settingsProfile: 'work'),
        registry,
      );

      expect(checks.every((PreflightCheck check) => check.status == PreflightCheckStatus.ok), isTrue);
    });

    test('classifies missing settings profile as warning', () {
      final PreflightService service = PreflightService(
        settingsLoader: () => <String, dynamic>{
          'profiles': <String, dynamic>{
            'default': <String, dynamic>{},
          },
        },
      );

      final PreflightCheck check = service
          .evaluateStartup(
            buildRuntimeOptions(settingsProfile: 'work'),
            _buildRegistry(),
          )
          .firstWhere((PreflightCheck item) => item.field == PreflightService.fieldSettingsProfile);

      expect(check.status, PreflightCheckStatus.warning);
      expect(check.code, 'missing-settings-profile');
    });

    test('classifies missing tokens as blocking errors', () {
      final PreflightService service = PreflightService();

      final List<PreflightCheck> checks = service.evaluateStartup(
        buildRuntimeOptions(sourceToken: '', targetToken: ''),
        _buildRegistry(),
      );

      expect(PreflightService.hasBlockingErrors(checks), isTrue);
      expect(checks.where((PreflightCheck check) => check.isBlocking), hasLength(2));
    });

    test('evaluateCommand accepts migrate and resume but rejects other commands', () {
      final PreflightService service = PreflightService();

      final List<PreflightCheck> migrateChecks =
          service.evaluateCommand(buildRuntimeOptions(commandName: commandMigrate));
      final List<PreflightCheck> resumeChecks =
          service.evaluateCommand(buildRuntimeOptions(commandName: commandResume));
      final List<PreflightCheck> settingsChecks =
          service.evaluateCommand(buildRuntimeOptions(commandName: commandSettings));

      expect(migrateChecks.single.status, PreflightCheckStatus.ok);
      expect(resumeChecks.single.status, PreflightCheckStatus.ok);
      expect(settingsChecks.single.status, PreflightCheckStatus.error);
    });

    test('firstBlockingError returns null when all checks are non-blocking', () {
      final PreflightService service = PreflightService(
        settingsLoader: () => <String, dynamic>{
          'profiles': <String, dynamic>{
            'default': <String, dynamic>{},
          },
        },
      );

      final List<PreflightCheck> checks = service.evaluateStartup(
        buildRuntimeOptions(settingsProfile: 'missing-profile'),
        _buildRegistry(),
      );

      expect(PreflightService.firstBlockingError(checks), isNull);
      expect(PreflightService.hasBlockingErrors(checks), isFalse);
    });

    test('rethrows unexpected URL parsing failures', () {
      final PreflightService service = PreflightService();

      expect(
        () => service.evaluateStartup(
          buildRuntimeOptions(),
          _buildBuggyRegistry(),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('findMissingTargetCommits returns tags whose commit does not exist in target', () async {
      final PreflightService service = PreflightService();
      final MigrationContext context = buildMigrationContext(
        createTempDir('gfrm-preflight-missing-target-'),
        _SourceAdapter(),
        _TargetAdapter(commitExistsResult: false),
        selectedTags: const <String>['v1.0.0'],
        releases: const <Map<String, dynamic>>[
          <String, dynamic>{
            'tag_name': 'v1.0.0',
            'name': 'v1.0.0',
            'description_markdown': '',
            'commit_sha': 'deadbeef',
            'assets': <String, dynamic>{'links': <dynamic>[], 'sources': <dynamic>[]},
          },
        ],
      );

      final List<MissingTargetCommit> missing = await service.findMissingTargetCommits(context);

      expect(missing, hasLength(1));
      expect(missing.single.tag, 'v1.0.0');
      expect(missing.single.commitSha, 'deadbeef');
    });

    test('findMissingTargetCommits still checks tag readiness when release migration is disabled', () async {
      final PreflightService service = PreflightService();
      final MigrationContext context = buildMigrationContext(
        createTempDir('gfrm-preflight-skip-releases-'),
        _SourceAdapter(),
        _TargetAdapter(commitExistsResult: false),
        selectedTags: const <String>['v1.0.0'],
        skipReleaseMigration: true,
        releases: const <Map<String, dynamic>>[
          <String, dynamic>{
            'tag_name': 'v1.0.0',
            'name': 'v1.0.0',
            'description_markdown': '',
            'commit_sha': 'deadbeef',
            'assets': <String, dynamic>{'links': <dynamic>[], 'sources': <dynamic>[]},
          },
        ],
      );

      final List<MissingTargetCommit> missing = await service.findMissingTargetCommits(context);

      expect(missing, hasLength(1));
      expect(missing.single.commitSha, 'deadbeef');
    });

    test('buildMissingTargetCommitCheck includes remediation guidance', () {
      final PreflightService service = PreflightService();
      final MigrationContext context = buildMigrationContext(
        createTempDir('gfrm-preflight-check-'),
        _SourceAdapter(),
        _TargetAdapter(commitExistsResult: false),
        selectedTags: const <String>['v1.0.0'],
        releases: const <Map<String, dynamic>>[
          <String, dynamic>{
            'tag_name': 'v1.0.0',
            'name': 'v1.0.0',
            'description_markdown': '',
            'commit_sha': 'deadbeef',
            'assets': <String, dynamic>{'links': <dynamic>[], 'sources': <dynamic>[]},
          },
        ],
      );

      final PreflightCheck check = service.buildMissingTargetCommitCheck(
        context,
        const <MissingTargetCommit>[MissingTargetCommit(tag: 'v1.0.0', commitSha: 'deadbeef')],
      );

      expect(check.status, PreflightCheckStatus.error);
      expect(check.code, 'missing-target-commit-history');
      expect(check.message, contains('v1.0.0 -> deadbeef'));
      expect(check.hint, contains('git clone --mirror'));
      expect(check.hint, contains('Use --skip-tags only if the target already has the requested tags.'));
    });

    test('buildSkipTagsSafetyCheck returns null when skip-tags is not enabled', () {
      final PreflightService service = PreflightService();
      final MigrationContext context = buildMigrationContext(
        createTempDir('gfrm-preflight-skip-tags-safe-'),
        _SourceAdapter(),
        _TargetAdapter(),
        selectedTags: const <String>['v1.0.0'],
        skipTagMigration: false,
      );

      final PreflightCheck? check = service.buildSkipTagsSafetyCheck(context);

      expect(check, isNull);
    });

    test('buildSkipTagsSafetyCheck returns error when skip-tags enabled but target has no tags', () {
      final PreflightService service = PreflightService();
      final MigrationContext context = buildMigrationContext(
        createTempDir('gfrm-preflight-skip-tags-unsafe-'),
        _SourceAdapter(),
        _TargetAdapter(),
        selectedTags: const <String>['v1.0.0'],
        skipTagMigration: true,
        targetTags: const <String>{},
      );

      final PreflightCheck? check = service.buildSkipTagsSafetyCheck(context);

      expect(check, isNotNull);
      expect(check!.status, PreflightCheckStatus.error);
      expect(check.code, 'skip-tags-unsafe');
      expect(check.message, contains('--skip-tags'));
      expect(check.message, contains('no existing tags'));
      expect(check.hint, contains('migrate tags by removing --skip-tags'));
    });

    test('buildSkipTagsSafetyCheck returns null when skip-tags enabled and target has existing tags', () {
      final PreflightService service = PreflightService();
      final MigrationContext context = buildMigrationContext(
        createTempDir('gfrm-preflight-skip-tags-safe-existing-'),
        _SourceAdapter(),
        _TargetAdapter(),
        selectedTags: const <String>['v1.0.0'],
        skipTagMigration: true,
        targetTags: const <String>{'v0.9.0', 'v1.0.0'},
      );

      final PreflightCheck? check = service.buildSkipTagsSafetyCheck(context);

      expect(check, isNull);
    });
  });
}
