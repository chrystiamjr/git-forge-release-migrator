import 'dart:convert';
import 'dart:io';

import 'cli/settings_setup_command_handler.dart';
import 'config.dart';
import 'core/adapters/provider_adapter.dart';
import 'core/jsonl.dart';
import 'core/logging.dart';
import 'core/session_store.dart';
import 'migrations/engine.dart';
import 'models/runtime_options.dart';
import 'providers/registry.dart';

void _printBanner() {
  if (!stdout.hasTerminal) {
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

  stdout.writeln();
  stdout.writeln(logo);
  stdout.writeln('Migrate tags, releases, changelog and assets between Git forges.');
  stdout.writeln('Quick commands:');
  stdout.writeln('  $publicCommandName migrate --help');
  stdout.writeln('  $publicCommandName resume --session-file ./sessions/last-session.json');
  stdout.writeln('  $publicCommandName demo --demo-releases 10');
  stdout.writeln('  $publicCommandName setup');
  stdout.writeln('  $publicCommandName settings show');
  stdout.writeln();
}

Directory _allocateRunWorkdir(Directory baseDir) {
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

class _PreparedRun {
  _PreparedRun({
    required this.options,
    required this.resultsRoot,
    required this.runWorkdir,
  });

  final RuntimeOptions options;
  final Directory resultsRoot;
  final Directory runWorkdir;
}

_PreparedRun _prepareRun(RuntimeOptions options) {
  final Directory resultsRoot = Directory(options.effectiveWorkdir());
  if (!resultsRoot.existsSync()) {
    resultsRoot.createSync(recursive: true);
  }

  final Directory runWorkdir = _allocateRunWorkdir(resultsRoot);
  runWorkdir.createSync(recursive: true);

  final RuntimeOptions withWorkdir = options.copyWith(
    workdir: runWorkdir.path,
    logFile: options.logFile.isEmpty ? '${runWorkdir.path}/migration-log.jsonl' : options.logFile,
    checkpointFile:
        options.checkpointFile.isEmpty ? '${resultsRoot.path}/checkpoints/state.jsonl' : options.checkpointFile,
  );

  return _PreparedRun(
    options: withWorkdir,
    resultsRoot: resultsRoot,
    runWorkdir: runWorkdir,
  );
}

void _saveSessionIfEnabled(RuntimeOptions options, ConsoleLogger logger) {
  if (!options.saveSession && !options.resumeSession) {
    return;
  }

  final String sessionFile = options.effectiveSessionFile();
  SessionStore.saveSession(sessionFile, options.toSessionPayload());
  logger.info('Session saved to $sessionFile');
  if (options.sessionTokenMode == 'plain') {
    logger.warn('Session file stores tokens in plain text. Keep file permissions restricted.');
  } else {
    logger.info('Session stores token env references only. Keep those environment variables available for resume.');
  }
}

void _logRuntimeHeader(
  RuntimeOptions options,
  ProviderRef sourceRef,
  ProviderRef targetRef,
  Directory resultsRoot,
  Directory runWorkdir,
  ConsoleLogger logger,
) {
  logger.info('Dart runtime loaded');
  logger.info('  Command: ${options.commandName}');
  logger.info('  Source: ${options.sourceProvider} (${sourceRef.resource})');
  logger.info('  Target: ${options.targetProvider} (${targetRef.resource})');
  logger.info('  Order: ${options.migrationOrder}');
  logger.info(
    '  Tag range: ${options.fromTag.isEmpty ? '<start>' : options.fromTag} -> ${options.toTag.isEmpty ? '<end>' : options.toTag}',
  );
  logger.info('  Dry-run: ${options.dryRun}');
  logger.info('  Skip tags: ${options.skipTagMigration}');
  logger.info('  Download workers: ${options.downloadWorkers}');
  logger.info('  Release workers: ${options.releaseWorkers}');
  logger.info('  Session token mode: ${options.sessionTokenMode}');
  if (options.settingsProfile.isNotEmpty) {
    logger.info('  Settings profile: ${options.settingsProfile}');
  }
  logger.info('  Checkpoint file: ${options.effectiveCheckpointFile()}');
  logger.info('  Results root: ${resultsRoot.path}');
  logger.info('  Run workdir: ${runWorkdir.path}');
  if (options.tagsFile.isNotEmpty) {
    logger.info('  Tags file: ${options.tagsFile}');
  }
}

List<String> _demoTags(RuntimeOptions options) {
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

Future<int> _runDemo(
  RuntimeOptions options,
  ConsoleLogger logger, {
  required Directory resultsRoot,
  required Directory runWorkdir,
}) async {
  final List<String> tags = _demoTags(options);
  final String logPath = options.logFile.isNotEmpty ? options.logFile : '${runWorkdir.path}/migration-log.jsonl';
  File(logPath).writeAsStringSync('');

  logger.info('DEMO MODE enabled (no network calls, no provider API interactions)');
  logger.info('  Source: ${options.sourceProvider} (${options.sourceUrl})');
  logger.info('  Target: ${options.targetProvider} (${options.targetUrl})');
  logger.info("  Tokens: source='${options.sourceToken}' target='${options.targetToken}'");
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
    notesFile.writeAsStringSync(
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
  failedTagsFile.writeAsStringSync('');

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
  summaryFile.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(summary)}\n');

  logger.info('Migration summary');
  logger.info('  Mode: demo');
  logger.info('  Releases created: $created');
  logger.info('  Releases failed: 0');
  logger.info('  JSONL log: $logPath');
  logger.info('  Summary JSON: ${summaryFile.path}');
  logger.info('  Failed tags file: ${failedTagsFile.path}');

  return 0;
}

Future<int> _executeMigration(
    RuntimeOptions options, ConsoleLogger logger, Directory resultsRoot, Directory runWorkdir) async {
  final ProviderRegistry registry = ProviderRegistry.defaults();
  final ProviderAdapter sourceAdapter = registry.get(options.sourceProvider);
  final ProviderAdapter targetAdapter = registry.get(options.targetProvider);

  final ProviderRef sourceRef = sourceAdapter.parseUrl(options.sourceUrl);
  final ProviderRef targetRef = targetAdapter.parseUrl(options.targetUrl);
  _saveSessionIfEnabled(options, logger);
  _logRuntimeHeader(options, sourceRef, targetRef, resultsRoot, runWorkdir, logger);

  final MigrationEngine engine = MigrationEngine(registry: registry, logger: logger);
  await engine.run(options, sourceRef, targetRef);
  logger.stopSpinner();

  return 0;
}

Future<int> _runCli(List<String> argv) async {
  ConsoleLogger? logger;
  try {
    final CliRequest request = CliRequestParser.parseCliRequest(argv);
    if (request.command == 'help') {
      stdout.writeln(request.usage);
      return 0;
    }

    if (request.command == commandSettings) {
      logger = ConsoleLogger(quiet: false, jsonOutput: false);
      return SettingsSetupCommandHandler(logger: logger).runSettingsCommand(request.settings!);
    }

    if (request.command == commandSetup) {
      logger = ConsoleLogger(quiet: false, jsonOutput: false);
      return SettingsSetupCommandHandler(logger: logger).runSetupCommand(request.setup!);
    }

    final RuntimeOptions initialOptions = request.options!;
    logger = ConsoleLogger(quiet: initialOptions.quiet, jsonOutput: initialOptions.jsonOutput);
    if (!initialOptions.noBanner && !initialOptions.jsonOutput && !initialOptions.quiet) {
      _printBanner();
    }

    final _PreparedRun prepared = _prepareRun(initialOptions);
    final RuntimeOptions options = prepared.options;

    if (options.commandName == commandDemo) {
      return _runDemo(
        options,
        logger,
        resultsRoot: prepared.resultsRoot,
        runWorkdir: prepared.runWorkdir,
      );
    }

    return _executeMigration(options, logger, prepared.resultsRoot, prepared.runWorkdir);
  } catch (exc) {
    try {
      logger?.stopSpinner();
    } catch (_) {}

    if (logger != null) {
      logger.error(exc.toString());
    } else {
      stderr.writeln('[ERROR] $exc');
    }

    return 1;
  }
}

final class CliRunner {
  const CliRunner._();

  static Future<int> run(List<String> argv) async {
    return _runCli(argv);
  }
}
