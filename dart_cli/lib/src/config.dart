import 'dart:io';

import 'package:args/args.dart';

import 'core/session_store.dart';
import 'core/settings.dart';
import 'core/versioning.dart';
import 'models.dart';

class CliRequest {
  CliRequest({
    required this.command,
    this.options,
    this.settings,
    this.setup,
    this.usage = '',
  });

  final String command;
  final RuntimeOptions? options;
  final SettingsCommandOptions? settings;
  final SetupCommandOptions? setup;
  final String usage;
}

class SetupCommandOptions {
  const SetupCommandOptions({
    required this.profile,
    required this.localScope,
    required this.assumeYes,
    required this.force,
  });

  final String profile;
  final bool localScope;
  final bool assumeYes;
  final bool force;
}

const Map<String, String> _providerMap = <String, String>{
  'github': 'github',
  'gh': 'github',
  'gitlab': 'gitlab',
  'gl': 'gitlab',
  'bitbucket': 'bitbucket',
  'bb': 'bitbucket',
};

const Set<String> _knownProviders = <String>{'github', 'gitlab', 'bitbucket'};

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

bool _tokenModeIsValid(String mode) {
  return const <String>{'env', 'plain'}.contains(mode);
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

  final String fromSettings = tokenFromSettings(settingsPayload, profile, provider);
  if (fromSettings.isNotEmpty) {
    return fromSettings;
  }

  return tokenFromEnvAliases(provider, sideEnvName: sideEnvName);
}

void _validateWorkerBounds({
  required int downloadWorkers,
  required int releaseWorkers,
}) {
  if (downloadWorkers < 1 || downloadWorkers > 16) {
    throw ArgumentError('--download-workers must be between 1 and 16');
  }

  if (releaseWorkers < 1 || releaseWorkers > 8) {
    throw ArgumentError('--release-workers must be between 1 and 8');
  }
}

void _validateProviderValue(String label, String provider) {
  if (!_knownProviders.contains(provider)) {
    throw ArgumentError('Unsupported $label provider: $provider');
  }
}

void _validateTagRange(String fromTag, String toTag) {
  if (fromTag.isNotEmpty && toTag.isNotEmpty && !versionLe(fromTag, toTag)) {
    throw ArgumentError('Invalid range: --from-tag ($fromTag) must be <= --to-tag ($toTag)');
  }
}

void _validateDemoConfig({
  required int demoReleases,
  required double demoSleepSeconds,
}) {
  if (demoReleases < 1 || demoReleases > 100) {
    throw ArgumentError('--demo-releases must be between 1 and 100');
  }

  if (demoSleepSeconds < 0) {
    throw ArgumentError('--demo-sleep-seconds must be >= 0');
  }
}

void _validateTokenPresence(String sourceToken, String targetToken) {
  if (sourceToken.isEmpty) {
    throw ArgumentError(
      'Missing source token. Provide --source-token, settings profile token, or relevant env variable.',
    );
  }

  if (targetToken.isEmpty) {
    throw ArgumentError(
      'Missing target token. Provide --target-token, settings profile token, or relevant env variable.',
    );
  }
}

ArgParser _baseRuntimeFlags() {
  final ArgParser parser = ArgParser();
  parser.addOption('workdir', defaultsTo: '');
  parser.addOption('log-file', defaultsTo: '');
  parser.addOption('checkpoint-file', defaultsTo: '');
  parser.addOption('tags-file', defaultsTo: '');
  parser.addOption('from-tag', defaultsTo: '');
  parser.addOption('to-tag', defaultsTo: '');
  parser.addOption('download-workers', defaultsTo: '4');
  parser.addOption('release-workers', defaultsTo: '1');
  parser.addFlag('skip-tags', defaultsTo: false, negatable: false);
  parser.addFlag('dry-run', defaultsTo: false, negatable: false);
  parser.addFlag('no-banner', defaultsTo: false, negatable: false);
  parser.addFlag('quiet', defaultsTo: false, negatable: false);
  parser.addFlag('json', defaultsTo: false, negatable: false);
  parser.addFlag('progress-bar', defaultsTo: false, negatable: false);
  parser.addFlag('help', abbr: 'h', defaultsTo: false, negatable: false);

  return parser;
}

