import 'dart:convert';
import 'dart:io';

import 'package:gfrm_dart/src/config/types/smoke_command_options.dart';
import 'package:gfrm_dart/src/core/console_output.dart';
import 'package:gfrm_dart/src/core/logging.dart';
import 'package:gfrm_dart/src/core/http.dart';
import 'package:gfrm_dart/src/smoke/artifact_validator.dart';
import 'package:gfrm_dart/src/smoke/fixture_trigger.dart';
import 'package:gfrm_dart/src/smoke/smoke_runner.dart';
import 'package:test/test.dart';

class _FakeOutput implements ConsoleOutput {
  final List<String> out = <String>[];
  final List<String> err = <String>[];

  @override
  bool get hasTerminal => false;

  @override
  bool get supportsAnsiEscapes => false;

  @override
  void writeOut(String text) => out.add(text);

  @override
  void writeOutLine(String line) => out.add(line);

  @override
  void writeErrLine(String line) => err.add(line);
}

class _FakeTrigger extends FixtureTrigger {
  _FakeTrigger({
    required this.onCreate,
    required this.onCleanup,
  }) : super(
          http: HttpClientHelper(),
          coords: const RepoCoordinates(host: 'example.com', workspace: 'w', repo: 'r'),
          token: 'fake',
          pollInterval: const Duration(milliseconds: 1),
          pollTimeout: const Duration(seconds: 1),
        );

  final Future<FixtureRunResult> Function() onCreate;
  final Future<FixtureRunResult> Function() onCleanup;

  int createCalls = 0;
  int cleanupCalls = 0;

  @override
  String get provider => 'fake';

  @override
  Future<FixtureRunResult> createFakeReleases() {
    createCalls += 1;
    return onCreate();
  }

  @override
  Future<FixtureRunResult> cleanupTagsAndReleases() {
    cleanupCalls += 1;
    return onCleanup();
  }
}

SmokeCommandOptions _options({
  String mode = smokeModeHappyPath,
  bool skipSetup = false,
  bool skipTeardown = false,
  int cooldownSeconds = 0,
}) {
  return SmokeCommandOptions(
    sourceProvider: 'github',
    sourceUrl: 'https://github.com/w/src',
    targetProvider: 'gitlab',
    targetUrl: 'https://gitlab.com/w/tgt',
    mode: mode,
    skipSetup: skipSetup,
    skipTeardown: skipTeardown,
    cooldownSeconds: cooldownSeconds,
    pollIntervalSeconds: 1,
    pollTimeoutSeconds: 30,
    settingsProfile: '',
    workdir: '',
    quiet: true,
    jsonOutput: false,
  );
}

