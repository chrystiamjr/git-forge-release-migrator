// ignore_for_file: implementation_imports

import 'package:gfrm_dart/src/application/run_failure.dart';

import '../../application/run/desktop_run_failure_summary.dart';

DesktopRunFailureSummary mapDesktopRunFailureToSummary(RunFailure failure) {
  return DesktopRunFailureSummary(
    code: failure.code,
    message: failure.message,
    retryable: failure.retryable,
    phase: failure.phase ?? '',
  );
}
