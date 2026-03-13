import 'preflight_check.dart';
import 'run_failure.dart';

enum RunStatus {
  success,
  partialFailure,
  validationFailure,
  runtimeFailure,
}

final class RunResult {
  const RunResult({
    required this.status,
    required this.exitCode,
    required this.resultsRootPath,
    required this.runWorkdirPath,
    required this.logPath,
    required this.checkpointPath,
    required this.summaryPath,
    required this.failedTagsPath,
    required this.retryCommand,
    required this.preflightChecks,
    required this.failures,
  });

  final RunStatus status;
  final int exitCode;
  final String resultsRootPath;
  final String runWorkdirPath;
  final String logPath;
  final String checkpointPath;
  final String summaryPath;
  final String failedTagsPath;
  final String retryCommand;
  final List<PreflightCheck> preflightChecks;
  final List<RunFailure> failures;

  bool get isSuccess => status == RunStatus.success;

  List<String> get preflightMessages {
    return preflightChecks
        .where((PreflightCheck check) => check.status != PreflightCheckStatus.ok)
        .map((PreflightCheck check) => check.message)
        .toList(growable: false);
  }
}