Directory _writeValidRunDir({bool partialFailure = false}) {
  final Directory dir = Directory.systemTemp.createTempSync('gfrm_smoke_runner_');
  final Map<String, Object?> summary = <String, Object?>{
    'schema_version': 2,
    'command': 'migrate',
    'retry_command': partialFailure ? 'gfrm resume --tags-file ${dir.path}/failed-tags.txt' : '',
    'retry_command_shell': partialFailure ? '/bin/bash' : '',
    'paths': <String, String>{
      'failed_tags': '${dir.path}/failed-tags.txt',
      'jsonl_log': '${dir.path}/migration-log.jsonl',
      'workdir': dir.path,
    },
  };
  File('${dir.path}/summary.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(summary));
  File('${dir.path}/failed-tags.txt').writeAsStringSync('');
  File('${dir.path}/migration-log.jsonl').writeAsStringSync('');
  return dir;
}

void main() {
  group('SmokeRunner', () {
    test('runs happy path and returns 0', () async {
      final _FakeTrigger trigger = _FakeTrigger(
        onCreate: () async => const FixtureRunResult(status: 'success', reference: 'c1'),
        onCleanup: () async => const FixtureRunResult(status: 'success', reference: 't1'),
      );
      final Directory runDir = _writeValidRunDir();
      final ConsoleLogger logger =
          ConsoleLogger(quiet: true, jsonOutput: false, output: _FakeOutput());

      final SmokeRunner runner = SmokeRunner(
        options: _options(),
        logger: logger,
        sourceTrigger: trigger,
        migrate: () async => runDir,
        validator: const ArtifactValidator(),
      );

      final SmokeResult result = await runner.run();

      expect(result.exitCode, 0);
      expect(trigger.createCalls, 1);
      expect(trigger.cleanupCalls, 1);
      expect(
        result.phases.map((SmokePhaseOutcome p) => p.name).toList(),
        <String>['setup', 'migrate', 'validate', 'teardown'],
      );
      expect(result.phases.every((SmokePhaseOutcome p) => p.succeeded), isTrue);

      runDir.deleteSync(recursive: true);
    });

    test('skips setup when requested', () async {
      final _FakeTrigger trigger = _FakeTrigger(
        onCreate: () async => const FixtureRunResult(status: 'success', reference: 'c1'),
        onCleanup: () async => const FixtureRunResult(status: 'success', reference: 't1'),
      );
      final Directory runDir = _writeValidRunDir();
      final ConsoleLogger logger =
          ConsoleLogger(quiet: true, jsonOutput: false, output: _FakeOutput());

      final SmokeRunner runner = SmokeRunner(
        options: _options(skipSetup: true),
        logger: logger,
        sourceTrigger: trigger,
        migrate: () async => runDir,
        validator: const ArtifactValidator(),
      );

      final SmokeResult result = await runner.run();

      expect(result.exitCode, 0);
      expect(trigger.createCalls, 0);
      expect(trigger.cleanupCalls, 1);
      expect(
        result.phases.map((SmokePhaseOutcome p) => p.name).toList(),
        <String>['migrate', 'validate', 'teardown'],
      );

      runDir.deleteSync(recursive: true);
    });

    test('skips teardown when requested', () async {
      final _FakeTrigger trigger = _FakeTrigger(
        onCreate: () async => const FixtureRunResult(status: 'success', reference: 'c1'),
        onCleanup: () async => const FixtureRunResult(status: 'success', reference: 't1'),
      );
      final Directory runDir = _writeValidRunDir();
      final ConsoleLogger logger =
          ConsoleLogger(quiet: true, jsonOutput: false, output: _FakeOutput());

      final SmokeRunner runner = SmokeRunner(
        options: _options(skipTeardown: true),
        logger: logger,
        sourceTrigger: trigger,
        migrate: () async => runDir,
        validator: const ArtifactValidator(),
      );

      final SmokeResult result = await runner.run();

      expect(result.exitCode, 0);
      expect(trigger.cleanupCalls, 0);

      runDir.deleteSync(recursive: true);
    });

    test('aborts on setup failure and does not call migrate or teardown', () async {
      final _FakeTrigger trigger = _FakeTrigger(
        onCreate: () async => const FixtureRunResult(
          status: 'failed',
          reference: 'c1',
          detail: 'CI returned conclusion=failure',
        ),
        onCleanup: () async => const FixtureRunResult(status: 'success', reference: 't1'),
      );
      bool migrateCalled = false;
      final ConsoleLogger logger =
          ConsoleLogger(quiet: true, jsonOutput: false, output: _FakeOutput());

      final SmokeRunner runner = SmokeRunner(
        options: _options(),
        logger: logger,
        sourceTrigger: trigger,
        migrate: () async {
          migrateCalled = true;
          return Directory.systemTemp.createTempSync('gfrm_should_not_exist_');
        },
        validator: const ArtifactValidator(),
      );

      final SmokeResult result = await runner.run();

      expect(result.exitCode, 1);
      expect(migrateCalled, isFalse);
      expect(trigger.cleanupCalls, 0);
      expect(result.phases.first.name, 'setup');
      expect(result.phases.first.succeeded, isFalse);
    });

    test('aborts on migration failure and does not call teardown', () async {
      final _FakeTrigger trigger = _FakeTrigger(
        onCreate: () async => const FixtureRunResult(status: 'success', reference: 'c1'),
        onCleanup: () async => const FixtureRunResult(status: 'success', reference: 't1'),
      );
      final ConsoleLogger logger =
          ConsoleLogger(quiet: true, jsonOutput: false, output: _FakeOutput());

      final SmokeRunner runner = SmokeRunner(
        options: _options(),
        logger: logger,
        sourceTrigger: trigger,
        migrate: () async {
          throw StateError('simulated migration error');
        },
        validator: const ArtifactValidator(),
      );

      final SmokeResult result = await runner.run();

      expect(result.exitCode, 1);
      expect(trigger.cleanupCalls, 0);
      expect(result.phases.last.name, 'migrate');
      expect(result.phases.last.succeeded, isFalse);
    });

    test('contract-check mode fails when retry_command is non-empty', () async {
      final _FakeTrigger trigger = _FakeTrigger(
        onCreate: () async => const FixtureRunResult(status: 'success', reference: 'c1'),
        onCleanup: () async => const FixtureRunResult(status: 'success', reference: 't1'),
      );
      final Directory runDir = _writeValidRunDir(partialFailure: true);
      final ConsoleLogger logger =
          ConsoleLogger(quiet: true, jsonOutput: false, output: _FakeOutput());

      final SmokeRunner runner = SmokeRunner(
        options: _options(mode: smokeModeContractCheck),
        logger: logger,
        sourceTrigger: trigger,
        migrate: () async => runDir,
        validator: const ArtifactValidator(),
      );

      final SmokeResult result = await runner.run();

      expect(result.exitCode, 1);
      expect(trigger.cleanupCalls, 0);
      expect(result.phases.last.name, 'validate');
      expect(result.phases.last.succeeded, isFalse);

      runDir.deleteSync(recursive: true);
    });

    test('partial-failure-resume mode accepts either retry shape', () async {
      final _FakeTrigger trigger = _FakeTrigger(
        onCreate: () async => const FixtureRunResult(status: 'success', reference: 'c1'),
        onCleanup: () async => const FixtureRunResult(status: 'success', reference: 't1'),
      );
      final Directory runDir = _writeValidRunDir(partialFailure: true);
      final ConsoleLogger logger =
          ConsoleLogger(quiet: true, jsonOutput: false, output: _FakeOutput());

      final SmokeRunner runner = SmokeRunner(
        options: _options(mode: smokeModePartialFailureResume),
        logger: logger,
        sourceTrigger: trigger,
        migrate: () async => runDir,
        validator: const ArtifactValidator(),
      );

      final SmokeResult result = await runner.run();

      expect(result.exitCode, 0);

      runDir.deleteSync(recursive: true);
    });
  });
}
