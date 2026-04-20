import 'dart:io';

import '../core/adapters/provider_adapter.dart';
import '../core/exceptions/migration_phase_error.dart';
import '../core/jsonl.dart';
import '../core/logging.dart';
import '../core/types/phase.dart';
import '../core/settings.dart';
import '../migrations/engine.dart';
import '../migrations/migration_execution_result.dart';
import '../migrations/selection.dart';
import '../migrations/summary.dart';
import '../models/migration_context.dart';
import '../models/runtime_options.dart';
import '../providers/registry.dart';
import '../runtime_events/runtime_event_emitter.dart';
import '../runtime_events/runtime_event_sink_dispatch_exception.dart';
import '../runtime_events/runtime_event_type.dart';
import '../runtime_events/serial_runtime_event_publisher.dart';
import 'missing_target_commit.dart';
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
    final RuntimeEventEmitter runtimeEventEmitter = RuntimeEventEmitter(
      publisher: SerialRuntimeEventPublisher(
        runId: _runIdFromWorkdir(prepared.runWorkdir.path),
      ),
      sinks: request.runtimeEventSinks,
      onSinkFailure: (RuntimeEventSinkDispatchException failure) {
        logger.warn('Runtime event sink "${failure.sinkId}" failed: ${failure.cause}');
      },
    );
    List<PreflightCheck> preflightChecks = const <PreflightCheck>[];

    try {
      _emitRunStarted(runtimeEventEmitter, options);
      preflightChecks = _preflightService.evaluateCommand(options);
      if (PreflightService.hasBlockingErrors(preflightChecks)) {
        _emitPreflightCompleted(runtimeEventEmitter, preflightChecks);
        _emitRunFailed(
          runtimeEventEmitter,
          code: _resolvedPreflightCode(preflightChecks),
          message: _resolvedPreflightMessage(preflightChecks),
          retryable: false,
          phase: 'preflight',
        );
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
        _emitPreflightCompleted(runtimeEventEmitter, preflightChecks);
        _emitRunFailed(
          runtimeEventEmitter,
          code: _resolvedPreflightCode(preflightChecks),
          message: _resolvedPreflightMessage(preflightChecks),
          retryable: false,
          phase: 'preflight',
        );
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
      final MigrationEngine engine = MigrationEngine(registry: registry, logger: logger);
      final MigrationContext context = await engine.createContextWithEmitter(
        runtime.options,
        runtime.sourceRef,
        runtime.targetRef,
        runtimeEventEmitter: runtimeEventEmitter,
      );
      final List<MissingTargetCommit> missingTargetCommits = await _preflightService.findMissingTargetCommits(context);
      if (missingTargetCommits.isNotEmpty) {
        final PreflightCheck check = _preflightService.buildMissingTargetCommitCheck(context, missingTargetCommits);
        preflightChecks = <PreflightCheck>[
          ...preflightChecks,
          check,
        ];
        _emitPreflightCompleted(runtimeEventEmitter, preflightChecks);
        return await _contextPreflightFailureResult(
          prepared: prepared,
          checks: preflightChecks,
          context: context,
          missingTargetCommits: missingTargetCommits,
          runtimeEventEmitter: runtimeEventEmitter,
        );
      }
      _emitPreflightCompleted(runtimeEventEmitter, preflightChecks);
      final _ExecutionOutcome outcome = await _executeMigration(
        prepared: prepared,
        engine: engine,
        context: context,
        runtime: runtime,
        preflightChecks: preflightChecks,
        runtimeEventEmitter: runtimeEventEmitter,
      );
      if (outcome.result != null) {
        return outcome.result!;
      }

      final MigrationExecutionResult execution = outcome.execution!;
      return _mapExecutionResultToRunResult(
        execution,
        context,
        options,
        prepared,
        runtimeEventEmitter,
        preflightChecks,
      );
    } on RuntimeEventSinkDispatchException catch (exc) {
      _emitRunFailedBestEffort(
        runtimeEventEmitter,
        code: 'runtime-event-sink-failed',
        message: exc.toString(),
        retryable: false,
        phase: 'runtime_event_sink',
      );
      return _failureResult(
        status: RunStatus.runtimeFailure,
        failure: RunFailure(
          scope: RunFailure.scopeExecution,
          code: 'runtime-event-sink-failed',
          message: exc.toString(),
          retryable: false,
          phase: 'runtime_event_sink',
        ),
        prepared: prepared,
        retryCommand: '',
        preflightChecks: preflightChecks,
      );
    } on ArgumentError catch (exc) {
      _emitRunFailed(
        runtimeEventEmitter,
        code: 'invalid-request',
        message: exc.toString(),
        retryable: false,
        phase: 'validation',
      );
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
      _emitRunFailed(
        runtimeEventEmitter,
        code: isValidationFailure ? 'validation-failed' : 'migration-failed',
        message: exc.toString(),
        retryable: !isValidationFailure,
        phase: isValidationFailure ? 'validation' : 'execution',
      );
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
      _emitRunFailed(
        runtimeEventEmitter,
        code: 'runtime-failed',
        message: exc.toString(),
        retryable: true,
        phase: 'execution',
      );
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

  RunResult _mapExecutionResultToRunResult(
    MigrationExecutionResult execution,
    MigrationContext context,
    RuntimeOptions options,
    PreparedRun prepared,
    RuntimeEventEmitter runtimeEventEmitter,
    List<PreflightCheck> preflightChecks,
  ) {
    if (execution.tagCounts.failed > 0 || execution.releaseCounts.failed > 0) {
      _emitArtifactEvents(
        runtimeEventEmitter,
        prepared,
        logPath: context.logPath,
      );
      _emitRunCompleted(
        runtimeEventEmitter,
        prepared,
        status: 'partial_failure',
        retryCommand: SummaryWriter.buildRetryCommand(options, File('${prepared.runWorkdir.path}/failed-tags.txt')),
        failedTagCount: context.failedTags.length,
        totalTags: context.selectedTags.length,
      );
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

    _emitArtifactEvents(
      runtimeEventEmitter,
      prepared,
      logPath: context.logPath,
    );
    _emitRunCompleted(
      runtimeEventEmitter,
      prepared,
      status: 'success',
      retryCommand: '',
      failedTagCount: context.failedTags.length,
      totalTags: context.selectedTags.length,
    );
    return _successResult(prepared: prepared, preflightChecks: preflightChecks);
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

  Future<RunResult> _contextPreflightFailureResult({
    required PreparedRun prepared,
    required List<PreflightCheck> checks,
    required MigrationContext context,
    required List<MissingTargetCommit> missingTargetCommits,
    required RuntimeEventEmitter runtimeEventEmitter,
  }) async {
    final PreflightCheck resolved = checks.last;
    final TagMigrationCounts tagCounts = TagMigrationCounts()..failed = missingTargetCommits.length;
    final ReleaseMigrationCounts releaseCounts = ReleaseMigrationCounts();
    for (final MissingTargetCommit item in missingTargetCommits) {
      context.failedTags.add(item.tag);
      JsonlLogWriter.appendLog(
        context.logPath,
        status: 'tag_failed',
        tag: item.tag,
        message:
            'Target ${SelectionService.capitalizeProvider(context.options.targetProvider)} is missing commit ${item.commitSha}',
        assetCount: 0,
        durationMs: 0,
        dryRun: false,
      );
    }

    try {
      await SummaryWriter.writeSummary(
        logger: logger,
        options: context.options,
        sourceRef: context.sourceRef,
        targetRef: context.targetRef,
        logPath: context.logPath,
        checkpointPath: context.checkpointPath,
        workdir: context.workdir,
        failedTags: context.failedTags,
        tagCounts: tagCounts,
        releaseCounts: releaseCounts,
      );
    } catch (exc) {
      _emitRunFailed(
        runtimeEventEmitter,
        code: 'artifact-finalization-failed',
        message: exc.toString(),
        retryable: false,
        phase: 'artifact_finalization',
      );
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
        preflightChecks: checks,
      );
    }

    _emitArtifactEvents(
      runtimeEventEmitter,
      prepared,
      logPath: context.logPath,
    );
    _emitRunFailed(
      runtimeEventEmitter,
      code: resolved.code,
      message: resolved.message,
      retryable: true,
      phase: 'preflight',
    );
    return _failureResult(
      status: RunStatus.validationFailure,
      failure: RunFailure(
        scope: RunFailure.scopeValidation,
        code: resolved.code,
        message: resolved.message,
        retryable: true,
      ),
      prepared: prepared,
      retryCommand: SummaryWriter.buildRetryCommand(
        context.options,
        File('${context.workdir.path}/failed-tags.txt'),
      ),
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
    required MigrationEngine engine,
    required MigrationContext context,
    required RunRuntime runtime,
    required List<PreflightCheck> preflightChecks,
    required RuntimeEventEmitter runtimeEventEmitter,
  }) async {
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
      _emitRunFailed(
        runtimeEventEmitter,
        code: 'artifact-finalization-failed',
        message: exc.toString(),
        retryable: false,
        phase: 'artifact_finalization',
      );
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

  void _emitRunStarted(RuntimeEventEmitter runtimeEventEmitter, RuntimeOptions options) {
    final Map<String, dynamic> payload = <String, dynamic>{
      'source_provider': options.sourceProvider,
      'target_provider': options.targetProvider,
      'mode': options.commandName,
      'dry_run': options.dryRun,
      'skip_tags': options.skipTagMigration,
    };
    if (options.settingsProfile.isNotEmpty) {
      payload['settings_profile'] = options.settingsProfile;
    }

    runtimeEventEmitter.emit(
      eventType: RuntimeEventType.runStarted,
      payload: payload,
    );
  }

  void _emitPreflightCompleted(
    RuntimeEventEmitter runtimeEventEmitter,
    List<PreflightCheck> checks,
  ) {
    final int blockingCount = checks.where((PreflightCheck check) => check.status == PreflightCheckStatus.error).length;
    final int warningCount =
        checks.where((PreflightCheck check) => check.status == PreflightCheckStatus.warning).length;

    runtimeEventEmitter.emit(
      eventType: RuntimeEventType.preflightCompleted,
      payload: <String, dynamic>{
        'status': blockingCount > 0 ? 'failed' : 'ok',
        'check_count': checks.length,
        'blocking_count': blockingCount,
        'warning_count': warningCount,
      },
    );
  }

  void _emitArtifactEvents(
    RuntimeEventEmitter runtimeEventEmitter,
    PreparedRun prepared, {
    required String logPath,
  }) {
    runtimeEventEmitter.emit(
      eventType: RuntimeEventType.artifactWritten,
      payload: <String, dynamic>{
        'artifact_type': 'migration_log',
        'path': logPath,
      },
    );
    runtimeEventEmitter.emit(
      eventType: RuntimeEventType.artifactWritten,
      payload: <String, dynamic>{
        'artifact_type': 'failed_tags',
        'path': '${prepared.runWorkdir.path}/failed-tags.txt',
      },
    );
    runtimeEventEmitter.emit(
      eventType: RuntimeEventType.artifactWritten,
      payload: <String, dynamic>{
        'artifact_type': 'summary',
        'path': '${prepared.runWorkdir.path}/summary.json',
        'schema_version': 2,
      },
    );
  }

  void _emitRunCompleted(
    RuntimeEventEmitter runtimeEventEmitter,
    PreparedRun prepared, {
    required String status,
    required String retryCommand,
    required int failedTagCount,
    required int totalTags,
  }) {
    final Map<String, dynamic> payload = <String, dynamic>{
      'status': status,
      'summary_path': '${prepared.runWorkdir.path}/summary.json',
      'failed_tags_path': '${prepared.runWorkdir.path}/failed-tags.txt',
      'total_tags': totalTags,
      'failed_tags': failedTagCount,
    };
    if (retryCommand.isNotEmpty) {
      payload['retry_command'] = retryCommand;
    }

    runtimeEventEmitter.emit(
      eventType: RuntimeEventType.runCompleted,
      payload: payload,
    );
  }

  void _emitRunFailed(
    RuntimeEventEmitter runtimeEventEmitter, {
    required String code,
    required String message,
    required bool retryable,
    String? phase,
  }) {
    final Map<String, dynamic> payload = <String, dynamic>{
      'code': code,
      'message': message,
      'retryable': retryable,
    };
    if (phase != null && phase.isNotEmpty) {
      payload['phase'] = phase;
    }

    runtimeEventEmitter.emit(
      eventType: RuntimeEventType.runFailed,
      payload: payload,
    );
  }

  void _emitRunFailedBestEffort(
    RuntimeEventEmitter runtimeEventEmitter, {
    required String code,
    required String message,
    required bool retryable,
    String? phase,
  }) {
    final Map<String, dynamic> payload = <String, dynamic>{
      'code': code,
      'message': message,
      'retryable': retryable,
    };
    if (phase != null && phase.isNotEmpty) {
      payload['phase'] = phase;
    }

    runtimeEventEmitter.emitBestEffort(
      eventType: RuntimeEventType.runFailed,
      payload: payload,
    );
  }

  String _resolvedPreflightCode(List<PreflightCheck> checks) {
    final PreflightCheck? blocking = PreflightService.firstBlockingError(checks);
    return blocking?.code ?? 'preflight-failed';
  }

  String _resolvedPreflightMessage(List<PreflightCheck> checks) {
    final PreflightCheck? blocking = PreflightService.firstBlockingError(checks);
    return blocking?.message ?? 'Preflight failed before migration start.';
  }

  static String _runIdFromWorkdir(String workdirPath) {
    final String normalizedPath =
        workdirPath.endsWith(Platform.pathSeparator) ? workdirPath.substring(0, workdirPath.length - 1) : workdirPath;
    return normalizedPath.split(Platform.pathSeparator).last;
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
