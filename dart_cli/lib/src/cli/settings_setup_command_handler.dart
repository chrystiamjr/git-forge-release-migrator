import 'dart:convert';
import 'dart:io';

import '../config.dart';
import '../core/console_output.dart';
import '../core/input_reader.dart';
import '../core/logging.dart';
import '../core/settings.dart';
import '../core/std_console_output.dart';
import '../core/std_input_reader.dart';
import '../core/test_helper.dart';
import '../models/runtime_options.dart';

class SettingsSetupCommandHandler {
  SettingsSetupCommandHandler({
    required this.logger,
    ConsoleOutput? output,
    InputReader? input,
    Map<String, String>? environment,
    Set<String> Function()? scanShellExportNames,
    bool Function()? isTestProcess,
  })  : output = output ?? const StdConsoleOutput(),
        input = input ?? const StdInputReader(),
        _environmentOverride = environment,
        _scanShellExportNamesOverride = scanShellExportNames,
        _isTestProcessOverride = isTestProcess;

  final ConsoleLogger logger;
  final ConsoleOutput output;
  final InputReader input;
  final Map<String, String>? _environmentOverride;
  final Set<String> Function()? _scanShellExportNamesOverride;
  final bool Function()? _isTestProcessOverride;

  int runSetupCommand(SetupCommandOptions options) {
    final Map<String, dynamic> effective = SettingsManager.loadEffectiveSettings();
    final String profile = _chooseSetupProfile(options: options, effectiveSettings: effective);
    if (_hasConfiguredTokenValues(effective) && !options.force) {
      logger.info('Detected existing settings token configuration. Setup wizard skipped.');
      logger.info('Run `$publicCommandName setup --force` to rebuild token mappings.');
      _printSetupExamples(profile);
      return 0;
    }

    final bool localScope = _chooseSetupScope(options);
    final SettingsScopeData scope = SettingsManager.readScopeSettings(local: localScope);
    final Set<String> knownEnvNames = <String>{
      ..._environment.keys,
      ..._scanShellExportNames(),
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

      updated = SettingsManager.setProviderTokenEnv(
        updated,
        profile: profile,
        provider: provider,
        envName: chosen,
      );
      changed = true;
    }

    if (changed) {
      SettingsManager.writeSettingsFile(scope.path, updated);
      logger.info('Setup finished. Settings written to ${scope.path}.');
    } else {
      logger.warn('Setup finished without token mappings. No settings file changes were required.');
    }

    _printSetupExamples(profile);
    return 0;
  }

  int runSettingsCommand(SettingsCommandOptions options) {
    final String action = options.action.trim();
    if (action == settingsActionShow) {
      final Map<String, dynamic> effective = SettingsManager.loadEffectiveSettings();
      final String profile = SettingsManager.resolveProfileName(effective, options.profile);
      final Map<String, dynamic> masked = SettingsManager.maskSettingsSecrets(effective);
      _writeLine(
        const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
          'profile': profile,
          'settings': masked,
        }),
      );

      return 0;
    }

    if (action == settingsActionInit) {
      return _runSettingsInit(options);
    }

    final String provider = options.provider.trim();
    if (!supportedSettingsProviders.contains(provider)) {
      throw ArgumentError('--provider must be one of: github, gitlab, bitbucket');
    }

    final SettingsScopeData scope = SettingsManager.readScopeSettings(local: options.localScope);
    final Map<String, dynamic> effective = SettingsManager.loadEffectiveSettings();
    final String profile = SettingsManager.resolveProfileName(effective, options.profile);
    Map<String, dynamic> updated = scope.payload;

    if (action == settingsActionSetTokenEnv) {
      final String envName = options.envName.trim();
      if (envName.isEmpty) {
        throw ArgumentError('--env-name is required for settings set-token-env');
      }

      updated = SettingsManager.setProviderTokenEnv(updated, profile: profile, provider: provider, envName: envName);
      SettingsManager.writeSettingsFile(scope.path, updated);
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

      updated = SettingsManager.setProviderTokenPlain(updated, profile: profile, provider: provider, token: token);
      SettingsManager.writeSettingsFile(scope.path, updated);
      logger.warn('Token stored in plain text. Keep file permissions restricted.');
      logger.info("Stored plain token for provider '$provider' in profile '$profile' at ${scope.path}");

      return 0;
    }

    if (action == settingsActionUnsetToken) {
      updated = SettingsManager.unsetProviderToken(updated, profile: profile, provider: provider);
      SettingsManager.writeSettingsFile(scope.path, updated);
      logger.info("Removed token settings for provider '$provider' in profile '$profile' at ${scope.path}");

      return 0;
    }

    throw ArgumentError('Unknown settings action: $action');
  }

  String _promptLine(String prompt) {
    output.writeOut(prompt);
    return input.readLine().trim();
  }

  void _writeLine(String line) {
    output.writeOutLine(line);
  }

  Map<String, String> get _environment => _environmentOverride ?? Platform.environment;

  Set<String> _scanShellExportNames() {
    if (_scanShellExportNamesOverride != null) {
      return _scanShellExportNamesOverride();
    }

    return SettingsManager.scanShellExportNames();
  }

  bool _isTestProcess() {
    if (_isTestProcessOverride != null) {
      return _isTestProcessOverride();
    }

    return TestEnvironment.isTestProcess();
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
    String suggested = SettingsManager.suggestEnvName(provider, knownEnvNames);
    if (suggested.isNotEmpty) {
      return suggested;
    }

    for (final String alias in SettingsManager.envAliases(provider)) {
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

    final String fallbackProfile = SettingsManager.resolveProfileName(effectiveSettings, '');
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
    if (_isTestProcess()) {
      return;
    }

    final String effectiveProfile = profile.trim().isEmpty ? 'default' : profile.trim();
    _writeLine('');
    _writeLine('Next commands:');
    _writeLine('  $publicCommandName settings show --profile $effectiveProfile');
    _writeLine(
      '  $publicCommandName migrate --source-provider <provider> --source-url <url> --target-provider <provider> '
      '--target-url <url> --settings-profile $effectiveProfile',
    );
    _writeLine('  $publicCommandName resume --settings-profile $effectiveProfile');
    _writeLine('');
  }

  int _runSettingsInit(SettingsCommandOptions options) {
    final SettingsScopeData scope = SettingsManager.readScopeSettings(local: options.localScope);
    final Map<String, dynamic> effective = SettingsManager.loadEffectiveSettings();
    final String profile = SettingsManager.resolveProfileName(effective, options.profile);
    final Set<String> knownEnvNames = <String>{
      ..._environment.keys,
      ..._scanShellExportNames(),
    };

    Map<String, dynamic> updated = scope.payload;
    bool changed = false;
    const List<String> providerOrder = <String>['github', 'gitlab', 'bitbucket'];
    for (final String provider in providerOrder) {
      String defaultEnv = SettingsManager.suggestEnvName(provider, knownEnvNames);
      if (defaultEnv.isEmpty) {
        for (final String candidate in SettingsManager.envAliases(provider)) {
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

      updated = SettingsManager.setProviderTokenEnv(updated, profile: profile, provider: provider, envName: chosen);
      changed = true;
    }

    if (changed) {
      SettingsManager.writeSettingsFile(scope.path, updated);
      logger.info('Settings initialized at ${scope.path}');
    } else {
      logger.info('No settings were changed');
    }

    return 0;
  }
}
