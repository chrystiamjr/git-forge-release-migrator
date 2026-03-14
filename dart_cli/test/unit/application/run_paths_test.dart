import 'dart:io';

import 'package:gfrm_dart/src/application/run_paths.dart';
import 'package:test/test.dart';

import '../../support/runtime_options_fixture.dart';
import '../../support/temp_dir.dart';

void main() {
  group('run paths', () {
    test('prepareRun derives workdir, log file, and checkpoint file from results root', () {
      final Directory temp = createTempDir('gfrm-run-paths-');

      final PreparedRun prepared = prepareRun(
        buildRuntimeOptions(workdir: '${temp.path}/results'),
      );

      expect(prepared.resultsRoot.path, '${temp.path}/results');
      expect(prepared.runWorkdir.path, startsWith('${temp.path}/results/'));
      expect(prepared.options.workdir, prepared.runWorkdir.path);
      expect(prepared.options.logFile, '${prepared.runWorkdir.path}/migration-log.jsonl');
      expect(prepared.options.checkpointFile, '${prepared.resultsRoot.path}/checkpoints/state.jsonl');
    });

    test('prepareRun preserves explicit log and checkpoint paths', () {
      final Directory temp = createTempDir('gfrm-run-paths-explicit-');
      final String explicitLogPath = '${temp.path}/custom/log.jsonl';
      final String explicitCheckpointPath = '${temp.path}/custom/checkpoints.jsonl';

      final PreparedRun prepared = prepareRun(
        buildRuntimeOptions(
          workdir: '${temp.path}/results',
          logFile: explicitLogPath,
          checkpointFile: explicitCheckpointPath,
        ),
      );

      expect(prepared.options.logFile, explicitLogPath);
      expect(prepared.options.checkpointFile, explicitCheckpointPath);
    });

    test('prepareRunDirectories creates both results root and run workdir', () {
      final Directory temp = createTempDir('gfrm-run-paths-directories-');
      final PreparedRun prepared = prepareRun(
        buildRuntimeOptions(workdir: '${temp.path}/results'),
      );

      prepareRunDirectories(prepared);

      expect(prepared.resultsRoot.existsSync(), isTrue);
      expect(prepared.runWorkdir.existsSync(), isTrue);
    });

    test('allocateRunWorkdir appends numeric suffix when timestamp path already exists', () {
      final Directory temp = createTempDir('gfrm-run-paths-collision-');
      final Directory firstCandidate = allocateRunWorkdir(temp);
      firstCandidate.createSync(recursive: true);

      final Directory secondCandidate = allocateRunWorkdir(temp);

      expect(secondCandidate.path, isNot(firstCandidate.path));
      expect(secondCandidate.path, startsWith(firstCandidate.path));
    });
  });
}
