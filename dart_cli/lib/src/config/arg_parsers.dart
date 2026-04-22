import 'package:args/args.dart';

import '../core/settings.dart';
import '../models/runtime_options.dart';

final class CliParserCatalog {
  const CliParserCatalog._();

  static const String _migrateDescription = 'Run migration from explicit source/target parameters.';
  static const String _resumeDescription = 'Resume migration from stored session file.';
  static const String _demoDescription = 'Run local demo simulation.';
  static const String _setupDescription = 'Interactive bootstrap for settings profiles.';
  static const String _settingsDescription = 'Manage token/profile settings.';
  static const String _smokeDescription = 'Run real end-to-end smoke test against throwaway source/target test repos.';

  static ArgParser buildRootParser() {
    final ArgParser parser = ArgParser();
    parser.addFlag('help', abbr: 'h', defaultsTo: false, negatable: false);
    parser.addCommand(commandMigrate, _buildMigrateParser());
    parser.addCommand(commandResume, _buildResumeParser());
    parser.addCommand(commandDemo, _buildDemoParser());
    parser.addCommand(commandSetup, _buildSetupParser());
    parser.addCommand(commandSettings, buildSettingsParser());
    parser.addCommand(commandSmoke, _buildSmokeParser());

    return parser;
  }

  static ArgParser buildSettingsParser() {
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

  static String buildUsage() {
    final ArgParser parser = buildRootParser();

    return 'Usage: $publicCommandName <command> [options]\n'
        '\n'
        'Commands:\n'
        '  migrate   Run migration from explicit source/target parameters.\n'
        '  resume    Resume migration from stored session file.\n'
        '  demo      Run local demo simulation.\n'
        '  setup     Interactive bootstrap for settings profiles.\n'
        '  settings  Manage token/profile settings.\n'
        '  smoke     Real end-to-end smoke test against throwaway test repos.\n'
        '\n'
        '${parser.usage}';
  }

  static String buildSmokeUsage() {
    final ArgParser parser = _buildSmokeParser();
    return 'Usage: $publicCommandName smoke [options]\n'
        '\n'
        '$_smokeDescription\n'
        '\n'
        '${parser.usage}';
  }

  static String buildMigrateUsage() {
    final ArgParser parser = _buildMigrateParser();
    return 'Usage: $publicCommandName migrate [options]\n'
        '\n'
        '$_migrateDescription\n'
        '\n'
        '${parser.usage}';
  }

  static String buildResumeUsage() {
    final ArgParser parser = _buildResumeParser();
    return 'Usage: $publicCommandName resume [options]\n'
        '\n'
        '$_resumeDescription\n'
        '\n'
        '${parser.usage}';
  }

  static String buildDemoUsage() {
    final ArgParser parser = _buildDemoParser();
    return 'Usage: $publicCommandName demo [options]\n'
        '\n'
        '$_demoDescription\n'
        '\n'
        '${parser.usage}';
  }

  static String buildSetupUsage() {
    final ArgParser parser = _buildSetupParser();
    return 'Usage: $publicCommandName setup [options]\n'
        '\n'
        '$_setupDescription\n'
        '\n'
        'Options:\n'
        '  --profile <name>  Target settings profile (default: auto-resolve).\n'
        '  --local           Store setup at ./.gfrm/settings.yaml.\n'
        '  --yes             Non-interactive setup with defaults.\n'
        '  --force           Run setup even if settings already exist.\n'
        '\n'
        '${parser.usage}';
  }

  static String buildSettingsUsage() {
    final ArgParser parser = buildSettingsParser();
    return 'Usage: $publicCommandName settings <action> [options]\n'
        '\n'
        '$_settingsDescription\n'
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

  static String buildSettingsActionUsage(String action) {
    final ArgParser parser = buildSettingsParser();
    final ArgParser? actionParser = parser.commands[action];
    if (actionParser == null) {
      return buildSettingsUsage();
    }

    final String description = switch (action) {
      settingsActionInit => 'Bootstrap token env references for providers.',
      settingsActionSetTokenEnv => 'Set provider token via env variable name.',
      settingsActionSetTokenPlain => 'Set provider plain token value.',
      settingsActionUnsetToken => 'Remove provider token from profile.',
      settingsActionShow => 'Show effective merged settings (masked).',
      _ => _settingsDescription,
    };

    return 'Usage: $publicCommandName settings $action [options]\n'
        '\n'
        '$description\n'
        '\n'
        '${actionParser.usage}';
  }

  static ArgParser _baseRuntimeFlags() {
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
    parser.addFlag('skip-releases', defaultsTo: false, negatable: false);
    parser.addFlag('skip-release-assets', defaultsTo: false, negatable: false);
    parser.addFlag('dry-run', defaultsTo: false, negatable: false);
    parser.addFlag('no-banner', defaultsTo: false, negatable: false);
    parser.addFlag('quiet', defaultsTo: false, negatable: false);
    parser.addFlag('json', defaultsTo: false, negatable: false);
    parser.addFlag('progress-bar', defaultsTo: false, negatable: false);
    parser.addFlag('help', abbr: 'h', defaultsTo: false, negatable: false);

    return parser;
  }

  static ArgParser _buildMigrateParser() {
    final ArgParser parser = _baseRuntimeFlags();
    parser.addOption('source-provider');
    parser.addOption('source-url');
    parser.addOption('source-token', defaultsTo: '', hide: true);
    parser.addOption('target-provider');
    parser.addOption('target-url');
    parser.addOption('target-token', defaultsTo: '', hide: true);
    parser.addFlag('save-session', defaultsTo: true, negatable: true);
    parser.addOption('session-file', defaultsTo: '');
    parser.addOption('session-token-mode', defaultsTo: 'env');
    parser.addOption('session-source-token-env', defaultsTo: defaultSourceTokenEnv);
    parser.addOption('session-target-token-env', defaultsTo: defaultTargetTokenEnv);
    parser.addOption('settings-profile', defaultsTo: '');

    return parser;
  }

  static ArgParser _buildResumeParser() {
    final ArgParser parser = _baseRuntimeFlags();
    parser.addOption('session-file', defaultsTo: '');
    parser.addOption('source-token', defaultsTo: '', hide: true);
    parser.addOption('target-token', defaultsTo: '', hide: true);
    parser.addFlag('save-session', defaultsTo: true, negatable: true);
    parser.addOption('session-token-mode', defaultsTo: '');
    parser.addOption('session-source-token-env', defaultsTo: defaultSourceTokenEnv);
    parser.addOption('session-target-token-env', defaultsTo: defaultTargetTokenEnv);
    parser.addOption('settings-profile', defaultsTo: '');

    return parser;
  }

  static ArgParser _buildDemoParser() {
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

  static ArgParser _buildSetupParser() {
    final ArgParser parser = ArgParser();
    parser.addOption('profile', defaultsTo: '');
    parser.addFlag('local', defaultsTo: false, negatable: false);
    parser.addFlag('yes', defaultsTo: false, negatable: false);
    parser.addFlag('force', defaultsTo: false, negatable: false);
    parser.addFlag('help', abbr: 'h', defaultsTo: false, negatable: false);

    return parser;
  }

  static ArgParser _buildSmokeParser() {
    final ArgParser parser = ArgParser();
    parser.addOption('source-provider');
    parser.addOption('source-url');
    parser.addOption('target-provider');
    parser.addOption('target-url');
    parser.addOption('mode', defaultsTo: 'happy-path');
    parser.addFlag('skip-setup', defaultsTo: false, negatable: false);
    parser.addFlag('skip-teardown', defaultsTo: false, negatable: false);
    parser.addOption('cooldown-seconds', defaultsTo: '15');
    parser.addOption('poll-interval', defaultsTo: '10');
    parser.addOption('poll-timeout', defaultsTo: '300');
    parser.addOption('settings-profile', defaultsTo: '');
    parser.addOption('workdir', defaultsTo: '');
    parser.addFlag('quiet', defaultsTo: false, negatable: false);
    parser.addFlag('json', defaultsTo: false, negatable: false);
    parser.addFlag('help', abbr: 'h', defaultsTo: false, negatable: false);

    return parser;
  }
}
