import 'dart:io';

import 'package:args/args.dart';

import 'config/arg_parsers.dart';
import 'config/types/cli_request.dart';
import 'config/types/setup_command_options.dart';
import 'config/validators.dart';
import 'core/session_store.dart';
import 'core/settings.dart';
import 'models/runtime_options.dart';

export 'config/types/cli_request.dart';
export 'config/types/setup_command_options.dart';

const Map<String, String> _providerMap = <String, String>{
  'github': 'github',
  'gh': 'github',
  'gitlab': 'gitlab',
  'gl': 'gitlab',
  'bitbucket': 'bitbucket',
  'bb': 'bitbucket',
};

const Set<String> _knownProviders = <String>{'github', 'gitlab', 'bitbucket'};
typedef _CommonRuntimeFlags = ({
  bool skipTagMigration,
  bool dryRun,
  String workdir,
  String logFile,
  String checkpointFile,
  String tagsFile,
  bool noBanner,
  bool quiet,
  bool jsonOutput,
  bool progressBar,
});

String _normalizeProvider(String? value) {
  if (value == null) {
    return '';
  }

  final String key = value.trim().toLowerCase();
  return _providerMap[key] ?? '';
}

String _requiredString(ArgResults args, String key) {
  final String value = (args[key] ?? '').toString().trim();
  if (value.isEmpty) {
    throw ArgumentError('Missing required option --$key');
  }

  return value;
}

String _optionalString(ArgResults args, String key) {
  try {
    return (args[key] ?? '').toString().trim();
  } catch (_) {
    return '';
  }
}

bool _optionalBool(ArgResults args, String key) {
  try {
    return (args[key] as bool?) ?? false;
  } catch (_) {
    return false;
  }
}

int _optionalInt(ArgResults args, String key, int fallback) {
  try {
    return int.tryParse((args[key] ?? '$fallback').toString()) ?? fallback;
  } catch (_) {
    return fallback;
  }
}

double _optionalDouble(ArgResults args, String key, double fallback) {
  try {
    return double.tryParse((args[key] ?? '$fallback').toString()) ?? fallback;
  } catch (_) {
    return fallback;
  }
}

_CommonRuntimeFlags _commonRuntimeFlags(ArgResults args) {
  return (
    skipTagMigration: _optionalBool(args, 'skip-tags'),
    dryRun: _optionalBool(args, 'dry-run'),
    workdir: _optionalString(args, 'workdir'),
    logFile: _optionalString(args, 'log-file'),
    checkpointFile: _optionalString(args, 'checkpoint-file'),
    tagsFile: _optionalString(args, 'tags-file'),
    noBanner: _optionalBool(args, 'no-banner'),
    quiet: _optionalBool(args, 'quiet'),
    jsonOutput: _optionalBool(args, 'json'),
    progressBar: _optionalBool(args, 'progress-bar'),
  );
}

RuntimeOptions _buildRuntimeOptions({
  required String commandName,
  required String sourceProvider,
  required String sourceUrl,
  required String sourceToken,
  required String targetProvider,
  required String targetUrl,
  required String targetToken,
  required String fromTag,
  required String toTag,
  required bool loadSession,
  required bool saveSession,
  required bool resumeSession,
  required String sessionFile,
  required String sessionTokenMode,
  required String sessionSourceTokenEnv,
  required String sessionTargetTokenEnv,
  required String settingsProfile,
  required int downloadWorkers,
  required int releaseWorkers,
  required bool demoMode,
  required int demoReleases,
  required double demoSleepSeconds,
  required _CommonRuntimeFlags common,
}) {
  return RuntimeOptions(
    commandName: commandName,
    sourceProvider: sourceProvider,
    sourceUrl: sourceUrl,
    sourceToken: sourceToken,
    targetProvider: targetProvider,
    targetUrl: targetUrl,
    targetToken: targetToken,
    migrationOrder: '$sourceProvider-to-$targetProvider',
    skipTagMigration: common.skipTagMigration,
    fromTag: fromTag,
    toTag: toTag,
    dryRun: common.dryRun,
    nonInteractive: true,
    workdir: common.workdir,
    logFile: common.logFile,
    loadSession: loadSession,
    saveSession: saveSession,
    resumeSession: resumeSession,
    sessionFile: sessionFile,
    sessionTokenMode: sessionTokenMode,
    sessionSourceTokenEnv: sessionSourceTokenEnv,
    sessionTargetTokenEnv: sessionTargetTokenEnv,
    settingsProfile: settingsProfile,
    downloadWorkers: downloadWorkers,
    releaseWorkers: releaseWorkers,
    checkpointFile: common.checkpointFile,
    tagsFile: common.tagsFile,
    noBanner: common.noBanner,
    quiet: common.quiet,
    jsonOutput: common.jsonOutput,
    progressBar: common.progressBar,
    demoMode: demoMode,
    demoReleases: demoReleases,
    demoSleepSeconds: demoSleepSeconds,
  );
}

