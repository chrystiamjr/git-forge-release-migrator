// ignore_for_file: implementation_imports

import 'dart:async';

import 'package:gfrm_dart/src/application/preflight_check.dart';
import 'package:gfrm_dart/src/application/preflight_service.dart';
import 'package:gfrm_dart/src/application/run_request.dart';
import 'package:gfrm_dart/src/application/run_result.dart';
import 'package:gfrm_dart/src/application/run_service.dart';
import 'package:gfrm_dart/src/core/logging.dart';
import 'package:gfrm_dart/src/core/settings.dart';
import 'package:gfrm_dart/src/models/runtime_options.dart';
import 'package:gfrm_dart/src/providers/registry.dart';
import 'package:gfrm_dart/src/runtime_events/runtime_event_sink.dart';

import 'package:gfrm_gui/src/application/run/models/desktop_preflight_request.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_preflight_summary.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_action_result.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_completion.dart';
import 'package:gfrm_gui/src/application/run/contracts/desktop_run_controller.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_failure_summary.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_resume_request.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_session.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_snapshot.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_start_request.dart';
import 'package:gfrm_gui/src/runtime/run/mappers/map_desktop_preflight_request_to_runtime_options.dart';
import 'package:gfrm_gui/src/runtime/run/mappers/map_desktop_run_failure_to_summary.dart';
import 'package:gfrm_gui/src/runtime/run/mappers/map_desktop_run_resume_request_to_run_request.dart';
import 'package:gfrm_gui/src/runtime/run/mappers/map_desktop_run_start_request_to_run_request.dart';
import 'package:gfrm_gui/src/runtime/run/mappers/map_preflight_checks_to_summary.dart';
import 'package:gfrm_gui/src/runtime/run/mappers/map_run_result_to_completion.dart';
import 'package:gfrm_gui/src/runtime/run/mappers/map_run_state_to_snapshot.dart';
import 'package:gfrm_gui/src/runtime/run/services/runtime_log_event_sink.dart';
import 'package:gfrm_gui/src/runtime/run/services/runtime_run_state_sink.dart';

final class GfrmDesktopRunController implements DesktopRunController {
  GfrmDesktopRunController({
    required ConsoleLogger logger,
    required RunService runService,
    required PreflightService preflightService,
    required ProviderRegistryFactory registryFactory,
  }) : _logger = logger,
       _runService = runService,
       _preflightService = preflightService,
       _registryFactory = registryFactory;

  factory GfrmDesktopRunController.defaults() {
    final ConsoleLogger logger = ConsoleLogger(quiet: true, jsonOutput: false, silent: true);
    final PreflightService preflightService = PreflightService();
    final ProviderRegistryFactory registryFactory = _defaultGuiRegistryFactory;

    return GfrmDesktopRunController(
      logger: logger,
      runService: RunService(logger: logger, registryFactory: registryFactory, preflightService: preflightService),
      preflightService: preflightService,
      registryFactory: registryFactory,
    );
  }

  final ConsoleLogger _logger;
  final RunService _runService;
  final PreflightService _preflightService;
  final ProviderRegistryFactory _registryFactory;
  final StreamController<DesktopRunSnapshot> _snapshotController = StreamController<DesktopRunSnapshot>.broadcast();
  final StreamController<String> _logController = StreamController<String>.broadcast();

  DesktopRunSnapshot _currentSnapshot = const DesktopRunSnapshot.initial();
  bool _runInFlight = false;
  int _nextSessionId = 0;
  DateTime? _runStartedAt;

  @override
  DesktopRunSnapshot get currentSnapshot => _currentSnapshot;

  @override
  Stream<DesktopRunSnapshot> get snapshots => _snapshotController.stream;

  @override
  Stream<String> get logStream => _logController.stream;

  @override
  Future<DesktopPreflightSummary> evaluatePreflight(DesktopPreflightRequest request) async {
    final RuntimeOptions options = mapDesktopPreflightRequestToRuntimeOptions(request);
    final List<PreflightCheck> commandChecks = _preflightService.evaluateCommand(options);
    if (PreflightService.hasBlockingErrors(commandChecks)) {
      return mapPreflightChecksToSummary(commandChecks);
    }

    final ProviderRegistry registry = _registryFactory(options);
    final List<PreflightCheck> startupChecks = _preflightService.evaluateStartup(options, registry);

    return mapPreflightChecksToSummary(<PreflightCheck>[...commandChecks, ...startupChecks]);
  }

  @override
  Future<DesktopRunSession> startRun(DesktopRunStartRequest request) {
    return _launchRun(runtimeRequest: mapDesktopRunStartRequestToRunRequest(request));
  }

  @override
  Future<DesktopRunSession> resumeRun(DesktopRunResumeRequest request) {
    return _launchRun(runtimeRequest: mapDesktopRunResumeRequestToRunRequest(request));
  }

