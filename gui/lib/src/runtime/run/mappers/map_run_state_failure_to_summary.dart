// ignore_for_file: implementation_imports

import 'package:gfrm_dart/src/runtime_events/run_state_failure.dart';

import 'package:gfrm_gui/src/application/run/models/desktop_run_failure_summary.dart';

DesktopRunFailureSummary mapRunStateFailureToSummary(RunStateFailure failure) {
  return DesktopRunFailureSummary(
    code: failure.code,
    message: failure.message,
    retryable: failure.retryable,
    phase: failure.phase,
  );
}