ArgParser _buildMigrateParser() {
  final ArgParser parser = _baseRuntimeFlags();
  parser.addOption('source-provider');
  parser.addOption('source-url');
  parser.addOption('source-token', defaultsTo: '');
  parser.addOption('target-provider');
  parser.addOption('target-url');
  parser.addOption('target-token', defaultsTo: '');
  parser.addFlag('save-session', defaultsTo: true, negatable: false);
  parser.addFlag('no-save-session', defaultsTo: false, negatable: false);
  parser.addOption('session-file', defaultsTo: '');
  parser.addOption('session-token-mode', defaultsTo: 'env');
  parser.addOption('session-source-token-env', defaultsTo: defaultSourceTokenEnv);
  parser.addOption('session-target-token-env', defaultsTo: defaultTargetTokenEnv);
  parser.addOption('settings-profile', defaultsTo: '');

  return parser;
}

ArgParser _buildResumeParser() {
  final ArgParser parser = _baseRuntimeFlags();
  parser.addOption('session-file', defaultsTo: '');
  parser.addFlag('save-session', defaultsTo: true, negatable: false);
  parser.addFlag('no-save-session', defaultsTo: false, negatable: false);
  parser.addOption('session-token-mode', defaultsTo: '');
  parser.addOption('session-source-token-env', defaultsTo: defaultSourceTokenEnv);
  parser.addOption('session-target-token-env', defaultsTo: defaultTargetTokenEnv);
  parser.addOption('settings-profile', defaultsTo: '');

  return parser;
}

ArgParser _buildDemoParser() {
  final ArgParser parser = _baseRuntimeFlags();
  parser.addOption('source-provider', defaultsTo: 'github');
  parser.addOption('source-url', defaultsTo: 'https://github.com/demo/source');
  parser.addOption('source-token', defaultsTo: 'demo-source-token');
  parser.addOption('target-provider', defaultsTo: 'gitlab');
  parser.addOption('target-url', defaultsTo: 'https://gitlab.com/demo/target');
  parser.addOption('target-token', defaultsTo: 'demo-target-token');
  parser.addOption('session-file', defaultsTo: '');
  parser.addOption('session-token-mode', defaultsTo: 'env');
  parser.addOption('session-source-token-env', defaultsTo: defaultSourceTokenEnv);
  parser.addOption('session-target-token-env', defaultsTo: defaultTargetTokenEnv);
  parser.addOption('demo-releases', defaultsTo: '5');
  parser.addOption('demo-sleep-seconds', defaultsTo: '1.0');

  return parser;
}

ArgParser _buildSetupParser() {
  final ArgParser parser = ArgParser();
  parser.addOption('profile', defaultsTo: '');
  parser.addFlag('local', defaultsTo: false, negatable: false);
  parser.addFlag('yes', defaultsTo: false, negatable: false);
  parser.addFlag('force', defaultsTo: false, negatable: false);
  parser.addFlag('help', abbr: 'h', defaultsTo: false, negatable: false);

  return parser;
}

ArgParser buildRootParser() {
  final ArgParser parser = ArgParser();
  parser.addFlag('help', abbr: 'h', defaultsTo: false, negatable: false);
  parser.addCommand(commandMigrate, _buildMigrateParser());
  parser.addCommand(commandResume, _buildResumeParser());
  parser.addCommand(commandDemo, _buildDemoParser());
  parser.addCommand(commandSetup, _buildSetupParser());

  return parser;
}

ArgParser buildSettingsParser() {
  final ArgParser parser = ArgParser();
  parser.addFlag('help', abbr: 'h', defaultsTo: false, negatable: false);

  final ArgParser init = ArgParser();
  init.addOption('profile', defaultsTo: '');
  init.addFlag('local', defaultsTo: false, negatable: false);
  init.addFlag('yes', defaultsTo: false, negatable: false);
  init.addFlag('help', abbr: 'h', defaultsTo: false, negatable: false);
  parser.addCommand(settingsActionInit, init);

  final ArgParser setTokenEnv = ArgParser();
  setTokenEnv.addOption('provider', defaultsTo: '');
  setTokenEnv.addOption('env-name', defaultsTo: '');
  setTokenEnv.addOption('profile', defaultsTo: '');
  setTokenEnv.addFlag('local', defaultsTo: false, negatable: false);
  setTokenEnv.addFlag('help', abbr: 'h', defaultsTo: false, negatable: false);
  parser.addCommand(settingsActionSetTokenEnv, setTokenEnv);

  final ArgParser setTokenPlain = ArgParser();
  setTokenPlain.addOption('provider', defaultsTo: '');
  setTokenPlain.addOption('token', defaultsTo: '');
  setTokenPlain.addOption('profile', defaultsTo: '');
  setTokenPlain.addFlag('local', defaultsTo: false, negatable: false);
  setTokenPlain.addFlag('help', abbr: 'h', defaultsTo: false, negatable: false);
  parser.addCommand(settingsActionSetTokenPlain, setTokenPlain);

  final ArgParser unsetToken = ArgParser();
  unsetToken.addOption('provider', defaultsTo: '');
  unsetToken.addOption('profile', defaultsTo: '');
  unsetToken.addFlag('local', defaultsTo: false, negatable: false);
  unsetToken.addFlag('help', abbr: 'h', defaultsTo: false, negatable: false);
  parser.addCommand(settingsActionUnsetToken, unsetToken);

  final ArgParser show = ArgParser();
  show.addOption('profile', defaultsTo: '');
  show.addFlag('help', abbr: 'h', defaultsTo: false, negatable: false);
  parser.addCommand(settingsActionShow, show);

  return parser;
}

