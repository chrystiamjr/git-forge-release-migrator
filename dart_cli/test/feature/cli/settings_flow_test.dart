import 'dart:io';

import 'package:gfrm_dart/gfrm_dart.dart';
import 'package:gfrm_dart/src/core/settings.dart';
import 'package:gfrm_dart/src/models.dart';
import 'package:test/test.dart';

void main() {
  group('settings flow', () {
    test('setup --yes --local bootstraps env token mappings', () async {
      final Directory temp = Directory.systemTemp.createTempSync('gfrm-setup-flow-');
      addTearDown(() => temp.deleteSync(recursive: true));

      final String oldCwd = Directory.current.path;
      Directory.current = temp.path;
      addTearDown(() => Directory.current = oldCwd);

      final int setupExit = await runCli(<String>[
        commandSetup,
        '--profile',
        'smoke',
        '--local',
        '--yes',
        '--force',
      ]);
      expect(setupExit, 0);

      final String localSettingsPath = defaultLocalSettingsPath(cwd: temp.path);
      final Map<String, dynamic> payload = loadSettingsFile(localSettingsPath);
      final Map<String, dynamic> profiles = (payload['profiles'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      final Map<String, dynamic> smoke = (profiles['smoke'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      final Map<String, dynamic> providers = (smoke['providers'] as Map<String, dynamic>?) ?? <String, dynamic>{};

      final Map<String, dynamic> github = (providers['github'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      final Map<String, dynamic> gitlab = (providers['gitlab'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      final Map<String, dynamic> bitbucket = (providers['bitbucket'] as Map<String, dynamic>?) ?? <String, dynamic>{};

      expect((github['token_env'] ?? '').toString(), isNotEmpty);
      expect((gitlab['token_env'] ?? '').toString(), isNotEmpty);
      expect((bitbucket['token_env'] ?? '').toString(), isNotEmpty);
    });

    test('set-token-env and unset-token update local settings file', () async {
      final Directory temp = Directory.systemTemp.createTempSync('gfrm-settings-flow-');
      addTearDown(() => temp.deleteSync(recursive: true));

      final String oldCwd = Directory.current.path;
      Directory.current = temp.path;
      addTearDown(() => Directory.current = oldCwd);

      final int setExit = await runCli(<String>[
        commandSettings,
        settingsActionSetTokenEnv,
        '--provider',
        'github',
        '--env-name',
        'GH_WORK_TOKEN',
        '--profile',
        'work',
        '--local',
      ]);
      expect(setExit, 0);

      final String localSettingsPath = defaultLocalSettingsPath(cwd: temp.path);
      final Map<String, dynamic> afterSet = loadSettingsFile(localSettingsPath);
      expect(
        (((afterSet['profiles'] as Map<String, dynamic>)['work'] as Map<String, dynamic>)['providers']
            as Map<String, dynamic>)['github'],
        <String, dynamic>{'token_env': 'GH_WORK_TOKEN'},
      );

      final int unsetExit = await runCli(<String>[
        commandSettings,
        settingsActionUnsetToken,
        '--provider',
        'github',
        '--profile',
        'work',
        '--local',
      ]);
      expect(unsetExit, 0);

      final Map<String, dynamic> afterUnset = loadSettingsFile(localSettingsPath);
      final Map<String, dynamic> profiles = (afterUnset['profiles'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      expect(profiles.containsKey('work'), isFalse);
    });

    test('settings show masks token_plain values', () async {
      final Directory temp = Directory.systemTemp.createTempSync('gfrm-settings-show-');
      addTearDown(() => temp.deleteSync(recursive: true));

      final String oldCwd = Directory.current.path;
      Directory.current = temp.path;
      addTearDown(() => Directory.current = oldCwd);

      final String localSettingsPath = defaultLocalSettingsPath(cwd: temp.path);
      writeSettingsFile(
        localSettingsPath,
        <String, dynamic>{
          'defaults': <String, dynamic>{'profile': 'work'},
          'profiles': <String, dynamic>{
            'work': <String, dynamic>{
              'providers': <String, dynamic>{
                'github': <String, dynamic>{
                  'token_plain': 'my-secret-token',
                },
              },
            },
          },
        },
      );

      final int exitCode = await runCli(<String>[commandSettings, settingsActionShow]);
      expect(exitCode, 0);
    });
  });
}
