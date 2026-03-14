import 'dart:convert';
import 'dart:io';

import '../application/preflight_check.dart';
import '../application/run_failure.dart';
import '../application/run_request.dart';
import '../application/run_result.dart';
import '../core/console_output.dart';
import '../core/jsonl.dart';
import '../core/logging.dart';
import '../models/runtime_options.dart';

final class CliRuntimeSupport {
  const CliRuntimeSupport._();

  static void printBanner(ConsoleOutput output) {
    if (!output.hasTerminal) {
      return;
    }

    final String logo = r'''
   ____ _ _      _____
  / ___(_) |_   |  ___|__  _ __ __ _  ___
 | |  _| | __|  | |_ / _ \| '__/ _` |/ _ \
 | |_| | | |_   |  _| (_) | | | (_| |  __/
  \____|_|\__|  |_|  \___/|_|  \__, |_|\___|
                               |___/
  ____      _                        __  __ _                  _
 |  _ \ ___| | ___  __ _ ___  ___   |  \/  (_) __ _ _ __ __ _| |_ ___  _ __
 | |_) / _ \ |/ _ \/ _` / __|/ _ \  | |\/| | |/ _` | '__/ _` | __/ _ \| '__|
 |  _ <  __/ |  __/ (_| \__ \  __/  | |  | | | (_| | | | (_| | || (_) | |
 |_| \_\___|_|\___|\__,_|___/\___|  |_|  |_|_|\__, |_|  \__,_|\__\___/|_|
                                               |___/
''';

    output.writeOutLine('');
    output.writeOutLine(logo);
    output.writeOutLine('Migrate tags, releases, changelog and assets between Git forges.');
    output.writeOutLine('Quick commands:');
    output.writeOutLine('  $publicCommandName migrate --help');
    output.writeOutLine('  $publicCommandName resume --session-file ./sessions/last-session.json');
    output.writeOutLine('  $publicCommandName demo --demo-releases 10');
    output.writeOutLine('  $publicCommandName setup');
    output.writeOutLine('  $publicCommandName settings show');
    output.writeOutLine('');
  }

  static String maskedTokenStatus(String tokenValue) {
    return tokenValue.trim().isEmpty ? '<empty>' : '***';
  }

  static List<String> demoTags(RuntimeOptions options) {
    if (options.tagsFile.isNotEmpty) {
      final File file = File(options.tagsFile);
      if (file.existsSync()) {
        final List<String> tags = file
            .readAsLinesSync()
            .map((String line) => line.trim())
            .where((String line) => line.isNotEmpty && !line.startsWith('#'))
            .take(options.demoReleases)
            .toList(growable: false);

        if (tags.isNotEmpty) {
          return tags;
        }
      }
    }

    final List<String> tags = <String>[];
    for (int index = 0; index < options.demoReleases; index += 1) {
      tags.add(index == 0 ? 'v3.2.1' : 'v3.${2 + index}.0');
    }

    return tags;
  }

