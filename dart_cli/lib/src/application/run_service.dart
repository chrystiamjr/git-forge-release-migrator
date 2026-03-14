import 'dart:io';

import '../core/adapters/provider_adapter.dart';
import '../core/exceptions/migration_phase_error.dart';
import '../core/logging.dart';
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
import 'run_paths.dart';
import 'run_request.dart';
import 'run_result.dart';
import 'run_runtime.dart';

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
    final PreparedRun prepared = prepareRun(request.options);
    final RuntimeOptions options = prepared.options;
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

      prepareRunDirectories(prepared);

      final ProviderAdapter sourceAdapter = registry.get(options.sourceProvider);
      final ProviderAdapter targetAdapter = registry.get(options.targetProvider);
      final RunRuntime runtime = RunRuntime.initialize(
        options: options,
        sourceAdapter: sourceAdapter,
        targetAdapter: targetAdapter,
        prepared: prepared,
        logger: logger,
      );
      final _ExecutionOutcome outcome = await _executeMigration(
        prepared: prepared,
        registry: registry,
        runtime: runtime,
        preflightChecks: preflightChecks,
      );
      if (outcome.result != null) {
        return outcome.result!;
      }

      final MigrationExecutionResult execution = outcome.execution!;

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
          retryCommand: SummaryWriter.buildRetryCommand(options, File('${prepared.runWorkdir.path}/failed-tags.txt')),
          preflightChecks: preflightChecks,
        );
      }

      return _successResult(prepared: prepared, preflightChecks: preflightChecks);
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
    required PreparedRun prepared,
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
    required PreparedRun prepared,
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

  Future<_ExecutionOutcome> _executeMigration({
    required PreparedRun prepared,
    required ProviderRegistry registry,
    required RunRuntime runtime,
    required List<PreflightCheck> preflightChecks,
  }) async {
    final MigrationEngine engine = MigrationEngine(registry: registry, logger: logger);
    final MigrationContext context = await engine.createContext(runtime.options, runtime.sourceRef, runtime.targetRef);
    final MigrationExecutionResult execution = await engine.execute(context);

    try {
      await SummaryWriter.writeSummary(
        logger: logger,
        options: runtime.options,
        sourceRef: runtime.sourceRef,
        targetRef: runtime.targetRef,
        logPath: context.logPath,
        checkpointPath: context.checkpointPath,
        workdir: context.workdir,
        failedTags: context.failedTags,
        tagCounts: execution.tagCounts,
        releaseCounts: execution.releaseCounts,
      );
    } catch (exc) {
      return _ExecutionOutcome(
        result: _failureResult(
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
        ),
      );
    }

    return _ExecutionOutcome(execution: execution);
  }

  RunResult _successResult({
    required PreparedRun prepared,
    required List<PreflightCheck> preflightChecks,
  }) {
    final RuntimeOptions options = prepared.options;
    return RunResult(
      status: RunStatus.success,
      exitCode: 0,
      resultsRootPath: prepared.resultsRoot.path,
      runWorkdirPath: prepared.runWorkdir.path,
      logPath: options.logFile,
      checkpointPath: options.effectiveCheckpointFile(),
      summaryPath: '${prepared.runWorkdir.path}/summary.json',
      failedTagsPath: '${prepared.runWorkdir.path}/failed-tags.txt',
      retryCommand: '',
      preflightChecks: preflightChecks,
      failures: const <RunFailure>[],
    );
  }
}

final class _ExecutionOutcome {
  const _ExecutionOutcome({
    this.execution,
    this.result,
  });

  final MigrationExecutionResult? execution;
  final RunResult? result;
}
