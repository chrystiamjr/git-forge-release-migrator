import 'dart:io';

import '../core/adapters/provider_adapter.dart';
import '../core/exceptions/migration_phase_error.dart';
import '../core/logging.dart';
import '../core/session_store.dart';
import '../core/settings.dart';
import '../migrations/engine.dart';
import '../migrations/migration_execution_result.dart';
import '../migrations/summary.dart';
import '../models/migration_context.dart';
import '../models/runtime_options.dart';
import '../providers/registry.dart';
import 'preflight_check.dart';
import 'preflight_service.dart';
import 'run_failure.dart';
import 'run_request.dart';
import 'run_result.dart';

typedef ProviderRegistryFactory = ProviderRegistry Function(RuntimeOptions options);

class RunService {
  RunService({
    required this.logger,
    ProviderRegistryFactory? registryFactory,
    PreflightService? preflightService,
  })  : _registryFactory = registryFactory ?? _defaultRegistryFactory,
        _preflightService = preflightService ?? PreflightService();

  static const String noReleasesFoundMessage = 'No releases found in selected range';
  static const String partialFailureMessage = 'Migration finished with failures';

  final ConsoleLogger logger;
  final ProviderRegistryFactory _registryFactory;
  final PreflightService _preflightService;

  Future<RunResult> run(RunRequest request) async {
    final _PreparedRun prepared = _prepareRun(request.options);
    final RuntimeOptions options = prepared.options;
    final String summaryPath = '${prepared.runWorkdir.path}/summary.json';
    final String failedTagsPath = '${prepared.runWorkdir.path}/failed-tags.txt';
    List<PreflightCheck> preflightChecks = const <PreflightCheck>[];

    try {
      preflightChecks = _preflightService.evaluateCommand(options);
      if (PreflightService.hasBlockingErrors(preflightChecks)) {
        return _preflightFailureResult(
          prepared: prepared,
          checks: preflightChecks,
        );
      }

      final ProviderRegistry registry = _registryFactory(options);
      preflightChecks = <PreflightCheck>[
        ...preflightChecks,
        ..._preflightService.evaluateStartup(options, registry),
      ];
      if (PreflightService.hasBlockingErrors(preflightChecks)) {
        return _preflightFailureResult(
          prepared: prepared,
          checks: preflightChecks,
        );
      }

      _prepareRunDirectories(prepared);

      final ProviderAdapter sourceAdapter = registry.get(options.sourceProvider);
      final ProviderAdapter targetAdapter = registry.get(options.targetProvider);
      final ProviderRef sourceRef = sourceAdapter.parseUrl(options.sourceUrl);
      final ProviderRef targetRef = targetAdapter.parseUrl(options.targetUrl);

      _saveSessionIfEnabled(options, logger);
      _logRuntimeHeader(options, sourceRef, targetRef, prepared.resultsRoot, prepared.runWorkdir, logger);

      final MigrationEngine engine = MigrationEngine(registry: registry, logger: logger);
      final MigrationContext context = await engine.createContext(options, sourceRef, targetRef);
      final MigrationExecutionResult execution = await engine.execute(context);

      try {
        await SummaryWriter.writeSummary(
          logger: logger,
          options: options,
          sourceRef: sourceRef,
          targetRef: targetRef,
          logPath: context.logPath,
          checkpointPath: context.checkpointPath,
          workdir: context.workdir,
          failedTags: context.failedTags,
          tagCounts: execution.tagCounts,
          releaseCounts: execution.releaseCounts,
        );
      } catch (exc) {
        return _failureResult(
          status: RunStatus.runtimeFailure,
          failure: RunFailure(
            scope: RunFailure.scopeArtifactFinalization,
            code: 'artifact-finalization-failed',
            message: exc.toString(),
            retryable: false,
          ),
          prepared: prepared,
          retryCommand: '',
          preflightChecks: preflightChecks,
        );
      }

      if (execution.tagCounts.failed > 0 || execution.releaseCounts.failed > 0) {
        return _failureResult(
          status: RunStatus.partialFailure,
          failure: RunFailure(
            scope: RunFailure.scopeExecution,
            code: 'migration-partial-failure',
            message: MigrationPhaseError(partialFailureMessage).toString(),
            retryable: true,
          ),
          prepared: prepared,
          retryCommand: SummaryWriter.buildRetryCommand(options, File(failedTagsPath)),
          preflightChecks: preflightChecks,
        );
      }

      return RunResult(
        status: RunStatus.success,
        exitCode: 0,
        resultsRootPath: prepared.resultsRoot.path,
        runWorkdirPath: prepared.runWorkdir.path,
        logPath: options.logFile,
        checkpointPath: options.effectiveCheckpointFile(),
        summaryPath: summaryPath,
        failedTagsPath: failedTagsPath,
        retryCommand: '',
        preflightChecks: preflightChecks,
        failures: const <RunFailure>[],
      );
    } on ArgumentError catch (exc) {
      return _failureResult(
        status: RunStatus.validationFailure,
        failure: RunFailure(
          scope: RunFailure.scopeValidation,
          code: 'invalid-request',
          message: exc.toString(),
          retryable: false,
        ),
        prepared: prepared,
        retryCommand: '',
        preflightChecks: preflightChecks,
      );
    } on MigrationPhaseError catch (exc) {
      final bool isValidationFailure = exc.message == noReleasesFoundMessage;
      return _failureResult(
        status: isValidationFailure ? RunStatus.validationFailure : RunStatus.runtimeFailure,
        failure: RunFailure(
          scope: isValidationFailure ? RunFailure.scopeValidation : RunFailure.scopeExecution,
          code: isValidationFailure ? 'validation-failed' : 'migration-failed',
          message: exc.toString(),
          retryable: !isValidationFailure,
        ),
        prepared: prepared,
        retryCommand: '',
        preflightChecks: preflightChecks,
      );
    } catch (exc) {
      return _failureResult(
        status: RunStatus.runtimeFailure,
        failure: RunFailure(
          scope: RunFailure.scopeExecution,
          code: 'runtime-failed',
          message: exc.toString(),
          retryable: true,
        ),
        prepared: prepared,
        retryCommand: '',
        preflightChecks: preflightChecks,
      );
    } finally {
      logger.stopSpinner();
    }
  }

