import 'dart:convert';
import 'dart:io';
import 'dart:mirrors';

import 'package:dio/dio.dart';
import 'package:gfrm_dart/src/application/preflight_check.dart';
import 'package:gfrm_dart/src/application/run_failure.dart';
import 'package:gfrm_dart/src/application/run_request.dart';
import 'package:gfrm_dart/src/application/run_result.dart';
import 'package:gfrm_dart/src/cli/runtime_support.dart';
import 'package:gfrm_dart/src/core/http.dart';
import 'package:gfrm_dart/src/core/enums/logger_prefix.dart';
import 'package:gfrm_dart/src/core/logging.dart';
import 'package:gfrm_dart/src/models/runtime_options.dart';
import 'package:test/test.dart';

import 'package:gfrm_dart/src/config.dart' as config_lib;
import 'package:gfrm_dart/src/core/http.dart' as http_lib;

import '../../support/buffer_console_output.dart';
import '../../support/temp_dir.dart';

void _loadPrivateTargetLibraries() {
  config_lib.CliRequestParser;
  http_lib.HttpClientHelper;
}

LibraryMirror _library(String uri) {
  return currentMirrorSystem().libraries.values.firstWhere(
        (LibraryMirror library) => library.uri.toString() == uri,
      );
}

Symbol _private(LibraryMirror library, String name) {
  return MirrorSystem.getSymbol(name, library);
}

RuntimeOptions _demoOptions({
  required String workdir,
  String tagsFile = '',
  bool skipTags = false,
}) {
  return RuntimeOptions(
    commandName: commandDemo,
    sourceProvider: 'github',
    sourceUrl: 'https://github.com/acme/source',
    sourceToken: '',
    targetProvider: 'gitlab',
    targetUrl: 'https://gitlab.com/acme/target',
    targetToken: '',
    migrationOrder: 'github-to-gitlab',
    skipTagMigration: skipTags,
    skipReleaseMigration: false,
    skipReleaseAssetMigration: false,
    fromTag: '',
    toTag: '',
    dryRun: false,
    nonInteractive: true,
    workdir: workdir,
    logFile: '',
    loadSession: false,
    saveSession: false,
    resumeSession: false,
    sessionFile: '',
    sessionTokenMode: 'env',
    sessionSourceTokenEnv: defaultSourceTokenEnv,
    sessionTargetTokenEnv: defaultTargetTokenEnv,
    settingsProfile: '',
    downloadWorkers: 4,
    releaseWorkers: 1,
    checkpointFile: '',
    tagsFile: tagsFile,
    noBanner: true,
    quiet: false,
    jsonOutput: false,
    progressBar: false,
    demoMode: true,
    demoReleases: 2,
    demoSleepSeconds: 0,
  );
}

