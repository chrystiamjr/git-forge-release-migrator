// ignore_for_file: implementation_imports

import 'package:gfrm_dart/src/application/run_request.dart';
import 'package:gfrm_dart/src/models/runtime_options.dart';

import 'package:gfrm_gui/src/application/run/models/desktop_preflight_request.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_resume_request.dart';
import 'package:gfrm_gui/src/runtime/run/services/build_gui_runtime_options.dart';

RunRequest mapDesktopRunResumeRequestToRunRequest(DesktopRunResumeRequest request) {
  final RuntimeOptions options = buildGuiRuntimeOptions(
    commandName: DesktopPreflightRequest.modeResume,
    sourceProvider: request.sourceProvider,
    sourceUrl: request.sourceUrl,
    sourceToken: request.sourceToken,
    targetProvider: request.targetProvider,
    targetUrl: request.targetUrl,
    targetToken: request.targetToken,
    settingsProfile: request.settingsProfile,
    fromTag: request.fromTag,
    toTag: request.toTag,
    skipTagMigration: request.skipTagMigration,
    skipReleaseMigration: request.skipReleaseMigration,
    skipReleaseAssetMigration: request.skipReleaseAssetMigration,
    dryRun: request.dryRun,
    workdir: request.workdir,
    logFile: request.logFile,
    downloadWorkers: request.downloadWorkers,
    releaseWorkers: request.releaseWorkers,
    checkpointFile: request.checkpointFile,
    tagsFile: request.tagsFile,
  );

  return RunRequest(options: options);
}
