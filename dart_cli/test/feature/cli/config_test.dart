import 'dart:io';

import 'package:args/args.dart';
import 'package:gfrm_dart/src/config.dart';
import 'package:gfrm_dart/src/config/arg_parsers.dart';
import 'package:gfrm_dart/src/core/session_store.dart';
import 'package:gfrm_dart/src/core/settings.dart';
import 'package:gfrm_dart/src/models/runtime_options.dart';
import '../../support/temp_dir.dart';
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

    test('parseCliRequest settings without action shows settings usage', () {
      final CliRequest request = CliRequestParser.parseCliRequest(<String>[commandSettings]);
      expect(request.command, 'help');
      expect(request.usage, contains('Usage: $publicCommandName settings <action> [options]'));
    });

    test('parseCliRequest settings --help shows settings usage', () {
      final CliRequest request = CliRequestParser.parseCliRequest(<String>[commandSettings, '--help']);
      expect(request.command, 'help');
      expect(request.usage, contains('Usage: $publicCommandName settings <action> [options]'));
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

    test('buildRootParser registers settings command', () {
      final ArgParser parser = CliParserCatalog.buildRootParser();
      expect(parser.commands.containsKey(commandSettings), isTrue);
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
      final Directory temp = createTempDir('gfrm-dart-config-');

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

    test('parseCliRequest honors --no-save-session for migrate and resume', () {
      final CliRequest migrateRequest = CliRequestParser.parseCliRequest(<String>[
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
        '--no-save-session',
      ]);
      expect(migrateRequest.options!.saveSession, isFalse);

      final Directory temp = createTempDir('gfrm-dart-config-save-session-');

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
        },
      );

      final CliRequest resumeRequest = CliRequestParser.parseCliRequest(<String>[
        commandResume,
        '--session-file',
        sessionPath,
        '--no-save-session',
      ]);
      expect(resumeRequest.options!.saveSession, isFalse);
    });

    test('parseCliRequest migrate resolves token from settings profile', () {
      final Directory tempWorkdir = createTempDir('gfrm-dart-settings-workdir-');

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

    test('parseCliRequest migrate prefers settings token_env over token_plain', () {
      final Directory tempWorkdir = createTempDir('gfrm-dart-settings-env-workdir-');
      final String settingsPath = '${tempWorkdir.path}/.gfrm/settings.yaml';
      SettingsManager.writeSettingsFile(
        settingsPath,
        <String, dynamic>{
          'profiles': <String, dynamic>{
            'work': <String, dynamic>{
              'providers': <String, dynamic>{
                'github': <String, dynamic>{
                  'token_env': 'GH_WORK_TOKEN',
                  'token_plain': 'source-from-plain',
                },
                'gitlab': <String, dynamic>{
                  'token_env': 'GL_WORK_TOKEN',
                  'token_plain': 'target-from-plain',
                },
              },
            },
          },
        },
      );

      final CliRequest request = CliRequestParser.parseCliRequest(
        <String>[
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
        ],
        cwd: tempWorkdir.path,
        env: <String, String>{
          'GH_WORK_TOKEN': 'source-from-env',
          'GL_WORK_TOKEN': 'target-from-env',
        },
      );

      final RuntimeOptions options = request.options!;
      expect(options.sourceToken, 'source-from-env');
      expect(options.targetToken, 'target-from-env');
    });

    test('parseCliRequest migrate falls back to environment aliases when settings are absent', () {
      final CliRequest request = CliRequestParser.parseCliRequest(
        <String>[
          commandMigrate,
          '--source-provider',
          'github',
          '--source-url',
          'https://github.com/acme/src',
          '--target-provider',
          'gitlab',
          '--target-url',
          'https://gitlab.com/acme/dst',
        ],
        env: <String, String>{
          'GH_TOKEN': 'source-from-alias',
          'GL_TOKEN': 'target-from-alias',
        },
      );

      final RuntimeOptions options = request.options!;
      expect(options.sourceToken, 'source-from-alias');
      expect(options.targetToken, 'target-from-alias');
    });

    test('parseCliRequest migrate explicit tokens override settings and environment fallbacks', () {
      final Directory tempWorkdir = createTempDir('gfrm-dart-settings-override-workdir-');
      final String settingsPath = '${tempWorkdir.path}/.gfrm/settings.yaml';
      SettingsManager.writeSettingsFile(
        settingsPath,
        <String, dynamic>{
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

      final CliRequest request = CliRequestParser.parseCliRequest(
        <String>[
          commandMigrate,
          '--source-provider',
          'github',
          '--source-url',
          'https://github.com/acme/src',
          '--source-token',
          'source-explicit',
          '--target-provider',
          'gitlab',
          '--target-url',
          'https://gitlab.com/acme/dst',
          '--target-token',
          'target-explicit',
          '--settings-profile',
          'work',
        ],
        cwd: tempWorkdir.path,
        env: <String, String>{
          'GH_TOKEN': 'source-from-alias',
          'GL_TOKEN': 'target-from-alias',
        },
      );

      final RuntimeOptions options = request.options!;
      expect(options.sourceToken, 'source-explicit');
      expect(options.targetToken, 'target-explicit');
    });

    test('parseCliRequest resume prefers session token context before settings and env aliases', () {
      final Directory temp = createTempDir('gfrm-dart-resume-session-precedence-');
      final String sessionPath = '${temp.path}/session.json';
      final String settingsPath = '${temp.path}/.gfrm/settings.yaml';

      SessionStore.saveSession(
        sessionPath,
        <String, dynamic>{
          'source_provider': 'github',
          'source_url': 'https://github.com/acme/src',
          'target_provider': 'gitlab',
          'target_url': 'https://gitlab.com/acme/dst',
          'source_token': 'source-from-session',
          'target_token': 'target-from-session',
          'session_token_mode': 'plain',
          'settings_profile': 'work',
        },
      );
      SettingsManager.writeSettingsFile(
        settingsPath,
        <String, dynamic>{
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

      final CliRequest request = CliRequestParser.parseCliRequest(
        <String>[
          commandResume,
          '--session-file',
          sessionPath,
        ],
        cwd: temp.path,
        env: <String, String>{
          'GH_TOKEN': 'source-from-alias',
          'GL_TOKEN': 'target-from-alias',
        },
      );

      final RuntimeOptions options = request.options!;
      expect(options.sourceToken, 'source-from-session');
      expect(options.targetToken, 'target-from-session');
    });

    test('parseCliRequest resume falls back to settings when session env refs are unavailable', () {
      final Directory temp = createTempDir('gfrm-dart-resume-settings-fallback-');
      final String sessionPath = '${temp.path}/session.json';
      final String settingsPath = '${temp.path}/.gfrm/settings.yaml';

      SessionStore.saveSession(
        sessionPath,
        <String, dynamic>{
          'source_provider': 'github',
          'source_url': 'https://github.com/acme/src',
          'target_provider': 'gitlab',
          'target_url': 'https://gitlab.com/acme/dst',
          'source_token_env': 'MISSING_SOURCE_ENV',
          'target_token_env': 'MISSING_TARGET_ENV',
          'session_token_mode': 'env',
          'settings_profile': 'work',
        },
      );
      SettingsManager.writeSettingsFile(
        settingsPath,
        <String, dynamic>{
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

      final CliRequest request = CliRequestParser.parseCliRequest(
        <String>[
          commandResume,
          '--session-file',
          sessionPath,
        ],
        cwd: temp.path,
        env: <String, String>{},
      );

      final RuntimeOptions options = request.options!;
      expect(options.sourceToken, 'source-from-settings');
      expect(options.targetToken, 'target-from-settings');
    });

    test('parseCliRequest resume explicit hidden tokens override session, settings, and env aliases', () {
      final Directory temp = createTempDir('gfrm-dart-resume-explicit-override-');
      final String sessionPath = '${temp.path}/session.json';
      final String settingsPath = '${temp.path}/.gfrm/settings.yaml';

      SessionStore.saveSession(
        sessionPath,
        <String, dynamic>{
          'source_provider': 'github',
          'source_url': 'https://github.com/acme/src',
          'target_provider': 'gitlab',
          'target_url': 'https://gitlab.com/acme/dst',
          'source_token': 'source-from-session',
          'target_token': 'target-from-session',
          'session_token_mode': 'plain',
          'settings_profile': 'work',
        },
      );
      SettingsManager.writeSettingsFile(
        settingsPath,
        <String, dynamic>{
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

      final CliRequest request = CliRequestParser.parseCliRequest(
        <String>[
          commandResume,
          '--session-file',
          sessionPath,
          '--source-token',
          'source-explicit',
          '--target-token',
          'target-explicit',
        ],
        cwd: temp.path,
        env: <String, String>{
          'GH_TOKEN': 'source-from-alias',
          'GL_TOKEN': 'target-from-alias',
        },
      );

      final RuntimeOptions options = request.options!;
      expect(options.sourceToken, 'source-explicit');
      expect(options.targetToken, 'target-explicit');
    });

    test('parseCliRequest builds demo runtime with defaults', () {
      final CliRequest request = CliRequestParser.parseCliRequest(<String>[
        commandDemo,
        '--source-provider',
        'gh',
        '--target-provider',
        'gl',
      ]);

      final RuntimeOptions options = request.options!;
      expect(request.command, commandDemo);
      expect(options.commandName, commandDemo);
      expect(options.sourceProvider, 'github');
      expect(options.targetProvider, 'gitlab');
      expect(options.demoMode, isTrue);
      expect(options.demoReleases, 5);
      expect(options.demoSleepSeconds, 1.0);
    });

    test('parseCliRequest builds demo runtime with explicit release count', () {
      final CliRequest request = CliRequestParser.parseCliRequest(<String>[
        commandDemo,
        '--source-provider',
        'github',
        '--target-provider',
        'gitlab',
        '--demo-releases',
        '10',
        '--demo-sleep-seconds',
        '0.5',
        '--download-workers',
        '2',
      ]);

      final RuntimeOptions options = request.options!;
      expect(options.demoMode, isTrue);
      expect(options.demoReleases, 10);
      expect(options.demoSleepSeconds, closeTo(0.5, 0.001));
      expect(options.downloadWorkers, 2);
    });
  });
}
