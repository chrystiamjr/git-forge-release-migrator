// ignore_for_file: implementation_imports

import 'package:gfrm_dart/src/application/preflight_check.dart';

import 'package:gfrm_gui/src/application/run/models/desktop_preflight_check_item.dart';

DesktopPreflightCheckItem mapDesktopPreflightCheckToItem(PreflightCheck check) {
  return DesktopPreflightCheckItem(
    code: check.code,
    message: check.message,
    status: check.status.name,
    hint: check.hint,
    field: check.field,
  );
}