  RunResult _failureResult({
    required RunStatus status,
    required RunFailure failure,
    required _PreparedRun prepared,
    required String retryCommand,
    required List<PreflightCheck> preflightChecks,
  }) {
    final RuntimeOptions options = prepared.options;
    return RunResult(
      status: status,
      exitCode: 1,
      resultsRootPath: prepared.resultsRoot.path,
      runWorkdirPath: prepared.runWorkdir.path,
      logPath: options.logFile,
      checkpointPath: options.effectiveCheckpointFile(),
      summaryPath: '${prepared.runWorkdir.path}/summary.json',
      failedTagsPath: '${prepared.runWorkdir.path}/failed-tags.txt',
      retryCommand: retryCommand,
      preflightChecks: preflightChecks,
      failures: <RunFailure>[failure],
    );
  }

  RunResult _preflightFailureResult({
    required _PreparedRun prepared,
    required List<PreflightCheck> checks,
  }) {
    final PreflightCheck? blocking = PreflightService.firstBlockingError(checks);
    final PreflightCheck resolved = blocking ??
        const PreflightCheck(
          status: PreflightCheckStatus.error,
          code: 'preflight-failed',
          message: 'Preflight failed before migration start.',
        );

    return _failureResult(
      status: RunStatus.validationFailure,
      failure: RunFailure(
        scope: RunFailure.scopeValidation,
        code: resolved.code,
        message: resolved.message,
        retryable: false,
      ),
      prepared: prepared,
      retryCommand: '',
      preflightChecks: checks,
    );
  }

  static ProviderRegistry _defaultRegistryFactory(RuntimeOptions options) {
    final Map<String, dynamic> settingsPayload = SettingsManager.loadEffectiveSettings();
    final HttpConfig httpConfig = SettingsManager.httpConfigFromSettings(settingsPayload, options.settingsProfile);
    return ProviderRegistry.defaults(config: httpConfig);
  }
}

