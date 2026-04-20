import 'package:gfrm_gui/src/application/run/models/desktop_preflight_check_item.dart';

final class DesktopPreflightSummary {
  const DesktopPreflightSummary({
    required this.status,
    required this.checks,
    required this.checkCount,
    required this.blockingCount,
    required this.warningCount,
  });

  const DesktopPreflightSummary.initial()
    : status = 'idle',
      checks = const <DesktopPreflightCheckItem>[],
      checkCount = 0,
      blockingCount = 0,
      warningCount = 0;

  final String status;
  final List<DesktopPreflightCheckItem> checks;
  final int checkCount;
  final int blockingCount;
  final int warningCount;

  bool get hasBlockingErrors => blockingCount > 0;
}