  static Future<int> runDemo(
    RuntimeOptions options,
    ConsoleLogger logger, {
    required Directory resultsRoot,
    required Directory runWorkdir,
  }) async {
    final List<String> tags = demoTags(options);
    final String logPath = options.logFile.isNotEmpty ? options.logFile : '${runWorkdir.path}/migration-log.jsonl';
    await File(logPath).writeAsString('');

    logger.info('DEMO MODE enabled (no network calls, no provider API interactions)');
    logger.info('  Source: ${options.sourceProvider} (${options.sourceUrl})');
    logger.info('  Target: ${options.targetProvider} (${options.targetUrl})');
    logger.info(
        "  Tokens: source='${maskedTokenStatus(options.sourceToken)}' target='${maskedTokenStatus(options.targetToken)}'");
    logger.info('  Simulated releases: ${tags.length}');
    logger.info('  Sleep per release: ${options.demoSleepSeconds.toStringAsFixed(2)}s');
    logger.info('  Results root: ${resultsRoot.path}');
    logger.info('  Run workdir: ${runWorkdir.path}');

    final DateTime startedAll = DateTime.now();
    int created = 0;
    for (int index = 0; index < tags.length; index += 1) {
      final String tag = tags[index];
      final int percent = tags.isEmpty ? 0 : ((index + 1) * 100 ~/ tags.length);
      final String progress = '[${index + 1}/${tags.length} - ${percent.toString().padLeft(3)}%] Release $tag';

      final bool spinnerStarted = logger.startSpinner(progress);
      final DateTime started = DateTime.now();
      await Future<void>.delayed(Duration(milliseconds: (options.demoSleepSeconds * 1000).round()));
      if (spinnerStarted) {
        logger.stopSpinner();
      }

      final File notesFile = File('${runWorkdir.path}/release-$tag-notes.md');
      await notesFile.writeAsString(
        '# $tag\n\n'
        'This is a local demo run for CLI recording.\n'
        'No real API call was executed.\n',
      );

      final int assetCount = (index + 1) % 2 == 0 ? 6 : 7;
      final int durationMs = DateTime.now().difference(started).inMilliseconds;
      JsonlLogWriter.appendLog(
        logPath,
        status: 'created',
        tag: tag,
        message: 'Demo: release created',
        assetCount: assetCount,
        durationMs: durationMs,
        dryRun: options.dryRun,
      );
      logger.info('[$tag] created with $assetCount asset(s) [demo]');
      created += 1;
    }

    final File failedTagsFile = File('${runWorkdir.path}/failed-tags.txt');
    await failedTagsFile.writeAsString('');

    final int durationMs = DateTime.now().difference(startedAll).inMilliseconds;
    final Map<String, Object> summary = <String, Object>{
      'schema_version': 2,
      'command': commandDemo,
      'demo_mode': true,
      'order': options.migrationOrder,
      'source': options.sourceUrl,
      'target': options.targetUrl,
      'counts': <String, int>{
        'tags_created': 0,
        'tags_skipped': options.skipTagMigration ? tags.length : 0,
        'tags_failed': 0,
        'releases_created': created,
        'releases_updated': 0,
        'releases_skipped': 0,
        'releases_failed': 0,
      },
      'duration_ms': durationMs,
      'paths': <String, String>{
        'jsonl_log': logPath,
        'workdir': runWorkdir.path,
        'failed_tags': failedTagsFile.path,
      },
    };

    final File summaryFile = File('${runWorkdir.path}/summary.json');
    await summaryFile.writeAsString('${const JsonEncoder.withIndent('  ').convert(summary)}\n');

    logger.info('Migration summary');
    logger.info('  Mode: demo');
    logger.info('  Releases created: $created');
    logger.info('  Releases failed: 0');
    logger.info('  JSONL log: $logPath');
    logger.info('  Summary JSON: ${summaryFile.path}');
    logger.info('  Failed tags file: ${failedTagsFile.path}');

    return 0;
  }

  static RunRequest buildRunRequest(RuntimeOptions options) {
    return RunRequest(options: options);
  }

  static int renderRunResult(ConsoleLogger logger, RunResult result) {
    final Set<String> renderedPreflightErrorCodes = <String>{};

    for (final PreflightCheck check in result.preflightChecks) {
      if (check.status == PreflightCheckStatus.warning) {
        logger.warn(formatPreflightCheck(check));
      }

      if (check.status == PreflightCheckStatus.error) {
        logger.error(formatPreflightCheck(check));
        renderedPreflightErrorCodes.add(check.code);
      }
    }

    if (!result.isSuccess && result.failures.isNotEmpty) {
      final RunFailure primaryFailure = result.failures.first;
      final bool alreadyRenderedPreflightError = primaryFailure.scope == RunFailure.scopeValidation &&
          renderedPreflightErrorCodes.contains(primaryFailure.code);
      if (!alreadyRenderedPreflightError) {
        logger.error(primaryFailure.message);
      }
    }

    return result.exitCode;
  }

  static String formatPreflightCheck(PreflightCheck check) {
    if (check.hint == null || check.hint!.trim().isEmpty) {
      return check.message;
    }

    return '${check.message} Hint: ${check.hint}';
  }
}
