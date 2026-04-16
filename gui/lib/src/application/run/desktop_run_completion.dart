import 'desktop_run_failure_summary.dart';
import 'desktop_run_snapshot.dart';

final class DesktopRunCompletion {
  const DesktopRunCompletion({
    required this.status,
    required this.exitCode,
    required this.resultsRootPath,
    required this.runWorkdirPath,
    required this.snapshot,
    required this.failures,
  });

  final String status;
  final int exitCode;
  final String resultsRootPath;
  final String runWorkdirPath;
  final DesktopRunSnapshot snapshot;
  final List<DesktopRunFailureSummary> failures;

  bool get isSuccess => status == 'success';
}
