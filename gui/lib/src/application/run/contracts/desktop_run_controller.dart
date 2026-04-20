import 'package:gfrm_gui/src/application/run/models/desktop_preflight_request.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_preflight_summary.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_action_result.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_resume_request.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_session.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_snapshot.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_start_request.dart';

abstract interface class DesktopRunController {
  DesktopRunSnapshot get currentSnapshot;

  Stream<DesktopRunSnapshot> get snapshots;

  Future<DesktopPreflightSummary> evaluatePreflight(DesktopPreflightRequest request);

  Future<DesktopRunSession> startRun(DesktopRunStartRequest request);

  Future<DesktopRunSession> resumeRun(DesktopRunResumeRequest request);

  Future<DesktopRunActionResult> cancelActiveRun();

  void dispose();
}