String buildUsage() {
  final ArgParser parser = buildRootParser();

  return 'Usage: $publicCommandName <command> [options]\n'
      '\n'
      'Commands:\n'
      '  migrate   Run migration from explicit source/target parameters.\n'
      '  resume    Resume migration from stored session file.\n'
      '  demo      Run local demo simulation.\n'
      '  setup     Interactive bootstrap for settings profiles.\n'
      '  settings  Manage token/profile settings.\n'
      '\n'
      '${parser.usage}';
}

String buildSetupUsage() {
  final ArgParser parser = _buildSetupParser();
  return 'Usage: $publicCommandName setup [options]\n'
      '\n'
      'Options:\n'
      '  --profile <name>  Target settings profile (default: auto-resolve).\n'
      '  --local           Store setup at ./.gfrm/settings.yaml.\n'
      '  --yes             Non-interactive setup with defaults.\n'
      '  --force           Run setup even if settings already exist.\n'
      '\n'
      '${parser.usage}';
}

String buildSettingsUsage() {
  final ArgParser parser = buildSettingsParser();
  return 'Usage: $publicCommandName settings <action> [options]\n'
      '\n'
      'Actions:\n'
      '  init            Bootstrap token env references for providers.\n'
      '  set-token-env   Set provider token via env variable name.\n'
      '  set-token-plain Set provider plain token value.\n'
      '  unset-token     Remove provider token from profile.\n'
      '  show            Show effective merged settings (masked).\n'
      '\n'
      '${parser.usage}';
}

RuntimeOptions _buildMigrateRuntime(ArgResults args) {
  final String sourceProvider = _normalizeProvider(_requiredString(args, 'source-provider'));
  final String targetProvider = _normalizeProvider(_requiredString(args, 'target-provider'));
  _validateProviderValue('source', sourceProvider);
  _validateProviderValue('target', targetProvider);

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
  if (!_tokenModeIsValid(sessionTokenMode)) {
    throw ArgumentError('--session-token-mode must be one of: env, plain');
  }

  _validateWorkerBounds(downloadWorkers: downloadWorkers, releaseWorkers: releaseWorkers);
  _validateTagRange(fromTag, toTag);

  final Map<String, dynamic> settingsPayload = loadEffectiveSettings();
  final String settingsProfile = resolveProfileName(settingsPayload, _optionalString(args, 'settings-profile'));
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
  _validateTokenPresence(sourceToken, targetToken);

  final bool saveSession = _optionalBool(args, 'save-session') && !_optionalBool(args, 'no-save-session');
  return RuntimeOptions(
    commandName: commandMigrate,
    sourceProvider: sourceProvider,
    sourceUrl: sourceUrl,
    sourceToken: sourceToken,
    targetProvider: targetProvider,
    targetUrl: targetUrl,
    targetToken: targetToken,
    migrationOrder: '$sourceProvider-to-$targetProvider',
    skipTagMigration: _optionalBool(args, 'skip-tags'),
    fromTag: fromTag,
    toTag: toTag,
    dryRun: _optionalBool(args, 'dry-run'),
    nonInteractive: true,
    workdir: _optionalString(args, 'workdir'),
    logFile: _optionalString(args, 'log-file'),
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
    checkpointFile: _optionalString(args, 'checkpoint-file'),
    tagsFile: _optionalString(args, 'tags-file'),
    noBanner: _optionalBool(args, 'no-banner'),
    quiet: _optionalBool(args, 'quiet'),
    jsonOutput: _optionalBool(args, 'json'),
    progressBar: _optionalBool(args, 'progress-bar'),
    demoMode: false,
    demoReleases: 5,
    demoSleepSeconds: 1.0,
  );
}