String _resolveTokenFromSession({
  required String tokenPlain,
  required String tokenEnv,
}) {
  if (tokenPlain.isNotEmpty) {
    return tokenPlain;
  }

  if (tokenEnv.isEmpty) {
    return '';
  }

  return Platform.environment[tokenEnv] ?? '';
}

String _resolveTokenWithFallback({
  required String providedToken,
  required String provider,
  required String profile,
  required Map<String, dynamic> settingsPayload,
  required String sideEnvName,
}) {
  if (providedToken.isNotEmpty) {
    return providedToken;
  }

  final String fromSettings = SettingsManager.tokenFromSettings(settingsPayload, profile, provider);
  if (fromSettings.isNotEmpty) {
    return fromSettings;
  }

  return SettingsManager.tokenFromEnvAliases(provider, sideEnvName: sideEnvName);
}

RuntimeOptions _buildMigrateRuntime(ArgResults args) {
  final String sourceProvider = _normalizeProvider(_requiredString(args, 'source-provider'));
  final String targetProvider = _normalizeProvider(_requiredString(args, 'target-provider'));
  ConfigValidators.validateProviderValue('source', sourceProvider, _knownProviders);
  ConfigValidators.validateProviderValue('target', targetProvider, _knownProviders);

  final String sourceUrl = _requiredString(args, 'source-url');
  final String targetUrl = _requiredString(args, 'target-url');
  final String sourceTokenInput = _optionalString(args, 'source-token');
  final String targetTokenInput = _optionalString(args, 'target-token');
  final int downloadWorkers = _optionalInt(args, 'download-workers', 4);
  final int releaseWorkers = _optionalInt(args, 'release-workers', 1);
  final String fromTag = _optionalString(args, 'from-tag');
  final String toTag = _optionalString(args, 'to-tag');
  final String sessionTokenMode = _optionalString(args, 'session-token-mode').toLowerCase();
  final String sessionSourceTokenEnv = _optionalString(args, 'session-source-token-env');
  final String sessionTargetTokenEnv = _optionalString(args, 'session-target-token-env');
  if (!ConfigValidators.tokenModeIsValid(sessionTokenMode)) {
    throw ArgumentError('--session-token-mode must be one of: env, plain');
  }

  ConfigValidators.validateWorkerBounds(downloadWorkers: downloadWorkers, releaseWorkers: releaseWorkers);
  ConfigValidators.validateTagRange(fromTag, toTag);

  final Map<String, dynamic> settingsPayload = SettingsManager.loadEffectiveSettings();
  final String settingsProfile =
      SettingsManager.resolveProfileName(settingsPayload, _optionalString(args, 'settings-profile'));
  final String sourceToken = _resolveTokenWithFallback(
    providedToken: sourceTokenInput,
    provider: sourceProvider,
    profile: settingsProfile,
    settingsPayload: settingsPayload,
    sideEnvName: sessionSourceTokenEnv,
  );
  final String targetToken = _resolveTokenWithFallback(
    providedToken: targetTokenInput,
    provider: targetProvider,
    profile: settingsProfile,
    settingsPayload: settingsPayload,
    sideEnvName: sessionTargetTokenEnv,
  );
  ConfigValidators.validateTokenPresence(sourceToken, targetToken);

  final _CommonRuntimeFlags common = _commonRuntimeFlags(args);
  final bool saveSession = _optionalBool(args, 'save-session');
  return _buildRuntimeOptions(
    commandName: commandMigrate,
    sourceProvider: sourceProvider,
    sourceUrl: sourceUrl,
    sourceToken: sourceToken,
    targetProvider: targetProvider,
    targetUrl: targetUrl,
    targetToken: targetToken,
    fromTag: fromTag,
    toTag: toTag,
    loadSession: false,
    saveSession: saveSession,
    resumeSession: false,
    sessionFile: _optionalString(args, 'session-file'),
    sessionTokenMode: sessionTokenMode,
    sessionSourceTokenEnv: sessionSourceTokenEnv,
    sessionTargetTokenEnv: sessionTargetTokenEnv,
    settingsProfile: settingsProfile,
    downloadWorkers: downloadWorkers,
    releaseWorkers: releaseWorkers,
    demoMode: false,
    demoReleases: 5,
    demoSleepSeconds: 1.0,
    common: common,
  );
}

