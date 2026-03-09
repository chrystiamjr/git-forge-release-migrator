import 'dart:convert';
import 'dart:io';

import 'config.dart';
import 'core/adapters/provider_adapter.dart';
import 'core/jsonl.dart';
import 'core/logging.dart';
import 'core/settings.dart';
import 'core/session_store.dart';
import 'migrations/engine.dart';
import 'models.dart';
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

String _promptLine(String prompt) {
  stdout.write(prompt);
  return (stdin.readLineSync() ?? '').trim();
}

bool _hasConfiguredTokenValues(Map<String, dynamic> payload) {
  final dynamic profilesRaw = payload['profiles'];
  if (profilesRaw is! Map<String, dynamic>) {
    return false;
  }

  for (final dynamic profileRaw in profilesRaw.values) {
    if (profileRaw is! Map<String, dynamic>) {
      continue;
    }

    final dynamic providersRaw = profileRaw['providers'];
    if (providersRaw is! Map<String, dynamic>) {
      continue;
    }

    for (final dynamic providerRaw in providersRaw.values) {
      if (providerRaw is! Map<String, dynamic>) {
        continue;
      }

      final String tokenEnv = (providerRaw['token_env'] ?? '').toString().trim();
      final String tokenPlain = (providerRaw['token_plain'] ?? '').toString().trim();
      if (tokenEnv.isNotEmpty || tokenPlain.isNotEmpty) {
        return true;
      }
    }
  }

  return false;
}

bool _readYesNo(String prompt, {bool defaultValue = false}) {
  final String raw = _promptLine(prompt).trim().toLowerCase();
  if (raw.isEmpty) {
    return defaultValue;
  }

  return raw == 'y' || raw == 'yes';
}

String _suggestProviderEnvName({
  required String provider,
  required Set<String> knownEnvNames,
  required bool fallbackAlias,
}) {
  String suggested = suggestEnvName(provider, knownEnvNames);
  if (suggested.isNotEmpty) {
    return suggested;
  }

  for (final String alias in envAliases(provider)) {
    if (knownEnvNames.contains(alias)) {
      suggested = alias;
      break;
    }
  }

  if (suggested.isNotEmpty || !fallbackAlias) {
    return suggested;
  }

  final List<String> providerAliases = providerEnvAliases[provider] ?? const <String>[];
  if (providerAliases.isNotEmpty) {
    return providerAliases.first;
  }

  return '';
}

String _chooseSetupProfile({
  required SetupCommandOptions options,
  required Map<String, dynamic> effectiveSettings,
}) {
  final String requested = options.profile.trim();
  if (requested.isNotEmpty) {
    return requested;
  }

  final String fallbackProfile = resolveProfileName(effectiveSettings, '');
  if (options.assumeYes) {
    return fallbackProfile;
  }

  final String entered = _promptLine('Profile name [$fallbackProfile]: ');
  if (entered.isEmpty) {
    return fallbackProfile;
  }

  return entered;
}

bool _chooseSetupScope(SetupCommandOptions options) {
  if (options.localScope) {
    return true;
  }

  if (options.assumeYes) {
    return false;
  }

  return _readYesNo('Store settings in ./.gfrm/settings.yaml? [y/N]: ');
}

String _chooseProviderEnvName({
  required String provider,
  required String suggested,
  required bool assumeYes,
}) {
  if (assumeYes) {
    return suggested;
  }

  final String prompt = suggested.isEmpty
      ? '$provider token env name (leave empty to skip): '
      : '$provider token env name [$suggested]: ';
  final String chosen = _promptLine(prompt);
  if (chosen.isEmpty) {
    return suggested;
  }

  return chosen;
}

void _printSetupExamples(String profile) {
  final String effectiveProfile = profile.trim().isEmpty ? 'default' : profile.trim();
  stdout.writeln();
  stdout.writeln('Next commands:');
  stdout.writeln('  $publicCommandName settings show --profile $effectiveProfile');
  stdout.writeln(
    '  $publicCommandName migrate --source-provider <provider> --source-url <url> --target-provider <provider> '
    '--target-url <url> --settings-profile $effectiveProfile',
  );
  stdout.writeln('  $publicCommandName resume --settings-profile $effectiveProfile');
  stdout.writeln();
}

int _runSettingsInit(SettingsCommandOptions options, ConsoleLogger logger) {
  final SettingsScopeData scope = readScopeSettings(local: options.localScope);
  final Map<String, dynamic> effective = loadEffectiveSettings();
  final String profile = resolveProfileName(effective, options.profile);
  final Set<String> knownEnvNames = <String>{
    ...Platform.environment.keys,
    ...scanShellExportNames(),
  };

  Map<String, dynamic> updated = scope.payload;
  bool changed = false;
  const List<String> providerOrder = <String>['github', 'gitlab', 'bitbucket'];
  for (final String provider in providerOrder) {
    String defaultEnv = suggestEnvName(provider, knownEnvNames);
    if (defaultEnv.isEmpty) {
      for (final String candidate in envAliases(provider)) {
        if (knownEnvNames.contains(candidate)) {
          defaultEnv = candidate;
          break;
        }
      }
    }

    String chosen = '';
    if (options.assumeYes) {
      chosen = defaultEnv;
    } else {
      final String prompt = defaultEnv.isEmpty
          ? '$provider token env name (leave empty to skip): '
          : '$provider token env name [$defaultEnv]: ';
      chosen = _promptLine(prompt);
      if (chosen.isEmpty) {
        chosen = defaultEnv;
      }
    }

    if (chosen.isEmpty) {
      continue;
    }

    updated = setProviderTokenEnv(updated, profile: profile, provider: provider, envName: chosen);
    changed = true;
  }

  if (changed) {
    writeSettingsFile(scope.path, updated);
    logger.info('Settings initialized at ${scope.path}');
  } else {
    logger.info('No settings were changed');
  }

  return 0;
}