  @override
  Future<DesktopRunActionResult> cancelActiveRun() async {
    return const DesktopRunActionResult(supported: false, message: 'Runtime cancel is not available yet.');
  }

  @override
  void dispose() {
    _snapshotController.close();
    _logController.close();
  }

  Future<DesktopRunSession> _launchRun({required RunRequest runtimeRequest}) async {
    if (_runInFlight) {
      throw StateError('A run is already in progress.');
    }

    final String sessionId = 'desktop-run-${++_nextSessionId}';
    final DesktopRunSnapshot initialSnapshot = DesktopRunSnapshot.initial(sessionId: sessionId);
    final Completer<DesktopRunCompletion> completer = Completer<DesktopRunCompletion>();

    _runInFlight = true;
    _currentSnapshot = initialSnapshot;
    _runStartedAt = DateTime.now();

    unawaited(
      Future<void>.microtask(
        () => _runInBackground(sessionId: sessionId, runtimeRequest: runtimeRequest, completer: completer),
      ),
    );

    return DesktopRunSession(sessionId: sessionId, initialSnapshot: initialSnapshot, completion: completer.future);
  }

  Future<void> _runInBackground({
    required String sessionId,
    required RunRequest runtimeRequest,
    required Completer<DesktopRunCompletion> completer,
  }) async {
    final RuntimeRunStateSink stateSink = RuntimeRunStateSink(
      onState: (state) {
        _emitSnapshot(mapRunStateToSnapshot(sessionId: sessionId, state: state));
      },
    );
    final RuntimeLogEventSink logSink = RuntimeLogEventSink(
      onLog: (line) {
        if (!_logController.isClosed) {
          _logController.add(line);
        }
      },
    );

    try {
      final RunResult result = await _runService.run(
        RunRequest(
          options: runtimeRequest.options,
          runtimeEventSinks: <RuntimeEventSink>[...runtimeRequest.runtimeEventSinks, stateSink, logSink],
        ),
      );

      final DesktopPreflightSummary preflight = mapPreflightChecksToSummary(result.preflightChecks);
      final DesktopRunFailureSummary? latestFailure = result.failures.isEmpty
          ? null
          : mapDesktopRunFailureToSummary(result.failures.first);
      final DesktopRunSnapshot finalSnapshot = _currentSnapshot.copyWith(
        preflight: preflight,
        artifacts: _currentSnapshot.artifacts.copyWith(
          summaryPath: result.summaryPath,
          failedTagsPath: result.failedTagsPath,
          migrationLogPath: result.logPath,
        ),
        latestFailure: latestFailure,
        completionStatus: switch (result.status) {
          RunStatus.success => 'success',
          RunStatus.partialFailure => 'partial_failure',
          RunStatus.validationFailure => 'validation_failure',
          RunStatus.runtimeFailure => 'runtime_failure',
        },
        retryCommand: result.retryCommand,
        canResume: result.retryCommand.trim().isNotEmpty || result.failures.any((failure) => failure.retryable),
      );

      _emitSnapshot(finalSnapshot);
      completer.complete(mapRunResultToCompletion(result: result, snapshot: _currentSnapshot));
    } catch (error, stackTrace) {
      _logger.error(error.toString());
      final DesktopRunSnapshot failedSnapshot = _currentSnapshot.copyWith(
        lifecycle: 'failed',
        latestFailure: DesktopRunFailureSummary(
          code: 'desktop-run-controller-error',
          message: error.toString(),
          retryable: false,
          phase: 'execution',
        ),
      );
      _emitSnapshot(failedSnapshot);
      completer.completeError(error, stackTrace);
    } finally {
      _runInFlight = false;
    }
  }

  void _emitSnapshot(DesktopRunSnapshot snapshot) {
    final DateTime? startedAt = _runStartedAt;
    final Duration elapsed = startedAt != null ? DateTime.now().difference(startedAt) : Duration.zero;
    final double progress = snapshot.progressPercent;

    Duration? remaining;
    if (progress >= 0.01 && progress < 1.0) {
      remaining = Duration(microseconds: (elapsed.inMicroseconds * (1.0 - progress) / progress).round());
    }

    final DesktopRunSnapshot timedSnapshot = snapshot.copyWith(elapsedTime: elapsed, estimatedRemainingTime: remaining);
    _currentSnapshot = timedSnapshot;
    if (!_snapshotController.isClosed) {
      _snapshotController.add(timedSnapshot);
    }
  }

  static ProviderRegistry _defaultGuiRegistryFactory(RuntimeOptions options) {
    final Map<String, dynamic> settingsPayload = SettingsManager.loadEffectiveSettings();
    final httpConfig = SettingsManager.httpConfigFromSettings(settingsPayload, options.settingsProfile);
    return ProviderRegistry.defaults(config: httpConfig);
  }
}