RuntimeOptions _buildRuntimeFromSession(ArgResults args) {
  final String sessionFile = _optionalString(args, 'session-file');
  final String sessionPath = sessionFile.isEmpty ? '${Directory.current.path}/sessions/last-session.json' : sessionFile;
  final Map<String, dynamic> data = SessionStore.loadSession(sessionPath);

  final String sourceProvider = _normalizeProvider((data['source_provider'] ?? '').toString());
  final String targetProvider = _normalizeProvider((data['target_provider'] ?? '').toString());
  ConfigValidators.validateProviderValue('source', sourceProvider, _knownProviders);
  ConfigValidators.validateProviderValue('target', targetProvider, _knownProviders);

  final String sourceUrl = (data['source_url'] ?? '').toString();
  final String targetUrl = (data['target_url'] ?? '').toString();
  if (sourceUrl.isEmpty || targetUrl.isEmpty) {
    throw ArgumentError('Session file is missing source_url/target_url');
  }

  final String sessionModeFromFile = (data['session_token_mode'] ?? 'env').toString().toLowerCase();
  final String sessionModeOverride = _optionalString(args, 'session-token-mode').toLowerCase();
  final String sessionTokenMode = sessionModeOverride.isEmpty ? sessionModeFromFile : sessionModeOverride;
  if (!ConfigValidators.tokenModeIsValid(sessionTokenMode)) {
    throw ArgumentError('--session-token-mode must be one of: env, plain');
  }

  final String sourceTokenEnv =
      ((data['source_token_env'] ?? _optionalString(args, 'session-source-token-env')).toString()).trim();
  final String targetTokenEnv =
      ((data['target_token_env'] ?? _optionalString(args, 'session-target-token-env')).toString()).trim();

  final Map<String, dynamic> settingsPayload = SettingsManager.loadEffectiveSettings();
  final String settingsProfileRequested = _optionalString(args, 'settings-profile');
  final String settingsProfileFromFile = (data['settings_profile'] ?? '').toString().trim();
  final String settingsProfile = SettingsManager.resolveProfileName(
    settingsPayload,
    settingsProfileRequested.isEmpty ? settingsProfileFromFile : settingsProfileRequested,
  );

  final String sourceToken = _resolveTokenWithFallback(
    providedToken: _resolveTokenFromSession(
      tokenPlain: (data['source_token'] ?? '').toString(),
      tokenEnv: sourceTokenEnv,
    ),
    provider: sourceProvider,
    profile: settingsProfile,
    settingsPayload: settingsPayload,
    sideEnvName: sourceTokenEnv,
  );
  final String targetToken = _resolveTokenWithFallback(
    providedToken: _resolveTokenFromSession(
      tokenPlain: (data['target_token'] ?? '').toString(),
      tokenEnv: targetTokenEnv,
    ),
    provider: targetProvider,
    profile: settingsProfile,
    settingsPayload: settingsPayload,
    sideEnvName: targetTokenEnv,
  );
  ConfigValidators.validateTokenPresence(sourceToken, targetToken);

  final int downloadWorkersOverride = _optionalInt(args, 'download-workers', -1);
  final int releaseWorkersOverride = _optionalInt(args, 'release-workers', -1);
  final int downloadWorkersFromSession = int.tryParse((data['download_workers'] ?? 4).toString()) ?? 4;
  final int releaseWorkersFromSession = int.tryParse((data['release_workers'] ?? 1).toString()) ?? 1;
  final int downloadWorkers = args.wasParsed('download-workers') ? downloadWorkersOverride : downloadWorkersFromSession;
  final int releaseWorkers = args.wasParsed('release-workers') ? releaseWorkersOverride : releaseWorkersFromSession;
  ConfigValidators.validateWorkerBounds(downloadWorkers: downloadWorkers, releaseWorkers: releaseWorkers);

  final String fromTag =
      args.wasParsed('from-tag') ? _optionalString(args, 'from-tag') : (data['from_tag'] ?? '').toString();
  final String toTag = args.wasParsed('to-tag') ? _optionalString(args, 'to-tag') : (data['to_tag'] ?? '').toString();
  ConfigValidators.validateTagRange(fromTag, toTag);

  final bool skipTags =
      args.wasParsed('skip-tags') ? _optionalBool(args, 'skip-tags') : ((data['skip_tag_migration'] ?? false) == true);
  final bool saveSession = _optionalBool(args, 'save-session');
  final _CommonRuntimeFlags baseCommon = _commonRuntimeFlags(args);
  final _CommonRuntimeFlags common = (
    skipTagMigration: skipTags,
    dryRun: baseCommon.dryRun,
    workdir: baseCommon.workdir,
    logFile: baseCommon.logFile,
    checkpointFile: baseCommon.checkpointFile,
    tagsFile: baseCommon.tagsFile,
    noBanner: baseCommon.noBanner,
    quiet: baseCommon.quiet,
    jsonOutput: baseCommon.jsonOutput,
    progressBar: baseCommon.progressBar,
  );

  return _buildRuntimeOptions(
    commandName: commandResume,
    sourceProvider: sourceProvider,
    sourceUrl: sourceUrl,
    sourceToken: sourceToken,
    targetProvider: targetProvider,
    targetUrl: targetUrl,
    targetToken: targetToken,
    fromTag: fromTag,
    toTag: toTag,
    loadSession: true,
    saveSession: saveSession,
    resumeSession: true,
    sessionFile: sessionPath,
    sessionTokenMode: sessionTokenMode,
    sessionSourceTokenEnv: sourceTokenEnv.isEmpty ? defaultSourceTokenEnv : sourceTokenEnv,
    sessionTargetTokenEnv: targetTokenEnv.isEmpty ? defaultTargetTokenEnv : targetTokenEnv,
    settingsProfile: settingsProfile,
    downloadWorkers: downloadWorkers,
    releaseWorkers: releaseWorkers,
    demoMode: false,
    demoReleases: 5,
    demoSleepSeconds: 1.0,
    common: common,
  );
}

