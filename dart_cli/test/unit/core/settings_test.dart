import 'dart:io';

import 'package:gfrm_dart/src/core/settings.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('settings', () {
    test('resolveProfileName prefers explicit then defaults then default', () {
      final Map<String, dynamic> payload = <String, dynamic>{
        'defaults': <String, dynamic>{'profile': 'work'},
      };

      expect(SettingsManager.resolveProfileName(payload, 'personal'), 'personal');
      expect(SettingsManager.resolveProfileName(payload, ''), 'work');
      expect(SettingsManager.resolveProfileName(<String, dynamic>{}, ''), 'default');
    });

    test('loadEffectiveSettings deep-merges global and local', () {
      final Directory home = Directory.systemTemp.createTempSync('gfrm-dart-settings-home-');
      final Directory cwd = Directory.systemTemp.createTempSync('gfrm-dart-settings-cwd-');
      addTearDown(() => home.deleteSync(recursive: true));
      addTearDown(() => cwd.deleteSync(recursive: true));

      final String globalPath = SettingsManager.defaultGlobalSettingsPath(homeDir: home.path, env: <String, String>{});
      final String localPath = SettingsManager.defaultLocalSettingsPath(cwd: cwd.path);

      SettingsManager.writeSettingsFile(
        globalPath,
        <String, dynamic>{
          'defaults': <String, dynamic>{'profile': 'work'},
          'profiles': <String, dynamic>{
            'work': <String, dynamic>{
              'providers': <String, dynamic>{
                'github': <String, dynamic>{'token_env': 'GH_WORK_TOKEN'},
              },
            },
          },
        },
      );

      SettingsManager.writeSettingsFile(
        localPath,
        <String, dynamic>{
          'profiles': <String, dynamic>{
            'work': <String, dynamic>{
              'providers': <String, dynamic>{
                'gitlab': <String, dynamic>{'token_plain': 'gl-local-token'},
              },
            },
          },
        },
      );

      final Map<String, dynamic> effective = SettingsManager.loadEffectiveSettings(
        cwd: cwd.path,
        homeDir: home.path,
        env: <String, String>{},
      );

      expect(SettingsManager.resolveProfileName(effective, ''), 'work');
      final Map<String, dynamic> providers =
          (effective['profiles'] as Map<String, dynamic>)['work'] as Map<String, dynamic>;
      final Map<String, dynamic> providerMap = providers['providers'] as Map<String, dynamic>;
      expect((providerMap['github'] as Map<String, dynamic>)['token_env'], 'GH_WORK_TOKEN');
      expect((providerMap['gitlab'] as Map<String, dynamic>)['token_plain'], 'gl-local-token');
    });

    test('tokenFromSettings prefers token_env over token_plain', () {
      final Map<String, dynamic> payload = <String, dynamic>{
        'profiles': <String, dynamic>{
          'work': <String, dynamic>{
            'providers': <String, dynamic>{
              'github': <String, dynamic>{
                'token_env': 'GH_WORK_TOKEN',
                'token_plain': 'plain-token',
              },
            },
          },
        },
      };

      final String fromEnv = SettingsManager.tokenFromSettings(
        payload,
        'work',
        'github',
        env: <String, String>{'GH_WORK_TOKEN': 'env-token'},
      );
      final String fromPlain = SettingsManager.tokenFromSettings(
        payload,
        'work',
        'github',
        env: <String, String>{},
      );

      expect(fromEnv, 'env-token');
      expect(fromPlain, 'plain-token');
    });

    test('tokenFromEnvAliases uses side env first', () {
      final String resolved = SettingsManager.tokenFromEnvAliases(
        'github',
        sideEnvName: 'CUSTOM_SOURCE_TOKEN',
        env: <String, String>{
          'CUSTOM_SOURCE_TOKEN': 'custom-token',
          'GH_TOKEN': 'gh-token',
        },
      );

      expect(resolved, 'custom-token');
    });

    test('set/unset provider token updates profile data', () {
      Map<String, dynamic> payload = <String, dynamic>{};
      payload =
          SettingsManager.setProviderTokenEnv(payload, profile: 'work', provider: 'github', envName: 'GH_WORK_TOKEN');
      expect(
        (((payload['profiles'] as Map<String, dynamic>)['work'] as Map<String, dynamic>)['providers']
            as Map<String, dynamic>)['github'],
        <String, dynamic>{'token_env': 'GH_WORK_TOKEN'},
      );

      payload =
          SettingsManager.setProviderTokenPlain(payload, profile: 'work', provider: 'github', token: 'plain-value');
      expect(
        (((payload['profiles'] as Map<String, dynamic>)['work'] as Map<String, dynamic>)['providers']
            as Map<String, dynamic>)['github'],
        <String, dynamic>{'token_plain': 'plain-value'},
      );

      payload = SettingsManager.unsetProviderToken(payload, profile: 'work', provider: 'github');
      final Map<String, dynamic> profiles = payload['profiles'] as Map<String, dynamic>;
      expect(profiles.containsKey('work'), isFalse);
    });

    test('maskSettingsSecrets redacts token_plain values', () {
      final Map<String, dynamic> masked = SettingsManager.maskSettingsSecrets(<String, dynamic>{
        'profiles': <String, dynamic>{
          'work': <String, dynamic>{
            'providers': <String, dynamic>{
              'github': <String, dynamic>{
                'token_plain': 'secret-value',
                'token_env': 'GH_TOKEN',
              },
            },
          },
        },
      });

      final Map<String, dynamic> provider = ((((masked['profiles'] as Map<String, dynamic>)['work']
          as Map<String, dynamic>)['providers'] as Map<String, dynamic>)['github'] as Map<String, dynamic>);
      expect(provider['token_plain'], '***');
      expect(provider['token_env'], 'GH_TOKEN');
    });

    test('scanShellExportNames parses export and assignment lines', () {
      final Directory temp = Directory.systemTemp.createTempSync('gfrm-dart-shell-scan-');
      addTearDown(() => temp.deleteSync(recursive: true));

      final String shellPath = p.join(temp.path, '.zshrc');
      File(shellPath).writeAsStringSync(
        '# comment\n'
        'export GH_TOKEN=abc\n'
        'GL_TOKEN=def\n'
        'not_valid line\n',
      );

      final Set<String> names = SettingsManager.scanShellExportNames(paths: <String>[shellPath]);
      expect(names.contains('GH_TOKEN'), isTrue);
      expect(names.contains('GL_TOKEN'), isTrue);
      expect(names.contains('not_valid'), isFalse);
    });

    test('writeSettingsFile overwrites existing settings file atomically', () {
      final Directory temp = Directory.systemTemp.createTempSync('gfrm-dart-settings-write-');
      addTearDown(() => temp.deleteSync(recursive: true));

      final String settingsPath = p.join(temp.path, '.gfrm', 'settings.yaml');
      SettingsManager.writeSettingsFile(settingsPath, <String, dynamic>{
        'version': 1,
        'defaults': <String, dynamic>{'profile': 'work'},
      });
      SettingsManager.writeSettingsFile(settingsPath, <String, dynamic>{
        'version': 1,
        'defaults': <String, dynamic>{'profile': 'personal'},
      });

      final Map<String, dynamic> loaded = SettingsManager.loadSettingsFile(settingsPath);
      final Map<String, dynamic> defaults = loaded['defaults'] as Map<String, dynamic>;
      expect(defaults['profile'], 'personal');
    });
  });
}
