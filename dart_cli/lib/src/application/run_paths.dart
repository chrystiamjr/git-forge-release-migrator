import 'dart:io';

import '../models/runtime_options.dart';

final class PreparedRun {
  PreparedRun({
    required this.options,
    required this.resultsRoot,
    required this.runWorkdir,
  });

  final RuntimeOptions options;
  final Directory resultsRoot;
  final Directory runWorkdir;
}

Directory allocateRunWorkdir(Directory baseDir) {
  final DateTime now = DateTime.now().toUtc();
  final String runId =
      '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';

  Directory candidate = Directory('${baseDir.path}/$runId');
  if (!candidate.existsSync()) {
    return candidate;
  }

  int index = 2;
  while (true) {
    candidate = Directory('${baseDir.path}/$runId-$index');
    if (!candidate.existsSync()) {
      return candidate;
    }

    index += 1;
  }
}

PreparedRun prepareRun(RuntimeOptions options) {
  final Directory resultsRoot = Directory(options.effectiveWorkdir());
  final Directory runWorkdir = allocateRunWorkdir(resultsRoot);

  final RuntimeOptions withWorkdir = options.copyWith(
    workdir: runWorkdir.path,
    logFile: options.logFile.isEmpty ? '${runWorkdir.path}/migration-log.jsonl' : options.logFile,
    checkpointFile:
        options.checkpointFile.isEmpty ? '${resultsRoot.path}/checkpoints/state.jsonl' : options.checkpointFile,
  );

  return PreparedRun(
    options: withWorkdir,
    resultsRoot: resultsRoot,
    runWorkdir: runWorkdir,
  );
}

void prepareRunDirectories(PreparedRun prepared) {
  if (!prepared.resultsRoot.existsSync()) {
    prepared.resultsRoot.createSync(recursive: true);
  }

  if (!prepared.runWorkdir.existsSync()) {
    prepared.runWorkdir.createSync(recursive: true);
  }
}