RuntimeOptions _buildDemoRuntime(ArgResults args) {
  final String sourceProvider = _normalizeProvider(_optionalString(args, 'source-provider'));
  final String targetProvider = _normalizeProvider(_optionalString(args, 'target-provider'));
  ConfigValidators.validateProviderValue('source', sourceProvider, _knownProviders);
  ConfigValidators.validateProviderValue('target', targetProvider, _knownProviders);

  final int downloadWorkers = _optionalInt(args, 'download-workers', 4);
  final int releaseWorkers = _optionalInt(args, 'release-workers', 1);
  ConfigValidators.validateWorkerBounds(downloadWorkers: downloadWorkers, releaseWorkers: releaseWorkers);

  final int demoReleases = _optionalInt(args, 'demo-releases', 5);
  final double demoSleepSeconds = _optionalDouble(args, 'demo-sleep-seconds', 1.0);
  ConfigValidators.validateDemoConfig(demoReleases: demoReleases, demoSleepSeconds: demoSleepSeconds);

  final String fromTag = _optionalString(args, 'from-tag');
  final String toTag = _optionalString(args, 'to-tag');
  ConfigValidators.validateTagRange(fromTag, toTag);

  final _CommonRuntimeFlags common = _commonRuntimeFlags(args);
  return _buildRuntimeOptions(
    commandName: commandDemo,
    sourceProvider: sourceProvider,
    sourceUrl: _optionalString(args, 'source-url'),
    sourceToken: _optionalString(args, 'source-token'),
    targetProvider: targetProvider,
    targetUrl: _optionalString(args, 'target-url'),
    targetToken: _optionalString(args, 'target-token'),
    fromTag: fromTag,
    toTag: toTag,
    loadSession: false,
    saveSession: false,
    resumeSession: false,
    sessionFile: _optionalString(args, 'session-file'),
    sessionTokenMode: _optionalString(args, 'session-token-mode'),
    sessionSourceTokenEnv: _optionalString(args, 'session-source-token-env'),
    sessionTargetTokenEnv: _optionalString(args, 'session-target-token-env'),
    settingsProfile: '',
    downloadWorkers: downloadWorkers,
    releaseWorkers: releaseWorkers,
    demoMode: true,
    demoReleases: demoReleases,
    demoSleepSeconds: demoSleepSeconds,
    common: common,
  );
}

