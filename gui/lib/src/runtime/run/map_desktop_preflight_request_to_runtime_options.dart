// ignore_for_file: implementation_imports

import 'package:gfrm_dart/src/models/runtime_options.dart';

import '../../application/run/desktop_preflight_request.dart';
import 'build_gui_runtime_options.dart';

RuntimeOptions mapDesktopPreflightRequestToRuntimeOptions(DesktopPreflightRequest request) {
  return buildGuiRuntimeOptions(
    commandName: request.mode,
    sourceProvider: request.sourceProvider,
    sourceUrl: request.sourceUrl,
    sourceToken: request.sourceToken,
    targetProvider: request.targetProvider,
    targetUrl: request.targetUrl,
    targetToken: request.targetToken,
    settingsProfile: request.settingsProfile,
    fromTag: '',
    toTag: '',
    skipTagMigration: false,
    dryRun: false,
    workdir: '',
    logFile: '',
    downloadWorkers: 4,
    releaseWorkers: 1,
    checkpointFile: '',
    tagsFile: '',
  );
}
