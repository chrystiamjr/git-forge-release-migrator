// ignore_for_file: implementation_imports

import 'package:gfrm_dart/src/application/run_request.dart';
import 'package:gfrm_dart/src/models/runtime_options.dart';

import '../../application/run/desktop_preflight_request.dart';
import '../../application/run/desktop_run_start_request.dart';
import 'build_gui_runtime_options.dart';

RunRequest mapDesktopRunStartRequestToRunRequest(DesktopRunStartRequest request) {
  final RuntimeOptions options = buildGuiRuntimeOptions(
    commandName: DesktopPreflightRequest.modeMigrate,
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
    dryRun: request.dryRun,
    workdir: request.workdir,
    logFile: request.logFile,
    downloadWorkers: request.downloadWorkers,
    releaseWorkers: request.releaseWorkers,
    checkpointFile: '',
    tagsFile: '',
  );

  return RunRequest(options: options);
}