RuntimeOptions _buildRuntimeFromSession(ArgResults args) {
  final String sessionFile = _optionalString(args, 'session-file');
  final String sessionPath = sessionFile.isEmpty ? '${Directory.current.path}/sessions/last-session.json' : sessionFile;
  final Map<String, dynamic> data = loadSession(sessionPath);

  final String sourceProvider = _normalizeProvider((data['source_provider'] ?? '').toString());
  final String targetProvider = _normalizeProvider((data['target_provider'] ?? '').toString());
  _validateProviderValue('source', sourceProvider);
  _validateProviderValue('target', targetProvider);

  final String sourceUrl = (data['source_url'] ?? '').toString();
  final String targetUrl = (data['target_url'] ?? '').toString();
  if (sourceUrl.isEmpty || targetUrl.isEmpty) {
    throw ArgumentError('Session file is missing source_url/target_url');
  }

  final String sessionModeFromFile = (data['session_token_mode'] ?? 'env').toString().toLowerCase();
  final String sessionModeOverride = _optionalString(args, 'session-token-mode').toLowerCase();
  final String sessionTokenMode = sessionModeOverride.isEmpty ? sessionModeFromFile : sessionModeOverride;
  if (!_tokenModeIsValid(sessionTokenMode)) {
    throw ArgumentError('--session-token-mode must be one of: env, plain');
  }

  final String sourceTokenEnv =
      ((data['source_token_env'] ?? _optionalString(args, 'session-source-token-env')).toString()).trim();
  final String targetTokenEnv =
      ((data['target_token_env'] ?? _optionalString(args, 'session-target-token-env')).toString()).trim();

  final Map<String, dynamic> settingsPayload = loadEffectiveSettings();
  final String settingsProfileRequested = _optionalString(args, 'settings-profile');
  final String settingsProfileFromFile = (data['settings_profile'] ?? '').toString().trim();
  final String settingsProfile = resolveProfileName(
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
  _validateTokenPresence(sourceToken, targetToken);

  final int downloadWorkersOverride = _optionalInt(args, 'download-workers', -1);
  final int releaseWorkersOverride = _optionalInt(args, 'release-workers', -1);
  final int downloadWorkersFromSession = int.tryParse((data['download_workers'] ?? 4).toString()) ?? 4;
  final int releaseWorkersFromSession = int.tryParse((data['release_workers'] ?? 1).toString()) ?? 1;
  final int downloadWorkers = args.wasParsed('download-workers') ? downloadWorkersOverride : downloadWorkersFromSession;
  final int releaseWorkers = args.wasParsed('release-workers') ? releaseWorkersOverride : releaseWorkersFromSession;
  _validateWorkerBounds(downloadWorkers: downloadWorkers, releaseWorkers: releaseWorkers);

  final String fromTag =
      args.wasParsed('from-tag') ? _optionalString(args, 'from-tag') : (data['from_tag'] ?? '').toString();
  final String toTag = args.wasParsed('to-tag') ? _optionalString(args, 'to-tag') : (data['to_tag'] ?? '').toString();
  _validateTagRange(fromTag, toTag);

  final bool skipTags =
      args.wasParsed('skip-tags') ? _optionalBool(args, 'skip-tags') : ((data['skip_tag_migration'] ?? false) == true);
  final bool saveSession = _optionalBool(args, 'save-session') && !_optionalBool(args, 'no-save-session');

  return RuntimeOptions(
    commandName: commandResume,
    sourceProvider: sourceProvider,
    sourceUrl: sourceUrl,
    sourceToken: sourceToken,
    targetProvider: targetProvider,
    targetUrl: targetUrl,
    targetToken: targetToken,
    migrationOrder: '$sourceProvider-to-$targetProvider',
    skipTagMigration: skipTags,
    fromTag: fromTag,
    toTag: toTag,
    dryRun: _optionalBool(args, 'dry-run'),
    nonInteractive: true,
    workdir: _optionalString(args, 'workdir'),
    logFile: _optionalString(args, 'log-file'),
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
    checkpointFile: _optionalString(args, 'checkpoint-file'),
    tagsFile: _optionalString(args, 'tags-file'),
    noBanner: _optionalBool(args, 'no-banner'),
    quiet: _optionalBool(args, 'quiet'),
    jsonOutput: _optionalBool(args, 'json'),
    progressBar: _optionalBool(args, 'progress-bar'),
    demoMode: false,
    demoReleases: 5,
    demoSleepSeconds: 1.0,
  );
}

RuntimeOptions _buildDemoRuntime(ArgResults args) {
  final String sourceProvider = _normalizeProvider(_optionalString(args, 'source-provider'));
  final String targetProvider = _normalizeProvider(_optionalString(args, 'target-provider'));
  _validateProviderValue('source', sourceProvider);
  _validateProviderValue('target', targetProvider);

  final int downloadWorkers = _optionalInt(args, 'download-workers', 4);
  final int releaseWorkers = _optionalInt(args, 'release-workers', 1);
  _validateWorkerBounds(downloadWorkers: downloadWorkers, releaseWorkers: releaseWorkers);

  final int demoReleases = _optionalInt(args, 'demo-releases', 5);
  final double demoSleepSeconds = _optionalDouble(args, 'demo-sleep-seconds', 1.0);
  _validateDemoConfig(demoReleases: demoReleases, demoSleepSeconds: demoSleepSeconds);

  final String fromTag = _optionalString(args, 'from-tag');
  final String toTag = _optionalString(args, 'to-tag');
  _validateTagRange(fromTag, toTag);

  return RuntimeOptions(
    commandName: commandDemo,
    sourceProvider: sourceProvider,
    sourceUrl: _optionalString(args, 'source-url'),
    sourceToken: _optionalString(args, 'source-token'),
    targetProvider: targetProvider,
    targetUrl: _optionalString(args, 'target-url'),
    targetToken: _optionalString(args, 'target-token'),
    migrationOrder: '$sourceProvider-to-$targetProvider',
    skipTagMigration: _optionalBool(args, 'skip-tags'),
    fromTag: fromTag,
    toTag: toTag,
    dryRun: _optionalBool(args, 'dry-run'),
    nonInteractive: true,
    workdir: _optionalString(args, 'workdir'),
    logFile: _optionalString(args, 'log-file'),
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
    checkpointFile: _optionalString(args, 'checkpoint-file'),
    tagsFile: _optionalString(args, 'tags-file'),
    noBanner: _optionalBool(args, 'no-banner'),
    quiet: _optionalBool(args, 'quiet'),
    jsonOutput: _optionalBool(args, 'json'),
    progressBar: _optionalBool(args, 'progress-bar'),
    demoMode: true,
    demoReleases: demoReleases,
    demoSleepSeconds: demoSleepSeconds,
  );
}

CliRequest _parseSettingsRequest(List<String> argv) {
  final ArgParser parser = buildSettingsParser();
  if (argv.isEmpty) {
    return CliRequest(command: 'help', usage: buildSettingsUsage());
  }

  final ArgResults root = parser.parse(argv);
  if (_optionalBool(root, 'help')) {
    return CliRequest(command: 'help', usage: buildSettingsUsage());
  }

  final ArgResults? command = root.command;
  if (command == null) {
    throw ArgumentError(
        'Missing settings action. Use one of: init, set-token-env, set-token-plain, unset-token, show.');
  }

  if (_optionalBool(command, 'help')) {
    return CliRequest(command: 'help', usage: buildSettingsUsage());
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

CliRequest parseCliRequest(List<String> argv) {
  if (argv.isEmpty) {
    return CliRequest(command: 'help', usage: buildUsage());
  }

  if (argv.first == commandSettings) {
    return _parseSettingsRequest(argv.sublist(1));
  }

  final ArgParser parser = buildRootParser();
  final ArgResults root = parser.parse(argv);
  if (_optionalBool(root, 'help')) {
    return CliRequest(command: 'help', usage: buildUsage());
  }

  final ArgResults? commandResult = root.command;
  if (commandResult == null) {
    throw ArgumentError('Missing command. Use one of: migrate, resume, demo, setup, settings.');
  }

  final String commandName = commandResult.name ?? '';
  if (_optionalBool(commandResult, 'help')) {
    if (commandName == commandSetup) {
      return CliRequest(command: 'help', usage: buildSetupUsage());
    }

    return CliRequest(command: 'help', usage: buildUsage());
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

    default:
      throw ArgumentError('Unsupported command: $commandName');
  }
}