Directory _allocateRunWorkdir(Directory baseDir) {
  final DateTime now = DateTime.now().toUtc();
  final String runId =
      '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';

  Directory candidate = Directory('${baseDir.path}/$runId');
  if (!candidate.existsSync()) {
    return candidate;
  }

  int index = 2;
  while (true) {
    candidate = Directory('${baseDir.path}/$runId-$index');
    if (!candidate.existsSync()) {
      return candidate;
    }

    index += 1;
  }
}

final class _PreparedRun {
  _PreparedRun({
    required this.options,
    required this.resultsRoot,
    required this.runWorkdir,
  });

  final RuntimeOptions options;
  final Directory resultsRoot;
  final Directory runWorkdir;
}

_PreparedRun _prepareRun(RuntimeOptions options) {
  final Directory resultsRoot = Directory(options.effectiveWorkdir());
  final Directory runWorkdir = _allocateRunWorkdir(resultsRoot);

  final RuntimeOptions withWorkdir = options.copyWith(
    workdir: runWorkdir.path,
    logFile: options.logFile.isEmpty ? '${runWorkdir.path}/migration-log.jsonl' : options.logFile,
    checkpointFile:
        options.checkpointFile.isEmpty ? '${resultsRoot.path}/checkpoints/state.jsonl' : options.checkpointFile,
  );

  return _PreparedRun(
    options: withWorkdir,
    resultsRoot: resultsRoot,
    runWorkdir: runWorkdir,
  );
}

void _prepareRunDirectories(_PreparedRun prepared) {
  if (!prepared.resultsRoot.existsSync()) {
    prepared.resultsRoot.createSync(recursive: true);
  }

  if (!prepared.runWorkdir.existsSync()) {
    prepared.runWorkdir.createSync(recursive: true);
  }
}

void _saveSessionIfEnabled(RuntimeOptions options, ConsoleLogger logger) {
  if (!options.saveSession && !options.resumeSession) {
    return;
  }

  final String sessionFile = options.effectiveSessionFile();
  SessionStore.saveSession(sessionFile, options.toSessionPayload());
  logger.info('Session saved to $sessionFile');
  if (options.sessionTokenMode == 'plain') {
    logger.warn('Session file stores tokens in plain text. Keep file permissions restricted.');
  } else {
    logger.info('Session stores token env references only. Keep those environment variables available for resume.');
  }
}

void _logRuntimeHeader(
  RuntimeOptions options,
  ProviderRef sourceRef,
  ProviderRef targetRef,
  Directory resultsRoot,
  Directory runWorkdir,
  ConsoleLogger logger,
) {
  logger.info('Dart runtime loaded');
  logger.info('  Command: ${options.commandName}');
  logger.info('  Source: ${options.sourceProvider} (${sourceRef.resource})');
  logger.info('  Target: ${options.targetProvider} (${targetRef.resource})');
  logger.info('  Order: ${options.migrationOrder}');
  logger.info(
    '  Tag range: ${options.fromTag.isEmpty ? '<start>' : options.fromTag} -> ${options.toTag.isEmpty ? '<end>' : options.toTag}',
  );
  logger.info('  Dry-run: ${options.dryRun}');
  logger.info('  Skip tags: ${options.skipTagMigration}');
  logger.info('  Download workers: ${options.downloadWorkers}');
  logger.info('  Release workers: ${options.releaseWorkers}');
  logger.info('  Session token mode: ${options.sessionTokenMode}');
  if (options.settingsProfile.isNotEmpty) {
    logger.info('  Settings profile: ${options.settingsProfile}');
  }
  logger.info('  Checkpoint file: ${options.effectiveCheckpointFile()}');
  logger.info('  Results root: ${resultsRoot.path}');
  logger.info('  Run workdir: ${runWorkdir.path}');
  if (options.tagsFile.isNotEmpty) {
    logger.info('  Tags file: ${options.tagsFile}');
  }
}
