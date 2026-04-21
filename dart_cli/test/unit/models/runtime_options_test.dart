import 'dart:io';

import 'package:gfrm_dart/src/models/runtime_options.dart';
import 'package:test/test.dart';

RuntimeOptions buildOptions({
  String sessionTokenMode = 'env',
  String sessionSourceTokenEnv = '',
  String sessionTargetTokenEnv = '',
  String sessionFile = '',
  String workdir = '',
  String checkpointFile = '',
  bool skipReleaseMigration = false,
  bool skipReleaseAssetMigration = false,
}) {
  return RuntimeOptions(
    commandName: commandMigrate,
    sourceProvider: 'github',
    sourceUrl: 'https://github.com/acme/src',
    sourceToken: 'source-token',
    targetProvider: 'gitlab',
    targetUrl: 'https://gitlab.com/acme/dst',
    targetToken: 'target-token',
    migrationOrder: 'github-to-gitlab',
    skipTagMigration: false,
    skipReleaseMigration: skipReleaseMigration,
    skipReleaseAssetMigration: skipReleaseAssetMigration,
    fromTag: 'v1.0.0',
    toTag: 'v2.0.0',
    dryRun: false,
    nonInteractive: true,
    workdir: workdir,
    logFile: '',
    loadSession: false,
    saveSession: true,
    resumeSession: false,
    sessionFile: sessionFile,
    sessionTokenMode: sessionTokenMode,
    sessionSourceTokenEnv: sessionSourceTokenEnv,
    sessionTargetTokenEnv: sessionTargetTokenEnv,
    settingsProfile: 'default',
    downloadWorkers: 4,
    releaseWorkers: 1,
    checkpointFile: checkpointFile,
    tagsFile: '',
    noBanner: false,
    quiet: false,
    jsonOutput: false,
    progressBar: false,
    demoMode: false,
    demoReleases: 5,
    demoSleepSeconds: 1.0,
  );
}

void main() {
  group('RuntimeOptions', () {
    test('effective paths fall back to current directory', () {
      final RuntimeOptions options = buildOptions();
      final String cwd = Directory.current.path;

      expect(options.effectiveWorkdir(), '$cwd/migration-results');
      expect(options.effectiveSessionFile(), '$cwd/sessions/last-session.json');
      expect(options.effectiveCheckpointFile(), '$cwd/migration-results/checkpoints/state.jsonl');
    });

    test('session env names use defaults when blank', () {
      final RuntimeOptions options = buildOptions(sessionSourceTokenEnv: ' ', sessionTargetTokenEnv: '');

      expect(options.sessionSourceEnvName(), defaultSourceTokenEnv);
      expect(options.sessionTargetEnvName(), defaultTargetTokenEnv);
    });

    test('toSessionPayload stores tokens in plain mode', () {
      final RuntimeOptions options = buildOptions(sessionTokenMode: 'plain');

      final Map<String, dynamic> payload = options.toSessionPayload();
      expect(payload['session_token_mode'], 'plain');
      expect(payload['settings_profile'], 'default');
      expect(payload['source_token'], 'source-token');
      expect(payload['target_token'], 'target-token');
      expect(payload.containsKey('source_token_env'), isFalse);
      expect(payload.containsKey('target_token_env'), isFalse);
    });

    test('toSessionPayload stores env names in env mode', () {
      final RuntimeOptions options = buildOptions(
        sessionTokenMode: 'env',
        sessionSourceTokenEnv: 'SRC_ENV',
        sessionTargetTokenEnv: 'DST_ENV',
      );

      final Map<String, dynamic> payload = options.toSessionPayload();
      expect(payload['session_token_mode'], 'env');
      expect(payload['settings_profile'], 'default');
      expect(payload['source_token_env'], 'SRC_ENV');
      expect(payload['target_token_env'], 'DST_ENV');
      expect(payload['skip_release_migration'], isFalse);
      expect(payload['skip_release_asset_migration'], isFalse);
      expect(payload.containsKey('source_token'), isFalse);
      expect(payload.containsKey('target_token'), isFalse);
    });

    test('toSessionPayload stores release skip flags', () {
      final RuntimeOptions options = buildOptions(
        skipReleaseMigration: true,
        skipReleaseAssetMigration: true,
      );

      final Map<String, dynamic> payload = options.toSessionPayload();

      expect(payload['skip_release_migration'], isTrue);
      expect(payload['skip_release_asset_migration'], isTrue);
    });

    test('copyWith updates only selected fields', () {
      final RuntimeOptions options = buildOptions();

      final RuntimeOptions changed = options.copyWith(
        dryRun: true,
        skipReleaseMigration: true,
        skipReleaseAssetMigration: true,
        workdir: '/tmp/custom-workdir',
        downloadWorkers: 8,
      );

      expect(changed.dryRun, isTrue);
      expect(changed.skipReleaseMigration, isTrue);
      expect(changed.skipReleaseAssetMigration, isTrue);
      expect(changed.workdir, '/tmp/custom-workdir');
      expect(changed.downloadWorkers, 8);
      expect(changed.sourceProvider, options.sourceProvider);
      expect(changed.targetProvider, options.targetProvider);
      expect(changed.releaseWorkers, options.releaseWorkers);
    });

    test('effective paths use explicit values when provided', () {
      final RuntimeOptions options = buildOptions(
        workdir: '/tmp/gfrm-results',
        checkpointFile: '/tmp/gfrm-results/state.jsonl',
        sessionFile: '/tmp/gfrm-session.json',
      );

      expect(options.effectiveWorkdir(), '/tmp/gfrm-results');
      expect(options.effectiveCheckpointFile(), '/tmp/gfrm-results/state.jsonl');
      expect(options.effectiveSessionFile(), '/tmp/gfrm-session.json');
    });
  });
}