void main() {
  _loadPrivateTargetLibraries();

  group('cli runtime support', () {
    test('printBanner, maskedTokenStatus, demoTags, and formatPreflightCheck expose expected formatting', () {
      final BufferConsoleOutput terminalOutput = BufferConsoleOutput(hasTerminal: true);
      final BufferConsoleOutput nonTerminalOutput = BufferConsoleOutput();
      final Directory temp = createTempDir('gfrm-private-cli-helpers-');
      final File tagsFile = File('${temp.path}/tags.txt')..writeAsStringSync('# comment\nv1.2.3\n\nv1.2.4\n');

      CliRuntimeSupport.printBanner(terminalOutput);
      CliRuntimeSupport.printBanner(nonTerminalOutput);

      final String empty = CliRuntimeSupport.maskedTokenStatus('  ');
      final String masked = CliRuntimeSupport.maskedTokenStatus('token');
      final List<String> tags = CliRuntimeSupport.demoTags(
        _demoOptions(
          workdir: temp.path,
          tagsFile: tagsFile.path,
        ),
      );
      final String noHint = CliRuntimeSupport.formatPreflightCheck(
        const PreflightCheck(
          status: PreflightCheckStatus.error,
          code: 'x',
          message: 'Plain message',
        ),
      );
      final String withHint = CliRuntimeSupport.formatPreflightCheck(
        const PreflightCheck(
          status: PreflightCheckStatus.warning,
          code: 'y',
          message: 'Hinted message',
          hint: 'Do the thing.',
        ),
      );

      expect(terminalOutput.stdoutLines, contains('Quick commands:'));
      expect(nonTerminalOutput.stdoutLines, isEmpty);
      expect(empty, '<empty>');
      expect(masked, '***');
      expect(tags, <String>['v1.2.3', 'v1.2.4']);
      expect(noHint, 'Plain message');
      expect(withHint, 'Hinted message Hint: Do the thing.');
    });

    test('runDemo writes summary artifacts and emits spinner output when logger is not silent', () async {
      final BufferConsoleOutput output = BufferConsoleOutput(
        hasTerminal: true,
        supportsAnsiEscapes: true,
      );
      final ConsoleLogger logger = ConsoleLogger(
        quiet: false,
        jsonOutput: false,
        output: output,
        silent: false,
      );
      final Directory temp = createTempDir('gfrm-private-run-demo-');
      final Directory resultsRoot = Directory('${temp.path}/results')..createSync(recursive: true);
      final Directory runWorkdir = Directory('${resultsRoot.path}/20260313-120000')..createSync(recursive: true);
      final RuntimeOptions options = _demoOptions(
        workdir: resultsRoot.path,
        skipTags: true,
      );

      final int exitCode = await CliRuntimeSupport.runDemo(
        options,
        logger,
        resultsRoot: resultsRoot,
        runWorkdir: runWorkdir,
      );

      expect(exitCode, 0);
      expect(output.rawWrites, isNotEmpty);
      expect(output.stdoutLines.join('\n'), contains('Migration summary'));
      expect(output.stdoutLines.join('\n'), contains("Tokens: source='<empty>' target='<empty>'"));

      final File summaryFile = File('${runWorkdir.path}/summary.json');
      expect(summaryFile.existsSync(), isTrue);
      final Map<String, dynamic> summary = jsonDecode(summaryFile.readAsStringSync()) as Map<String, dynamic>;
      expect(summary['command'], commandDemo);
      expect((summary['counts'] as Map<String, dynamic>)['tags_skipped'], 2);
      expect(File('${runWorkdir.path}/release-v3.2.1-notes.md').existsSync(), isTrue);
    });

    test('renderRunResult suppresses duplicate validation failure message after preflight error', () {
      final BufferConsoleOutput output = BufferConsoleOutput();
      final ConsoleLogger logger = ConsoleLogger(
        quiet: false,
        jsonOutput: false,
        output: output,
        silent: false,
      );

      final int exitCode = CliRuntimeSupport.renderRunResult(
        logger,
        const RunResult(
          status: RunStatus.validationFailure,
          exitCode: 1,
          resultsRootPath: '/tmp/results',
          runWorkdirPath: '/tmp/results/run',
          logPath: '/tmp/results/run/migration-log.jsonl',
          checkpointPath: '/tmp/results/checkpoints/state.jsonl',
          summaryPath: '/tmp/results/run/summary.json',
          failedTagsPath: '/tmp/results/run/failed-tags.txt',
          retryCommand: '',
          preflightChecks: <PreflightCheck>[
            PreflightCheck(
              status: PreflightCheckStatus.error,
              code: 'missing-source-token',
              message: 'Missing source token.',
              hint: 'Provide a token.',
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
      );

      expect(exitCode, 1);
      expect(output.stderrLines, hasLength(1));
      expect(output.stderrLines.single, contains('Missing source token.'));
    });

    test('renderRunResult emits primary failure when it was not already rendered by preflight', () {
      final BufferConsoleOutput output = BufferConsoleOutput();
      final ConsoleLogger logger = ConsoleLogger(
        quiet: false,
        jsonOutput: false,
        output: output,
        silent: false,
      );

      final int exitCode = CliRuntimeSupport.renderRunResult(
        logger,
        const RunResult(
          status: RunStatus.runtimeFailure,
          exitCode: 1,
          resultsRootPath: '/tmp/results',
          runWorkdirPath: '/tmp/results/run',
          logPath: '/tmp/results/run/migration-log.jsonl',
          checkpointPath: '/tmp/results/checkpoints/state.jsonl',
          summaryPath: '/tmp/results/run/summary.json',
          failedTagsPath: '/tmp/results/run/failed-tags.txt',
          retryCommand: '',
          preflightChecks: <PreflightCheck>[
            PreflightCheck(
              status: PreflightCheckStatus.warning,
              code: 'warn-only',
              message: 'Heads up.',
            ),
          ],
          failures: <RunFailure>[
            RunFailure(
              scope: RunFailure.scopeExecution,
              code: 'runtime-failed',
              message: 'Primary failure.',
              retryable: true,
            ),
          ],
        ),
      );

      expect(exitCode, 1);
      expect(output.stderrLines, contains('[ERROR] Primary failure.'));
    });

    test('buildRunRequest preserves the original runtime options object', () {
      final RuntimeOptions options = _demoOptions(workdir: '/tmp/results');

      final RunRequest request = CliRuntimeSupport.buildRunRequest(options);

      expect(identical(request.options, options), isTrue);
    });
  });

  group('private config helpers', () {
    test('_resolveTokenFromSession handles plain token, empty env name, and env lookup', () {
      final LibraryMirror configMirror = _library('package:gfrm_dart/src/config.dart');

      final String plain = configMirror.invoke(
        _private(configMirror, '_resolveTokenFromSession'),
        const <Object>[],
        <Symbol, Object>{
          #tokenPlain: 'plain-token',
          #tokenEnv: 'IGNORED_TOKEN',
          #env: <String, String>{},
        },
      ).reflectee as String;

      final String empty = configMirror.invoke(
        _private(configMirror, '_resolveTokenFromSession'),
        const <Object>[],
        <Symbol, Object>{
          #tokenPlain: '',
          #tokenEnv: '',
          #env: <String, String>{},
        },
      ).reflectee as String;

      final String fromEnv = configMirror.invoke(
        _private(configMirror, '_resolveTokenFromSession'),
        const <Object>[],
        <Symbol, Object>{
          #tokenPlain: '',
          #tokenEnv: 'SESSION_TOKEN',
          #env: <String, String>{'SESSION_TOKEN': 'env-token'},
        },
      ).reflectee as String;

      expect(plain, 'plain-token');
      expect(empty, isEmpty);
      expect(fromEnv, 'env-token');
    });

    test('_resolveTokenWithFallback prefers explicit token, then settings, then aliases', () {
      final LibraryMirror configMirror = _library('package:gfrm_dart/src/config.dart');

      final String explicit = configMirror.invoke(
        _private(configMirror, '_resolveTokenWithFallback'),
        const <Object>[],
        <Symbol, Object>{
          #providedToken: 'explicit-token',
          #provider: 'github',
          #profile: 'work',
          #settingsPayload: <String, dynamic>{},
          #sideEnvName: defaultSourceTokenEnv,
          #env: <String, String>{},
        },
      ).reflectee as String;

      final String fromSettings = configMirror.invoke(
        _private(configMirror, '_resolveTokenWithFallback'),
        const <Object>[],
        <Symbol, Object>{
          #providedToken: '',
          #provider: 'github',
          #profile: 'work',
          #settingsPayload: <String, dynamic>{
            'profiles': <String, dynamic>{
              'work': <String, dynamic>{
                'providers': <String, dynamic>{
                  'github': <String, dynamic>{'token_plain': 'settings-token'},
                },
              },
            },
          },
          #sideEnvName: defaultSourceTokenEnv,
          #env: <String, String>{},
        },
      ).reflectee as String;

      final String fromAlias = configMirror.invoke(
        _private(configMirror, '_resolveTokenWithFallback'),
        const <Object>[],
        <Symbol, Object>{
          #providedToken: '',
          #provider: 'github',
          #profile: 'work',
          #settingsPayload: <String, dynamic>{},
          #sideEnvName: defaultSourceTokenEnv,
          #env: <String, String>{defaultSourceTokenEnv: 'alias-token'},
        },
      ).reflectee as String;

      expect(explicit, 'explicit-token');
      expect(fromSettings, 'settings-token');
      expect(fromAlias, 'alias-token');
    });
  });

  group('private http helpers', () {
    test('_isRateLimitedForbidden recognizes headers and body markers', () {
      final LibraryMirror httpMirror = _library('package:gfrm_dart/src/core/http.dart');
      final HttpClientHelper helper = HttpClientHelper();
      final InstanceMirror instance = reflect(helper);

      final bool fromRetryAfter = instance.invoke(
        _private(httpMirror, '_isRateLimitedForbidden'),
        const <Object>[],
        <Symbol, Object>{
          #headers: Headers.fromMap(<String, List<String>>{
            'retry-after': <String>['1']
          }),
          #body: 'forbidden',
        },
      ).reflectee as bool;
      final bool fromXRateLimit = instance.invoke(
        _private(httpMirror, '_isRateLimitedForbidden'),
        const <Object>[],
        <Symbol, Object>{
          #headers: Headers.fromMap(<String, List<String>>{
            'x-ratelimit-remaining': <String>['0']
          }),
          #body: 'forbidden',
        },
      ).reflectee as bool;
      final bool fromRateLimit = instance.invoke(
        _private(httpMirror, '_isRateLimitedForbidden'),
        const <Object>[],
        <Symbol, Object>{
          #headers: Headers.fromMap(<String, List<String>>{
            'ratelimit-remaining': <String>['0']
          }),
          #body: 'forbidden',
        },
      ).reflectee as bool;
      final bool fromBody = instance.invoke(
        _private(httpMirror, '_isRateLimitedForbidden'),
        const <Object>[],
        <Symbol, Object>{
          #headers: Headers(),
          #body: 'Too many requests right now',
        },
      ).reflectee as bool;

      expect(fromRetryAfter, isTrue);
      expect(fromXRateLimit, isTrue);
      expect(fromRateLimit, isTrue);
      expect(fromBody, isTrue);
    });

    test('_safePreviewLength, _nextBackoffMillis, _parseRetryAfterSeconds, and _waitWithRetryAfter behave as expected',
        () {
      final LibraryMirror httpMirror = _library('package:gfrm_dart/src/core/http.dart');
      final HttpClientHelper helper = HttpClientHelper();
      final InstanceMirror instance = reflect(helper);

      final int preview =
          instance.invoke(_private(httpMirror, '_safePreviewLength'), <Object>['x' * 600]).reflectee as int;
      final int backoff = instance.invoke(
          _private(httpMirror, '_nextBackoffMillis'), <Object>[const Duration(milliseconds: 300)]).reflectee as int;
      final int? emptyValues = instance
          .invoke(_private(httpMirror, '_parseRetryAfterSeconds'), <Object>[const <String>[]]).reflectee as int?;
      final int? blankValue = instance.invoke(_private(httpMirror, '_parseRetryAfterSeconds'), <Object>[
        const <String>['   '],
      ]).reflectee as int?;
      final int? decimalValue = instance.invoke(_private(httpMirror, '_parseRetryAfterSeconds'), <Object>[
        const <String>['0.2'],
      ]).reflectee as int?;
      final int? invalidValue = instance.invoke(_private(httpMirror, '_parseRetryAfterSeconds'), <Object>[
        const <String>['soon'],
      ]).reflectee as int?;
      final Duration unchanged = instance.invoke(
        _private(httpMirror, '_waitWithRetryAfter'),
        <Object?>[const Duration(milliseconds: 250), null],
      ).reflectee as Duration;
      final Duration widened = instance.invoke(
        _private(httpMirror, '_waitWithRetryAfter'),
        <Object>[const Duration(milliseconds: 250), 2],
      ).reflectee as Duration;

      expect(preview, 300);
      expect(backoff, 750);
      expect(emptyValues, isNull);
      expect(blankValue, isNull);
      expect(decimalValue, 1);
      expect(invalidValue, isNull);
      expect(unchanged, const Duration(milliseconds: 250));
      expect(widened, const Duration(seconds: 2));
    });
  });

  group('private logging helpers', () {
    test('_resolveTty evaluates ansi, quiet, json, and silent gates', () {
      final LibraryMirror loggingMirror = _library('package:gfrm_dart/src/core/logging.dart');
      final ClassMirror loggerClass = reflectClass(ConsoleLogger);
      final BufferConsoleOutput ansiOutput = BufferConsoleOutput(supportsAnsiEscapes: true);
      final BufferConsoleOutput plainOutput = BufferConsoleOutput(supportsAnsiEscapes: false);

      final bool ttyEnabled = loggerClass.invoke(
        _private(loggingMirror, '_resolveTty'),
        <Object>[ansiOutput, false, false, false],
      ).reflectee as bool;
      final bool ttySilent = loggerClass.invoke(
        _private(loggingMirror, '_resolveTty'),
        <Object>[ansiOutput, true, false, false],
      ).reflectee as bool;
      final bool ttyQuiet = loggerClass.invoke(
        _private(loggingMirror, '_resolveTty'),
        <Object>[ansiOutput, false, true, false],
      ).reflectee as bool;
      final bool ttyJson = loggerClass.invoke(
        _private(loggingMirror, '_resolveTty'),
        <Object>[ansiOutput, false, false, true],
      ).reflectee as bool;
      final bool ttyNoAnsi = loggerClass.invoke(
        _private(loggingMirror, '_resolveTty'),
        <Object>[plainOutput, false, false, false],
      ).reflectee as bool;

      expect(ttyEnabled, isTrue);
      expect(ttySilent, isFalse);
      expect(ttyQuiet, isFalse);
      expect(ttyJson, isFalse);
      expect(ttyNoAnsi, isFalse);
    });

    test('_emit and _stopSpinnerAndEmit honor silent, streams, and quiet suppression', () {
      final LibraryMirror loggingMirror = _library('package:gfrm_dart/src/core/logging.dart');
      final BufferConsoleOutput plainOutput = BufferConsoleOutput();
      final BufferConsoleOutput jsonOutput = BufferConsoleOutput();
      final BufferConsoleOutput silentOutput = BufferConsoleOutput();

      final ConsoleLogger plainLogger = ConsoleLogger(
        quiet: false,
        jsonOutput: false,
        output: plainOutput,
        silent: false,
      );
      final ConsoleLogger jsonLogger = ConsoleLogger(
        quiet: false,
        jsonOutput: true,
        output: jsonOutput,
        silent: false,
      );
      final ConsoleLogger silentLogger = ConsoleLogger(
        quiet: false,
        jsonOutput: false,
        output: silentOutput,
        silent: true,
      );
      final ConsoleLogger quietLogger = ConsoleLogger(
        quiet: true,
        jsonOutput: false,
        output: BufferConsoleOutput(),
        silent: false,
      );

      reflect(plainLogger).invoke(
        _private(loggingMirror, '_emit'),
        <Object>[LoggerPrefix.info, 'plain info'],
        <Symbol, Object>{#useErrorStream: false},
      );
      reflect(plainLogger).invoke(
        _private(loggingMirror, '_emit'),
        <Object>[LoggerPrefix.error, 'plain error'],
        <Symbol, Object>{#useErrorStream: true},
      );
      reflect(jsonLogger).invoke(
        _private(loggingMirror, '_emit'),
        <Object>[LoggerPrefix.warning, 'json warning'],
        <Symbol, Object>{#useErrorStream: true},
      );
      reflect(silentLogger).invoke(
        _private(loggingMirror, '_emit'),
        <Object>[LoggerPrefix.info, 'ignored'],
        <Symbol, Object>{#useErrorStream: false},
      );
      reflect(quietLogger).invoke(
        _private(loggingMirror, '_stopSpinnerAndEmit'),
        <Object>[LoggerPrefix.info, 'quiet info'],
        <Symbol, Object>{#useErrorStream: false},
      );

      expect(plainOutput.stdoutLines, contains('[INFO] plain info'));
      expect(plainOutput.stderrLines, contains('[ERROR] plain error'));
      expect(jsonOutput.stderrLines.single, allOf(contains('"level":"warn"'), contains('json warning')));
      expect(silentOutput.stdoutLines, isEmpty);
      expect(silentOutput.stderrLines, isEmpty);
    });

    test('_renderSpinner exits early when inactive and writes frames when active', () {
      final LibraryMirror loggingMirror = _library('package:gfrm_dart/src/core/logging.dart');
      final BufferConsoleOutput output = BufferConsoleOutput(
        hasTerminal: true,
        supportsAnsiEscapes: true,
      );
      final ConsoleLogger logger = ConsoleLogger(
        quiet: false,
        jsonOutput: false,
        output: output,
        silent: false,
      );
      final InstanceMirror instance = reflect(logger);

      instance.invoke(_private(loggingMirror, '_renderSpinner'), const <Object>[]);
      expect(output.rawWrites, isEmpty);

      expect(logger.startSpinner('spinning'), isTrue);
      final int writesBefore = output.rawWrites.length;

      instance.invoke(_private(loggingMirror, '_renderSpinner'), const <Object>[]);

      expect(output.rawWrites.length, greaterThan(writesBefore));
      expect(output.rawWrites.last, contains('spinning'));
    });
  });
}
