import 'dart:io';

import 'package:gfrm_dart/src/config.dart';
import 'package:gfrm_dart/src/core/session_store.dart';
import 'package:gfrm_dart/src/core/settings.dart';
import 'package:gfrm_dart/src/models/runtime_options.dart';
import 'package:test/test.dart';

void main() {
  group('config', () {
    test('parseCliRequest builds migrate runtime', () {
      final CliRequest request = CliRequestParser.parseCliRequest(<String>[
        commandMigrate,
        '--source-provider',
        'gh',
        '--source-url',
        'https://github.com/o/r',
        '--source-token',
        's',
        '--target-provider',
        'gl',
        '--target-url',
        'https://gitlab.com/g/p',
        '--target-token',
        't',
        '--skip-tags',
        '--download-workers',
        '6',
        '--release-workers',
        '2',
      ]);

      final RuntimeOptions options = request.options!;
      expect(request.command, commandMigrate);
      expect(options.sourceProvider, 'github');
      expect(options.targetProvider, 'gitlab');
      expect(options.skipTagMigration, isTrue);
      expect(options.downloadWorkers, 6);
      expect(options.releaseWorkers, 2);
      expect(options.commandName, commandMigrate);
    });

    test('parseCliRequest builds settings request', () {
      final CliRequest request = CliRequestParser.parseCliRequest(<String>[
        commandSettings,
        settingsActionSetTokenEnv,
        '--provider',
        'gh',
        '--env-name',
        'GH_TOKEN',
        '--profile',
        'work',
        '--local',
      ]);

      expect(request.command, commandSettings);
      final SettingsCommandOptions options = request.settings!;
      expect(options.action, settingsActionSetTokenEnv);
      expect(options.provider, 'github');
      expect(options.envName, 'GH_TOKEN');
      expect(options.profile, 'work');
      expect(options.localScope, isTrue);
    });

    test('parseCliRequest builds setup request', () {
      final CliRequest request = CliRequestParser.parseCliRequest(<String>[
        commandSetup,
        '--profile',
        'work',
        '--local',
        '--yes',
        '--force',
      ]);

      expect(request.command, commandSetup);
      final SetupCommandOptions options = request.setup!;
      expect(options.profile, 'work');
      expect(options.localScope, isTrue);
      expect(options.assumeYes, isTrue);
      expect(options.force, isTrue);
    });

    test('parseCliRequest validates ranges', () {
      expect(
        () => CliRequestParser.parseCliRequest(<String>[
          commandMigrate,
          '--source-provider',
          'github',
          '--source-url',
          'https://github.com/o/r',
          '--source-token',
          's',
          '--target-provider',
          'gitlab',
          '--target-url',
          'https://gitlab.com/g/p',
          '--target-token',
          't',
          '--from-tag',
          'v2.0.0',
          '--to-tag',
          'v1.0.0',
        ]),
        throwsArgumentError,
      );
    });

    test('parseCliRequest loads resume session', () {
      final Directory temp = Directory.systemTemp.createTempSync('gfrm-dart-config-');
      addTearDown(() => temp.deleteSync(recursive: true));

      final String sessionPath = '${temp.path}/session.json';
      SessionStore.saveSession(
        sessionPath,
        <String, dynamic>{
          'source_provider': 'github',
          'source_url': 'https://github.com/acme/src',
          'target_provider': 'gitlab',
          'target_url': 'https://gitlab.com/acme/dst',
          'source_token': 'source-token',
          'target_token': 'target-token',
          'session_token_mode': 'plain',
          'from_tag': 'v1.0.0',
          'to_tag': 'v2.0.0',
          'download_workers': 4,
          'release_workers': 1,
        },
      );

      final CliRequest request = CliRequestParser.parseCliRequest(<String>[
        commandResume,
        '--session-file',
        sessionPath,
        '--download-workers',
        '7',
      ]);

      final RuntimeOptions options = request.options!;
      expect(request.command, commandResume);
      expect(options.sourceProvider, 'github');
      expect(options.targetProvider, 'gitlab');
      expect(options.sourceToken, 'source-token');
      expect(options.targetToken, 'target-token');
      expect(options.downloadWorkers, 7);
      expect(options.commandName, commandResume);
    });

    test('parseCliRequest migrate resolves token from settings profile', () {
      final Directory tempWorkdir = Directory.systemTemp.createTempSync('gfrm-dart-settings-workdir-');
      addTearDown(() => tempWorkdir.deleteSync(recursive: true));

      final String settingsPath = '${tempWorkdir.path}/.gfrm/settings.yaml';
      SettingsManager.writeSettingsFile(
        settingsPath,
        <String, dynamic>{
          'version': 1,
          'defaults': <String, dynamic>{'profile': 'default'},
          'profiles': <String, dynamic>{
            'work': <String, dynamic>{
              'providers': <String, dynamic>{
                'github': <String, dynamic>{'token_plain': 'source-from-settings'},
                'gitlab': <String, dynamic>{'token_plain': 'target-from-settings'},
              },
            },
          },
        },
      );

      final CliRequest request = IOOverrides.runZoned<CliRequest>(
        () => CliRequestParser.parseCliRequest(<String>[
          commandMigrate,
          '--source-provider',
          'github',
          '--source-url',
          'https://github.com/acme/src',
          '--target-provider',
          'gitlab',
          '--target-url',
          'https://gitlab.com/acme/dst',
          '--settings-profile',
          'work',
        ]),
        getCurrentDirectory: () => tempWorkdir,
      );

      final RuntimeOptions options = request.options!;
      expect(options.sourceToken, 'source-from-settings');
      expect(options.targetToken, 'target-from-settings');
      expect(options.settingsProfile, 'work');
    });
  });
}
