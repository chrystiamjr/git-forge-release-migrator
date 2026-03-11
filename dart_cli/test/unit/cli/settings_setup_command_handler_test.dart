import 'dart:io';

import 'package:gfrm_dart/src/cli/settings_setup_command_handler.dart';
import 'package:gfrm_dart/src/config.dart';
import 'package:gfrm_dart/src/core/settings.dart';
import '../../support/logging.dart';
import '../../support/temp_dir.dart';
import 'package:test/test.dart';

void main() {
  group('SettingsSetupCommandHandler', () {
    test('setup skips when token configuration already exists and force is false', () {
      final Directory temp = createTempDir('gfrm-setup-skip-');
      withCurrentDirectory(temp);

      final String settingsPath = SettingsManager.defaultLocalSettingsPath(cwd: temp.path);
      SettingsManager.writeSettingsFile(
        settingsPath,
        <String, dynamic>{
          'profiles': <String, dynamic>{
            'default': <String, dynamic>{
              'providers': <String, dynamic>{
                'github': <String, dynamic>{'token_env': 'GH_TOKEN'},
              },
            },
          },
        },
      );

      final List<String> output = <String>[];
      final SettingsSetupCommandHandler handler = SettingsSetupCommandHandler(
        logger: createSilentLogger(),
        outputLine: output.add,
        isTestProcess: () => false,
      );

      final int exitCode = handler.runSetupCommand(
        const SetupCommandOptions(profile: '', localScope: true, assumeYes: true, force: false),
      );

      expect(exitCode, 0);
      expect(output.join('\n'), contains('settings show --profile default'));
      final Map<String, dynamic> payload = SettingsManager.loadSettingsFile(settingsPath);
      expect(
        ((((payload['profiles'] as Map<String, dynamic>)['default'] as Map<String, dynamic>)['providers']
            as Map<String, dynamic>)['github'] as Map<String, dynamic>)['token_env'],
        'GH_TOKEN',
      );
    });

    test('interactive setup uses prompts and writes selected env names', () {
      final Directory temp = createTempDir('gfrm-setup-interactive-');
      withCurrentDirectory(temp);

      final List<String> prompts = <String>[];
      final List<String> answers = <String>['work', 'yes', '', 'GL_WORK_TOKEN', 'BB_WORK_TOKEN'];
      final SettingsSetupCommandHandler handler = SettingsSetupCommandHandler(
        logger: createSilentLogger(),
        promptLine: (String prompt) {
          prompts.add(prompt);
          return answers.removeAt(0);
        },
        environment: <String, String>{'GH_TOKEN': 'x'},
        scanShellExportNames: () => <String>{},
        isTestProcess: () => true,
      );

      final int exitCode = handler.runSetupCommand(
        const SetupCommandOptions(profile: '', localScope: false, assumeYes: false, force: true),
      );

      expect(exitCode, 0);
      expect(prompts, hasLength(5));

      final String settingsPath = SettingsManager.defaultLocalSettingsPath(cwd: temp.path);
      final Map<String, dynamic> payload = SettingsManager.loadSettingsFile(settingsPath);
      final Map<String, dynamic> workProfile = (((payload['profiles'] as Map<String, dynamic>)['work']
          as Map<String, dynamic>)['providers'] as Map<String, dynamic>);

      expect((workProfile['github'] as Map<String, dynamic>)['token_env'], 'GH_TOKEN');
      expect((workProfile['gitlab'] as Map<String, dynamic>)['token_env'], 'GL_WORK_TOKEN');
      expect((workProfile['bitbucket'] as Map<String, dynamic>)['token_env'], 'BB_WORK_TOKEN');
    });

    test('setup falls back to provider aliases in assume-yes mode', () {
      final Directory temp = createTempDir('gfrm-setup-alias-');
      withCurrentDirectory(temp);

      final SettingsSetupCommandHandler handler = SettingsSetupCommandHandler(
        logger: createSilentLogger(),
        environment: const <String, String>{},
        scanShellExportNames: () => <String>{},
        isTestProcess: () => true,
      );

      final int exitCode = handler.runSetupCommand(
        const SetupCommandOptions(profile: 'auto', localScope: true, assumeYes: true, force: true),
      );

      expect(exitCode, 0);

      final String settingsPath = SettingsManager.defaultLocalSettingsPath(cwd: temp.path);
      final Map<String, dynamic> payload = SettingsManager.loadSettingsFile(settingsPath);
      final Map<String, dynamic> providers = (((payload['profiles'] as Map<String, dynamic>)['auto']
          as Map<String, dynamic>)['providers'] as Map<String, dynamic>);

      expect((providers['github'] as Map<String, dynamic>)['token_env'], 'GITHUB_TOKEN');
      expect((providers['gitlab'] as Map<String, dynamic>)['token_env'], 'GITLAB_TOKEN');
      expect((providers['bitbucket'] as Map<String, dynamic>)['token_env'], 'BITBUCKET_TOKEN');
    });

    test('settings show masks token_plain values in output', () {
      final Directory temp = createTempDir('gfrm-settings-show-unit-');
      withCurrentDirectory(temp);

      final String settingsPath = SettingsManager.defaultLocalSettingsPath(cwd: temp.path);
      SettingsManager.writeSettingsFile(
        settingsPath,
        <String, dynamic>{
          'profiles': <String, dynamic>{
            'work': <String, dynamic>{
              'providers': <String, dynamic>{
                'github': <String, dynamic>{'token_plain': 'super-secret'},
              },
            },
          },
        },
      );

      final List<String> output = <String>[];
      final SettingsSetupCommandHandler handler = SettingsSetupCommandHandler(
        logger: createSilentLogger(),
        outputLine: output.add,
        isTestProcess: () => false,
      );

      final int exitCode = handler.runSettingsCommand(
        const SettingsCommandOptions(
          action: settingsActionShow,
          profile: 'work',
          provider: '',
          envName: '',
          token: '',
          localScope: true,
          assumeYes: true,
        ),
      );

      expect(exitCode, 0);
      expect(output.single, contains('***'));
      expect(output.single, isNot(contains('super-secret')));
    });

    test('set-token-plain prompts for token when option is empty', () {
      final Directory temp = createTempDir('gfrm-settings-plain-');
      withCurrentDirectory(temp);

      final SettingsSetupCommandHandler handler = SettingsSetupCommandHandler(
        logger: createSilentLogger(),
        promptLine: (_) => 'prompt-token',
        isTestProcess: () => true,
      );

      final int exitCode = handler.runSettingsCommand(
        const SettingsCommandOptions(
          action: settingsActionSetTokenPlain,
          profile: 'work',
          provider: 'github',
          envName: '',
          token: '',
          localScope: true,
          assumeYes: true,
        ),
      );

      expect(exitCode, 0);

      final String settingsPath = SettingsManager.defaultLocalSettingsPath(cwd: temp.path);
      final Map<String, dynamic> payload = SettingsManager.loadSettingsFile(settingsPath);
      expect(
        (((payload['profiles'] as Map<String, dynamic>)['work'] as Map<String, dynamic>)['providers']
            as Map<String, dynamic>)['github'],
        <String, dynamic>{'token_plain': 'prompt-token'},
      );
    });

    test('settings init writes discovered env names in assume-yes mode', () {
      final Directory temp = createTempDir('gfrm-settings-init-');
      withCurrentDirectory(temp);

      final SettingsSetupCommandHandler handler = SettingsSetupCommandHandler(
        logger: createSilentLogger(),
        environment: <String, String>{
          'GH_TOKEN': 'x',
          'GL_TOKEN': 'y',
          'BB_TOKEN': 'z',
        },
        scanShellExportNames: () => <String>{},
        isTestProcess: () => true,
      );

      final int exitCode = handler.runSettingsCommand(
        const SettingsCommandOptions(
          action: settingsActionInit,
          profile: 'work',
          provider: '',
          envName: '',
          token: '',
          localScope: true,
          assumeYes: true,
        ),
      );

      expect(exitCode, 0);

      final String settingsPath = SettingsManager.defaultLocalSettingsPath(cwd: temp.path);
      final Map<String, dynamic> payload = SettingsManager.loadSettingsFile(settingsPath);
      final Map<String, dynamic> providers = (((payload['profiles'] as Map<String, dynamic>)['work']
          as Map<String, dynamic>)['providers'] as Map<String, dynamic>);

      expect((providers['github'] as Map<String, dynamic>)['token_env'], 'GH_TOKEN');
      expect((providers['gitlab'] as Map<String, dynamic>)['token_env'], 'GL_TOKEN');
      expect((providers['bitbucket'] as Map<String, dynamic>)['token_env'], 'BB_TOKEN');
    });
  });
}
