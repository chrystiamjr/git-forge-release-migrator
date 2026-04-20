// ignore_for_file: implementation_imports

import 'package:gfrm_dart/src/application/run_result.dart';

import 'package:gfrm_gui/src/application/run/models/desktop_run_completion.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_failure_summary.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_snapshot.dart';
import 'package:gfrm_gui/src/runtime/run/mappers/map_desktop_run_failure_to_summary.dart';

DesktopRunCompletion mapRunResultToCompletion({required RunResult result, required DesktopRunSnapshot snapshot}) {
  final List<DesktopRunFailureSummary> failures = result.failures
      .map(mapDesktopRunFailureToSummary)
      .toList(growable: false);

  return DesktopRunCompletion(
    status: switch (result.status) {
      RunStatus.success => 'success',
      RunStatus.partialFailure => 'partial_failure',
      RunStatus.validationFailure => 'validation_failure',
      RunStatus.runtimeFailure => 'runtime_failure',
    },
    exitCode: result.exitCode,
    resultsRootPath: result.resultsRootPath,
    runWorkdirPath: result.runWorkdirPath,
    snapshot: snapshot,
    failures: failures,
  );
}