int _runSetupCommand(SetupCommandOptions options, ConsoleLogger logger) {
  final Map<String, dynamic> effective = loadEffectiveSettings();
  final String profile = _chooseSetupProfile(options: options, effectiveSettings: effective);
  if (_hasConfiguredTokenValues(effective) && !options.force) {
    logger.info('Detected existing settings token configuration. Setup wizard skipped.');
    logger.info('Run `$publicCommandName setup --force` to rebuild token mappings.');
    _printSetupExamples(profile);
    return 0;
  }

  final bool localScope = _chooseSetupScope(options);
  final SettingsScopeData scope = readScopeSettings(local: localScope);
  final Set<String> knownEnvNames = <String>{
    ...Platform.environment.keys,
    ...scanShellExportNames(),
  };

  Map<String, dynamic> updated = scope.payload;
  bool changed = false;
  const List<String> providerOrder = <String>['github', 'gitlab', 'bitbucket'];
  for (final String provider in providerOrder) {
    final String suggested = _suggestProviderEnvName(
      provider: provider,
      knownEnvNames: knownEnvNames,
      fallbackAlias: options.assumeYes,
    );
    final String chosen = _chooseProviderEnvName(
      provider: provider,
      suggested: suggested,
      assumeYes: options.assumeYes,
    );
    if (chosen.isEmpty) {
      continue;
    }

    updated = setProviderTokenEnv(
      updated,
      profile: profile,
      provider: provider,
      envName: chosen,
    );
    changed = true;
  }

  if (changed) {
    writeSettingsFile(scope.path, updated);
    logger.info('Setup finished. Settings written to ${scope.path}.');
  } else {
    logger.warn('Setup finished without token mappings. No settings file changes were required.');
  }

  _printSetupExamples(profile);
  return 0;
}

int _runSettingsCommand(SettingsCommandOptions options, ConsoleLogger logger) {
  final String action = options.action.trim();
  if (action == settingsActionShow) {
    final Map<String, dynamic> effective = loadEffectiveSettings();
    final String profile = resolveProfileName(effective, options.profile);
    final Map<String, dynamic> masked = maskSettingsSecrets(effective);
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
        'profile': profile,
        'settings': masked,
      }),
    );
    return 0;
  }

  if (action == settingsActionInit) {
    return _runSettingsInit(options, logger);
  }

  final String provider = options.provider.trim();
  if (!supportedSettingsProviders.contains(provider)) {
    throw ArgumentError('--provider must be one of: github, gitlab, bitbucket');
  }

  final SettingsScopeData scope = readScopeSettings(local: options.localScope);
  final Map<String, dynamic> effective = loadEffectiveSettings();
  final String profile = resolveProfileName(effective, options.profile);
  Map<String, dynamic> updated = scope.payload;

  if (action == settingsActionSetTokenEnv) {
    final String envName = options.envName.trim();
    if (envName.isEmpty) {
      throw ArgumentError('--env-name is required for settings set-token-env');
    }

    updated = setProviderTokenEnv(updated, profile: profile, provider: provider, envName: envName);
    writeSettingsFile(scope.path, updated);
    logger.info(
      "Stored env-token reference for provider '$provider' in profile '$profile' at ${scope.path}",
    );
    return 0;
  }

  if (action == settingsActionSetTokenPlain) {
    String token = options.token;
    if (token.isEmpty) {
      token = _promptLine('Plain token for $provider: ');
    }

    if (token.isEmpty) {
      throw ArgumentError('Token value is empty');
    }

    updated = setProviderTokenPlain(updated, profile: profile, provider: provider, token: token);
    writeSettingsFile(scope.path, updated);
    logger.warn('Token stored in plain text. Keep file permissions restricted.');
    logger.info("Stored plain token for provider '$provider' in profile '$profile' at ${scope.path}");
    return 0;
  }

  if (action == settingsActionUnsetToken) {
    updated = unsetProviderToken(updated, profile: profile, provider: provider);
    writeSettingsFile(scope.path, updated);
    logger.info("Removed token settings for provider '$provider' in profile '$profile' at ${scope.path}");
    return 0;
  }

  throw ArgumentError('Unknown settings action: $action');
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
  saveSession(sessionFile, options.toSessionPayload());
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
    appendLog(
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

Future<int> runCli(List<String> argv) async {
  ConsoleLogger? logger;
  try {
    final CliRequest request = parseCliRequest(argv);
    if (request.command == 'help') {
      stdout.writeln(request.usage);
      return 0;
    }

    if (request.command == commandSettings) {
      logger = ConsoleLogger(quiet: false, jsonOutput: false);
      return _runSettingsCommand(request.settings!, logger);
    }

    if (request.command == commandSetup) {
      logger = ConsoleLogger(quiet: false, jsonOutput: false);
      return _runSetupCommand(request.setup!, logger);
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
