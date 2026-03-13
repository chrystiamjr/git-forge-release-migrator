import 'dart:convert';
import 'dart:io';

import 'package:gfrm_dart/gfrm_dart.dart';
import 'package:gfrm_dart/src/application/preflight_check.dart';
import 'package:gfrm_dart/src/application/run_failure.dart';
import 'package:gfrm_dart/src/application/run_request.dart';
import 'package:gfrm_dart/src/application/run_result.dart';
import 'package:gfrm_dart/src/application/run_service.dart';
import 'package:gfrm_dart/src/core/logging.dart';
import 'package:gfrm_dart/src/models/runtime_options.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../support/buffer_console_output.dart';
import '../../support/temp_dir.dart';

File _findSingleFile(Directory root, String name) {
  final List<File> matches = root
      .listSync(recursive: true)
      .whereType<File>()
      .where((File file) => p.basename(file.path) == name)
      .toList(growable: false);
  expect(matches, hasLength(1));
  return matches.single;
}

final class _FakeRunService extends RunService {
  _FakeRunService({
    required this.result,
    required super.logger,
    this.onRun,
  });

  final RunResult result;
  final void Function(RunRequest request)? onRun;

  @override
  Future<RunResult> run(RunRequest request) async {
    onRun?.call(request);
    return result;
  }
}

