import 'dart:convert';
import 'dart:io';

import 'package:gfrm_dart/src/application/preflight_check.dart';
import 'package:gfrm_dart/src/application/run_failure.dart';
import 'package:gfrm_dart/src/application/run_request.dart';
import 'package:gfrm_dart/src/application/run_result.dart';
import 'package:gfrm_dart/src/application/run_service.dart';
import 'package:gfrm_dart/src/cli/smoke_command_handler.dart';
import 'package:gfrm_dart/src/config/types/smoke_command_options.dart';
import 'package:gfrm_dart/src/core/settings.dart';
import 'package:test/test.dart';

import '../../support/buffer_console_output.dart';
import '../../support/http_stubs.dart';
import '../../support/logging.dart';
import '../../support/temp_dir.dart';

void main() {
  group('SmokeCommandHandler', () {
    test(
        'forwards RunResult.runWorkdirPath to validator and does not pre-allocate a nested subdir',
        () async {
      final Directory temp = createTempDir('gfrm-smoke-handler-');
      await runInCurrentDirectory(temp, () async {
        SettingsManager.writeSettingsFile(
          SettingsManager.defaultLocalSettingsPath(cwd: temp.path),
          <String, dynamic>{
            'profiles': <String, dynamic>{
              'default': <String, dynamic>{
                'providers': <String, dynamic>{
                  'github': <String, dynamic>{'token_plain': 'dummy-gh'},
                  'gitlab': <String, dynamic>{'token_plain': 'dummy-gl'},
                },
              },
            },
          },
        );

        final Directory smokeRoot = Directory('${temp.path}/smoke-root')
          ..createSync(recursive: true);

        final _RecordingRunService runService = _RecordingRunService(
          logger: createSilentLogger(output: BufferConsoleOutput()),
          onRun: (RunRequest request) async {
            final String workdir = request.options.workdir;
            final Directory runDir = Directory('$workdir/run-synthetic')
              ..createSync(recursive: true);
            File('${runDir.path}/failed-tags.txt').writeAsStringSync('');
            File('${runDir.path}/migration-log.jsonl').writeAsStringSync('');
            File('${runDir.path}/summary.json').writeAsStringSync(
              jsonEncode(<String, dynamic>{
                'schema_version': 2,
                'command': 'migrate',
                'retry_command': '',
                'retry_command_shell': '',
                'paths': <String, dynamic>{
                  'failed_tags': '${runDir.path}/failed-tags.txt',
                  'jsonl_log': '${runDir.path}/migration-log.jsonl',
                  'workdir': runDir.path,
                },
              }),
            );
            return RunResult(
              status: RunStatus.success,
              exitCode: 0,
              resultsRootPath: workdir,
              runWorkdirPath: runDir.path,
              logPath: '${runDir.path}/migration-log.jsonl',
              checkpointPath: '',
              summaryPath: '${runDir.path}/summary.json',
              failedTagsPath: '${runDir.path}/failed-tags.txt',
              retryCommand: '',
              preflightChecks: const <PreflightCheck>[],
              failures: const <RunFailure>[],
            );
          },
        );

        final BufferConsoleOutput output = BufferConsoleOutput();
        final SmokeCommandHandler handler = SmokeCommandHandler(
          logger: createSilentLogger(output: output),
          output: output,
        );

        final int exitCode = await handler.run(
          SmokeCommandOptions(
            sourceProvider: 'github',
            sourceUrl: 'https://github.com/example/source',
            targetProvider: 'gitlab',
            targetUrl: 'https://gitlab.com/example/target',
            mode: smokeModeHappyPath,
            skipSetup: true,
            skipTeardown: true,
            cooldownSeconds: 0,
            pollIntervalSeconds: 1,
            pollTimeoutSeconds: 1,
            settingsProfile: 'default',
            workdir: smokeRoot.path,
            quiet: true,
            jsonOutput: false,
          ),
          cwd: temp.path,
          env: const <String, String>{},
          runServiceOverride: runService,
          httpOverride: ScriptedHttpClientHelper(),
        );

        expect(exitCode, 0);

        // Regression guard: handler must pass the smoke results root to the
        // RunService without pre-allocating a timestamped subdir. The service
        // (via prepareRun in production) is the single owner of run-dir
        // allocation.
        expect(runService.captured.options.workdir, smokeRoot.path);

        // Regression guard: only one subdir exists under the smoke root —
        // the one the RunService created. The pre-fix handler created a
        // wrapping timestamp dir that held a second timestamp dir inside.
        final List<FileSystemEntity> children = smokeRoot.listSync();
        expect(children, hasLength(1));
        expect(children.single.path, endsWith('run-synthetic'));
      });
    });
  });
}

final class _RecordingRunService extends RunService {
  _RecordingRunService({required super.logger, required this.onRun});

  final Future<RunResult> Function(RunRequest request) onRun;

  late RunRequest captured;

  @override
  Future<RunResult> run(RunRequest request) async {
    captured = request;
    return onRun(request);
  }
}
