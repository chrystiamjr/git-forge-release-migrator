// ignore_for_file: implementation_imports

import 'package:gfrm_dart/src/application/preflight_check.dart';

import 'package:gfrm_gui/src/application/run/models/desktop_preflight_check_item.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_preflight_summary.dart';
import 'package:gfrm_gui/src/runtime/run/mappers/map_desktop_preflight_check_to_item.dart';

DesktopPreflightSummary mapPreflightChecksToSummary(List<PreflightCheck> checks) {
  final List<DesktopPreflightCheckItem> items = checks.map(mapDesktopPreflightCheckToItem).toList(growable: false);
  final int blockingCount = items.where((DesktopPreflightCheckItem item) => item.isBlocking).length;
  final int warningCount = items.where((DesktopPreflightCheckItem item) => item.isWarning).length;

  return DesktopPreflightSummary(
    status: blockingCount > 0
        ? 'failed'
        : warningCount > 0
        ? 'warning'
        : 'ok',
    checks: items,
    checkCount: items.length,
    blockingCount: blockingCount,
    warningCount: warningCount,
  );
}