CliRequest _parseSettingsCommand(ArgResults root) {
  if (_optionalBool(root, 'help')) {
    return CliRequest(command: 'help', usage: CliParserCatalog.buildSettingsUsage());
  }

  final ArgResults? command = root.command;
  if (command == null) {
    return CliRequest(command: 'help', usage: CliParserCatalog.buildSettingsUsage());
  }

  if (_optionalBool(command, 'help')) {
    return CliRequest(command: 'help', usage: CliParserCatalog.buildSettingsUsage());
  }

  final String action = command.name ?? '';
  final String provider = _normalizeProvider(_optionalString(command, 'provider'));
  if (provider.isNotEmpty && !_knownProviders.contains(provider)) {
    throw ArgumentError('--provider must be one of: github, gitlab, bitbucket');
  }

  return CliRequest(
    command: commandSettings,
    settings: SettingsCommandOptions(
      action: action,
      profile: _optionalString(command, 'profile'),
      provider: provider,
      envName: _optionalString(command, 'env-name'),
      token: _optionalString(command, 'token'),
      localScope: _optionalBool(command, 'local'),
      assumeYes: _optionalBool(command, 'yes'),
    ),
  );
}

CliRequest _parseSetupRequest(ArgResults command) {
  return CliRequest(
    command: commandSetup,
    setup: SetupCommandOptions(
      profile: _optionalString(command, 'profile'),
      localScope: _optionalBool(command, 'local'),
      assumeYes: _optionalBool(command, 'yes'),
      force: _optionalBool(command, 'force'),
    ),
  );
}

CliRequest _parseCliRequest(List<String> argv) {
  if (argv.isEmpty) {
    return CliRequest(command: 'help', usage: CliParserCatalog.buildUsage());
  }

  final ArgParser parser = CliParserCatalog.buildRootParser();
  final ArgResults root = parser.parse(argv);
  if (_optionalBool(root, 'help')) {
    return CliRequest(command: 'help', usage: CliParserCatalog.buildUsage());
  }

  final ArgResults? commandResult = root.command;
  if (commandResult == null) {
    throw ArgumentError('Missing command. Use one of: migrate, resume, demo, setup, settings.');
  }

  final String commandName = commandResult.name ?? '';
  if (_optionalBool(commandResult, 'help')) {
    if (commandName == commandSetup) {
      return CliRequest(command: 'help', usage: CliParserCatalog.buildSetupUsage());
    }

    if (commandName == commandSettings) {
      return CliRequest(command: 'help', usage: CliParserCatalog.buildSettingsUsage());
    }

    return CliRequest(command: 'help', usage: CliParserCatalog.buildUsage());
  }

  switch (commandName) {
    case commandMigrate:
      return CliRequest(
        command: commandMigrate,
        options: _buildMigrateRuntime(commandResult),
      );

    case commandResume:
      return CliRequest(
        command: commandResume,
        options: _buildRuntimeFromSession(commandResult),
      );

    case commandDemo:
      return CliRequest(
        command: commandDemo,
        options: _buildDemoRuntime(commandResult),
      );

    case commandSetup:
      return _parseSetupRequest(commandResult);

    case commandSettings:
      return _parseSettingsCommand(commandResult);

    default:
      throw ArgumentError('Unsupported command: $commandName');
  }
}

final class CliRequestParser {
  const CliRequestParser._();

  static CliRequest parseCliRequest(List<String> argv) {
    return _parseCliRequest(argv);
  }
}