void main() {
  group('CliRunner', () {
    test('help command prints usage and exits successfully', () async {
      final BufferConsoleOutput output = BufferConsoleOutput();

      final int exitCode = await CliRunner.run(<String>['--help'], output: output);

      expect(exitCode, 0);
      expect(output.stdoutLines.single, contains('Usage: gfrm <command> [options]'));
      expect(output.stderrLines, isEmpty);
    });

    test('demo command prints banner when terminal output is enabled', () async {
      final BufferConsoleOutput output = BufferConsoleOutput(hasTerminal: true);
      final Directory temp = createTempDir('gfrm-demo-banner-');

      final int exitCode = await CliRunner.run(
        <String>[
          commandDemo,
          '--source-provider',
          'github',
          '--source-url',
          'https://github.com/acme/source',
          '--source-token',
          'src-token',
          '--target-provider',
          'gitlab',
          '--target-url',
          'https://gitlab.com/acme/target',
          '--target-token',
          'dst-token',
          '--workdir',
          '${temp.path}/results',
          '--demo-releases',
          '1',
          '--demo-sleep-seconds',
          '0',
        ],
        output: output,
      );

      expect(exitCode, 0);
      expect(output.stdoutLines, contains('Quick commands:'));
      expect(output.stdoutLines, contains('Migrate tags, releases, changelog and assets between Git forges.'));
    });

    test('demo command writes summary and notes using tags file input', () async {
      final BufferConsoleOutput output = BufferConsoleOutput();
      final Directory temp = createTempDir('gfrm-demo-run-');
      final Directory resultsRoot = Directory('${temp.path}/results');
      final File tagsFile = File('${temp.path}/tags.txt')..writeAsStringSync('# comment\nv1.0.0\n\nv1.1.0\nv1.2.0\n');

      final int exitCode = await CliRunner.run(
        <String>[
          commandDemo,
          '--source-provider',
          'github',
          '--source-url',
          'https://github.com/acme/source',
          '--source-token',
          'src-token',
          '--target-provider',
          'gitlab',
          '--target-url',
          'https://gitlab.com/acme/target',
          '--target-token',
          'dst-token',
          '--workdir',
          resultsRoot.path,
          '--tags-file',
          tagsFile.path,
          '--demo-releases',
          '2',
          '--demo-sleep-seconds',
          '0',
          '--no-banner',
        ],
        output: output,
      );

      expect(exitCode, 0);
      expect(output.stderrLines, isEmpty);

      final File summaryFile = _findSingleFile(resultsRoot, 'summary.json');
      final Map<String, dynamic> summary = jsonDecode(summaryFile.readAsStringSync()) as Map<String, dynamic>;
      expect(summary['command'], commandDemo);
      expect((summary['counts'] as Map<String, dynamic>)['releases_created'], 2);

      final Directory runDir = summaryFile.parent;
      expect(File('${runDir.path}/release-v1.0.0-notes.md').existsSync(), isTrue);
      expect(File('${runDir.path}/release-v1.1.0-notes.md').existsSync(), isTrue);
      expect(File('${runDir.path}/failed-tags.txt').readAsStringSync(), isEmpty);
    });

    test('demo command falls back to generated tags when tags file has no entries', () async {
      final BufferConsoleOutput output = BufferConsoleOutput();
      final Directory temp = createTempDir('gfrm-demo-fallback-');
      final Directory resultsRoot = Directory('${temp.path}/results');
      final File tagsFile = File('${temp.path}/empty-tags.txt')..writeAsStringSync('# only comments\n\n');

      final int exitCode = await CliRunner.run(
        <String>[
          commandDemo,
          '--source-provider',
          'github',
          '--source-url',
          'https://github.com/acme/source',
          '--source-token',
          'src-token',
          '--target-provider',
          'gitlab',
          '--target-url',
          'https://gitlab.com/acme/target',
          '--target-token',
          'dst-token',
          '--workdir',
          resultsRoot.path,
          '--tags-file',
          tagsFile.path,
          '--demo-releases',
          '3',
          '--demo-sleep-seconds',
          '0',
          '--no-banner',
        ],
        output: output,
      );

      expect(exitCode, 0);
      expect(output.stderrLines, isEmpty);

      final File summaryFile = _findSingleFile(resultsRoot, 'summary.json');
      final Map<String, dynamic> summary = jsonDecode(summaryFile.readAsStringSync()) as Map<String, dynamic>;
      expect((summary['counts'] as Map<String, dynamic>)['releases_created'], 3);
      expect(File('${summaryFile.parent.path}/release-v3.2.1-notes.md').existsSync(), isTrue);
    });

    test('settings command without action returns help successfully', () async {
      final BufferConsoleOutput output = BufferConsoleOutput();

      final int exitCode = await CliRunner.run(<String>[commandSettings], output: output);

      expect(exitCode, 0);
      expect(output.stdoutLines.single, contains('Usage: gfrm settings <action> [options]'));
      expect(output.stderrLines, isEmpty);
    });

    test('settings help command prints settings usage and exits successfully', () async {
      final BufferConsoleOutput output = BufferConsoleOutput();

      final int exitCode = await CliRunner.run(<String>[commandSettings, '--help'], output: output);

      expect(exitCode, 0);
      expect(output.stdoutLines.single, contains('Usage: gfrm settings <action> [options]'));
      expect(output.stderrLines, isEmpty);
    });

    test('setup help command prints setup usage and exits successfully', () async {
      final BufferConsoleOutput output = BufferConsoleOutput();

      final int exitCode = await CliRunner.run(<String>[commandSetup, '--help'], output: output);

      expect(exitCode, 0);
      expect(output.stdoutLines.single, contains('Usage: gfrm setup [options]'));
      expect(output.stderrLines, isEmpty);
    });

    test('invalid migrate invocation returns non-zero', () async {
      final BufferConsoleOutput output = BufferConsoleOutput();

      final int exitCode = await CliRunner.run(<String>[commandMigrate], output: output);

      expect(exitCode, 1);
      expect(output.stderrLines.single, contains('Missing required option --source-provider'));
    });

    test('unknown command reports error through stderr when logger was not created yet', () async {
      final BufferConsoleOutput output = BufferConsoleOutput();

      final int exitCode = await CliRunner.run(<String>['unknown-command'], output: output);

      expect(exitCode, 1);
      expect(output.stdoutLines, isEmpty);
      expect(output.stderrLines.single, contains('[ERROR]'));
    });

    test('migrate command preserves non-zero exit code from RunService', () async {
      final BufferConsoleOutput output = BufferConsoleOutput();

      final int exitCode = await CliRunner.run(
        <String>[
          commandMigrate,
          '--source-provider',
          'github',
          '--source-url',
          'https://github.com/acme/source',
          '--source-token',
          'src-token',
          '--target-provider',
          'gitlab',
          '--target-url',
          'https://gitlab.com/acme/target',
          '--target-token',
          'dst-token',
          '--no-banner',
        ],
        output: output,
        runServiceFactory: (ConsoleLogger logger) => _FakeRunService(
          logger: logger,
          result: const RunResult(
            status: RunStatus.runtimeFailure,
            exitCode: 1,
            resultsRootPath: '/tmp/results',
            runWorkdirPath: '/tmp/results/20260313-120000',
            logPath: '/tmp/results/20260313-120000/migration-log.jsonl',
            checkpointPath: '/tmp/results/checkpoints/state.jsonl',
            summaryPath: '/tmp/results/20260313-120000/summary.json',
            failedTagsPath: '/tmp/results/20260313-120000/failed-tags.txt',
            retryCommand: '',
            preflightChecks: <PreflightCheck>[],
            failures: <RunFailure>[
              RunFailure(
                scope: RunFailure.scopeExecution,
                code: 'runtime-failed',
                message: 'MigrationPhaseError: Migration finished with failures',
                retryable: true,
              ),
            ],
          ),
        ),
      );

      expect(exitCode, 1);
    });

    test('migrate command returns non-zero when run service factory throws after logger setup', () async {
      final BufferConsoleOutput output = BufferConsoleOutput();

      final int exitCode = await CliRunner.run(
        <String>[
          commandMigrate,
          '--source-provider',
          'github',
          '--source-url',
          'https://github.com/acme/source',
          '--source-token',
          'src-token',
          '--target-provider',
          'gitlab',
          '--target-url',
          'https://gitlab.com/acme/target',
          '--target-token',
          'dst-token',
          '--no-banner',
        ],
        output: output,
        runServiceFactory: (_) => throw StateError('factory boom'),
      );

      expect(exitCode, 1);
    });

    test('migrate command maps parsed runtime options into RunRequest', () async {
      final BufferConsoleOutput output = BufferConsoleOutput();
      RunRequest? capturedRequest;

      final int exitCode = await CliRunner.run(
        <String>[
          commandMigrate,
          '--source-provider',
          'github',
          '--source-url',
          'https://github.com/acme/source',
          '--source-token',
          'src-token',
          '--target-provider',
          'gitlab',
          '--target-url',
          'https://gitlab.com/acme/target',
          '--target-token',
          'dst-token',
          '--settings-profile',
          'work',
          '--no-banner',
        ],
        output: output,
        runServiceFactory: (ConsoleLogger logger) => _FakeRunService(
          logger: logger,
          onRun: (RunRequest request) => capturedRequest = request,
          result: const RunResult(
            status: RunStatus.success,
            exitCode: 0,
            resultsRootPath: '/tmp/results',
            runWorkdirPath: '/tmp/results/20260313-120000',
            logPath: '/tmp/results/20260313-120000/migration-log.jsonl',
            checkpointPath: '/tmp/results/checkpoints/state.jsonl',
            summaryPath: '/tmp/results/20260313-120000/summary.json',
            failedTagsPath: '/tmp/results/20260313-120000/failed-tags.txt',
            retryCommand: '',
            preflightChecks: <PreflightCheck>[],
            failures: <RunFailure>[],
          ),
        ),
      );

      expect(exitCode, 0);
      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.options.commandName, commandMigrate);
      expect(capturedRequest!.options.settingsProfile, 'work');
      expect(capturedRequest!.options.sourceToken, 'src-token');
      expect(capturedRequest!.options.targetToken, 'dst-token');
    });

    test('resume command maps parsed runtime options into RunRequest and preserves success exit', () async {
      final BufferConsoleOutput output = BufferConsoleOutput();
      final Directory temp = createTempDir('gfrm-runner-resume-');
      final String sessionPath = '${temp.path}/session.json';
      RunRequest? capturedRequest;

      File(sessionPath).writeAsStringSync(jsonEncode(<String, dynamic>{
        'source_provider': 'github',
        'source_url': 'https://github.com/acme/source',
        'target_provider': 'gitlab',
        'target_url': 'https://gitlab.com/acme/target',
        'source_token': 'session-source-token',
        'target_token': 'session-target-token',
        'session_token_mode': 'plain',
      }));

      final int exitCode = await CliRunner.run(
        <String>[
          commandResume,
          '--session-file',
          sessionPath,
          '--no-banner',
        ],
        output: output,
        runServiceFactory: (ConsoleLogger logger) => _FakeRunService(
          logger: logger,
          onRun: (RunRequest request) => capturedRequest = request,
          result: const RunResult(
            status: RunStatus.success,
            exitCode: 0,
            resultsRootPath: '/tmp/results',
            runWorkdirPath: '/tmp/results/20260313-120000',
            logPath: '/tmp/results/20260313-120000/migration-log.jsonl',
            checkpointPath: '/tmp/results/checkpoints/state.jsonl',
            summaryPath: '/tmp/results/20260313-120000/summary.json',
            failedTagsPath: '/tmp/results/20260313-120000/failed-tags.txt',
            retryCommand: '',
            preflightChecks: <PreflightCheck>[],
            failures: <RunFailure>[],
          ),
        ),
      );

      expect(exitCode, 0);
      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.options.commandName, commandResume);
      expect(capturedRequest!.options.sourceToken, 'session-source-token');
      expect(capturedRequest!.options.targetToken, 'session-target-token');
    });

    test('cli renders structured preflight warnings without changing successful exit', () async {
      final BufferConsoleOutput output = BufferConsoleOutput();

      final int exitCode = await CliRunner.run(
        <String>[
          commandMigrate,
          '--source-provider',
          'github',
          '--source-url',
          'https://github.com/acme/source',
          '--source-token',
          'src-token',
          '--target-provider',
          'gitlab',
          '--target-url',
          'https://gitlab.com/acme/target',
          '--target-token',
          'dst-token',
          '--no-banner',
        ],
        output: output,
        runServiceFactory: (ConsoleLogger logger) => _FakeRunService(
          logger: logger,
          result: const RunResult(
            status: RunStatus.success,
            exitCode: 0,
            resultsRootPath: '/tmp/results',
            runWorkdirPath: '/tmp/results/20260313-120000',
            logPath: '/tmp/results/20260313-120000/migration-log.jsonl',
            checkpointPath: '/tmp/results/checkpoints/state.jsonl',
            summaryPath: '/tmp/results/20260313-120000/summary.json',
            failedTagsPath: '/tmp/results/20260313-120000/failed-tags.txt',
            retryCommand: '',
            preflightChecks: <PreflightCheck>[
              PreflightCheck(
                status: PreflightCheckStatus.warning,
                code: 'missing-settings-profile',
                message: 'Settings profile work was not found in effective settings.',
                hint:
                    'The run can continue if tokens were resolved elsewhere, but profile-backed settings will not apply.',
                field: 'settings_profile',
              ),
            ],
            failures: <RunFailure>[],
          ),
        ),
      );

      expect(exitCode, 0);
      expect(output.stderrLines, isEmpty);
    });

    test('cli preserves non-zero exit when run service returns preflight validation failure', () async {
      final BufferConsoleOutput output = BufferConsoleOutput();

      final int exitCode = await CliRunner.run(
        <String>[
          commandMigrate,
          '--source-provider',
          'github',
          '--source-url',
          'https://github.com/acme/source',
          '--target-provider',
          'gitlab',
          '--target-url',
          'https://gitlab.com/acme/target',
          '--no-banner',
        ],
        output: output,
        runServiceFactory: (ConsoleLogger logger) => _FakeRunService(
          logger: logger,
          result: const RunResult(
            status: RunStatus.validationFailure,
            exitCode: 1,
            resultsRootPath: '/tmp/results',
            runWorkdirPath: '/tmp/results/20260313-120000',
            logPath: '/tmp/results/20260313-120000/migration-log.jsonl',
            checkpointPath: '/tmp/results/checkpoints/state.jsonl',
            summaryPath: '/tmp/results/20260313-120000/summary.json',
            failedTagsPath: '/tmp/results/20260313-120000/failed-tags.txt',
            retryCommand: '',
            preflightChecks: <PreflightCheck>[
              PreflightCheck(
                status: PreflightCheckStatus.error,
                code: 'missing-source-token',
                message: 'Missing source token.',
                hint: 'Provide --source-token, a settings profile token, or a relevant environment variable.',
                field: 'source_token',
              ),
            ],
            failures: <RunFailure>[
              RunFailure(
                scope: RunFailure.scopeValidation,
                code: 'missing-source-token',
                message: 'Missing source token.',
                retryable: false,
              ),
            ],
          ),
        ),
      );

      expect(exitCode, 1);
      expect(output.stderrLines, isEmpty);
    });

    test('demo command honors custom log path and keeps banner hidden on non-terminal output', () async {
      final BufferConsoleOutput output = BufferConsoleOutput(hasTerminal: false);
      final Directory temp = createTempDir('gfrm-demo-custom-log-');
      final Directory resultsRoot = Directory('${temp.path}/results');
      final String missingTagsFile = '${temp.path}/missing-tags.txt';
      final String customLogPath = '${temp.path}/custom-demo.jsonl';

      final int exitCode = await CliRunner.run(
        <String>[
          commandDemo,
          '--source-provider',
          'github',
          '--source-url',
          'https://github.com/acme/source',
          '--source-token',
          'src-token',
          '--target-provider',
          'gitlab',
          '--target-url',
          'https://gitlab.com/acme/target',
          '--target-token',
          'dst-token',
          '--workdir',
          resultsRoot.path,
          '--log-file',
          customLogPath,
          '--tags-file',
          missingTagsFile,
          '--skip-tags',
          '--demo-releases',
          '2',
          '--demo-sleep-seconds',
          '0',
        ],
        output: output,
      );

      expect(exitCode, 0);
      expect(output.stdoutLines, isNot(contains('Quick commands:')));
      expect(File(customLogPath).existsSync(), isTrue);

      final File summaryFile = _findSingleFile(resultsRoot, 'summary.json');
      final Map<String, dynamic> summary = jsonDecode(summaryFile.readAsStringSync()) as Map<String, dynamic>;
      expect((summary['counts'] as Map<String, dynamic>)['tags_skipped'], 2);
      expect((summary['paths'] as Map<String, dynamic>)['jsonl_log'], customLogPath);
    });
  });
}
