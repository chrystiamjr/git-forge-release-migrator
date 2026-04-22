import 'dart:io';

import '../application/run_request.dart';
import '../application/run_result.dart';
import '../application/run_service.dart';
import '../config/types/smoke_command_options.dart';
import '../core/console_output.dart';
import '../core/exceptions/migration_phase_error.dart';
import '../core/http.dart';
import '../core/logging.dart';
import '../core/settings.dart';
import '../models/runtime_options.dart';
import '../smoke/artifact_validator.dart';
import '../smoke/bitbucket_fixture_trigger.dart';
import '../smoke/fixture_trigger.dart';
import '../smoke/github_fixture_trigger.dart';
import '../smoke/gitlab_fixture_trigger.dart';
import '../smoke/repo_url_parser.dart';
import '../smoke/smoke_runner.dart';
import 'runtime_support.dart';

/// Bridges the CLI smoke request to the `SmokeRunner`.
///
/// Resolves source tokens from `settings.yaml`, constructs the right
/// `FixtureTrigger` for the source forge, composes a migration callback
/// that drives the existing `RunService`, and hands everything off to
/// `SmokeRunner` for orchestration.
final class SmokeCommandHandler {
  SmokeCommandHandler({
    required this.logger,
    required this.output,
  });

  final ConsoleLogger logger;
  final ConsoleOutput output;

  Future<int> run(
    SmokeCommandOptions smoke, {
    String? cwd,
    Map<String, String>? env,
    String? homeDir,
    RunService? runServiceOverride,
    HttpClientHelper? httpOverride,
  }) async {
    final Map<String, dynamic> settingsPayload = SettingsManager.loadEffectiveSettings(
      cwd: cwd,
      env: env,
      homeDir: homeDir,
    );
    final String settingsProfile = SettingsManager.resolveProfileName(settingsPayload, smoke.settingsProfile);

    final String sourceToken = _resolveToken(
      settingsPayload: settingsPayload,
      settingsProfile: settingsProfile,
      provider: smoke.sourceProvider,
      sideEnvName: defaultSourceTokenEnv,
      env: env,
    );
    if (sourceToken.isEmpty) {
      logger.error(
        'No source token available for provider "${smoke.sourceProvider}". '
        'Run `gfrm settings set-token-env` or set the relevant env var.',
      );
      return 1;
    }

    final String targetToken = _resolveToken(
      settingsPayload: settingsPayload,
      settingsProfile: settingsProfile,
      provider: smoke.targetProvider,
      sideEnvName: defaultTargetTokenEnv,
      env: env,
    );
    if (targetToken.isEmpty) {
      logger.error(
        'No target token available for provider "${smoke.targetProvider}". '
        'Run `gfrm settings set-token-env` or set the relevant env var.',
      );
      return 1;
    }

    final RepoCoordinates sourceCoords;
    try {
      sourceCoords = parseRepoUrl(smoke.sourceUrl);
      // Validate target URL up-front; we do not need the coords for the
      // source-side FixtureTrigger, but a bad target URL should fail fast.
      parseRepoUrl(smoke.targetUrl);
    } catch (exc) {
      logger.error('Invalid forge URL: $exc');
      return 1;
    }

    final HttpClientHelper http = httpOverride ?? HttpClientHelper();
    final FixtureTrigger sourceTrigger = _buildTrigger(
      provider: smoke.sourceProvider,
      coords: sourceCoords,
      token: sourceToken,
      http: http,
      pollInterval: Duration(seconds: smoke.pollIntervalSeconds),
      pollTimeout: Duration(seconds: smoke.pollTimeoutSeconds),
    );

    final Directory resultsRoot = Directory(
      smoke.workdir.isNotEmpty ? smoke.workdir : '${Directory.current.path}/.tmp/smoke',
    );
    resultsRoot.createSync(recursive: true);

    final RunService runService = runServiceOverride ?? RunService(logger: logger);

    Future<Directory> migrate() async {
      final RuntimeOptions options = RuntimeOptions(
        commandName: commandMigrate,
        sourceProvider: smoke.sourceProvider,
        sourceUrl: smoke.sourceUrl,
        sourceToken: sourceToken,
        targetProvider: smoke.targetProvider,
        targetUrl: smoke.targetUrl,
        targetToken: targetToken,
        migrationOrder: '${smoke.sourceProvider}-to-${smoke.targetProvider}',
        skipTagMigration: false,
        skipReleaseMigration: false,
        skipReleaseAssetMigration: false,
        fromTag: '',
        toTag: '',
        dryRun: false,
        nonInteractive: true,
        workdir: resultsRoot.path,
        logFile: '',
        loadSession: false,
        saveSession: false,
        resumeSession: false,
        sessionFile: '',
        sessionTokenMode: 'env',
        sessionSourceTokenEnv: defaultSourceTokenEnv,
        sessionTargetTokenEnv: defaultTargetTokenEnv,
        settingsProfile: settingsProfile,
        downloadWorkers: 4,
        releaseWorkers: 1,
        checkpointFile: '',
        tagsFile: '',
        noBanner: true,
        quiet: smoke.quiet,
        jsonOutput: smoke.jsonOutput,
        progressBar: false,
        demoMode: false,
        demoReleases: 5,
        demoSleepSeconds: 1.0,
      );

      final RunRequest request = CliRuntimeSupport.buildRunRequest(options);
      final RunResult result = await runService.run(request);

      if (!result.isSuccess) {
        throw MigrationPhaseError(
          'Migration failed with exit code ${result.exitCode}. See ${result.summaryPath}',
        );
      }

      return Directory(result.runWorkdirPath);
    }

    final SmokeRunner smokeRunner = SmokeRunner(
      options: smoke,
      logger: logger,
      sourceTrigger: sourceTrigger,
      migrate: migrate,
      validator: const ArtifactValidator(),
    );

    final SmokeResult result = await smokeRunner.run();
    return result.exitCode;
  }

  FixtureTrigger _buildTrigger({
    required String provider,
    required RepoCoordinates coords,
    required String token,
    required HttpClientHelper http,
    required Duration pollInterval,
    required Duration pollTimeout,
  }) {
    return switch (provider) {
      'github' => GitHubFixtureTrigger(
          http: http,
          coords: coords,
          token: token,
          pollInterval: pollInterval,
          pollTimeout: pollTimeout,
        ),
      'gitlab' => GitLabFixtureTrigger(
          http: http,
          coords: coords,
          token: token,
          pollInterval: pollInterval,
          pollTimeout: pollTimeout,
        ),
      'bitbucket' => BitbucketFixtureTrigger(
          http: http,
          coords: coords,
          token: token,
          pollInterval: pollInterval,
          pollTimeout: pollTimeout,
        ),
      _ => throw MigrationPhaseError('Unknown provider: $provider'),
    };
  }

  String _resolveToken({
    required Map<String, dynamic> settingsPayload,
    required String settingsProfile,
    required String provider,
    required String sideEnvName,
    required Map<String, String>? env,
  }) {
    final String fromSettings = SettingsManager.tokenFromSettings(
      settingsPayload,
      settingsProfile,
      provider,
      env: env,
    );
    if (fromSettings.isNotEmpty) {
      return fromSettings;
    }

    return SettingsManager.tokenFromEnvAliases(
      provider,
      sideEnvName: sideEnvName,
      env: env,
    );
  }
}
