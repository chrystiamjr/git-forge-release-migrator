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
    test('parseCliRequest without args returns root usage help', () {
      final CliRequest request = CliRequestParser.parseCliRequest(<String>[]);

      expect(request.command, 'help');
      expect(request.usage, contains('Usage: $publicCommandName <command> [options]'));
    });

    test('parseCliRequest root --help returns root usage help', () {
      final CliRequest request = CliRequestParser.parseCliRequest(<String>['--help']);

      expect(request.command, 'help');
      expect(request.usage, contains('Commands:'));
    });

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
        '--skip-releases',
        '--skip-release-assets',
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
      expect(options.skipReleaseMigration, isTrue);
      expect(options.skipReleaseAssetMigration, isTrue);
      expect(options.downloadWorkers, 6);
      expect(options.releaseWorkers, 2);
      expect(options.commandName, commandMigrate);
    });

    test('parseCliRequest migrate preserves optional common runtime flags', () {
      final CliRequest request = CliRequestParser.parseCliRequest(<String>[
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
        '--workdir',
        '/tmp/custom-results',
        '--log-file',
        '/tmp/custom-log.jsonl',
        '--checkpoint-file',
        '/tmp/checkpoints.jsonl',
        '--tags-file',
        '/tmp/tags.txt',
        '--no-banner',
        '--quiet',
        '--json',
        '--progress-bar',
      ]);

      final RuntimeOptions options = request.options!;
      expect(options.workdir, '/tmp/custom-results');
      expect(options.logFile, '/tmp/custom-log.jsonl');
      expect(options.checkpointFile, '/tmp/checkpoints.jsonl');
      expect(options.tagsFile, '/tmp/tags.txt');
      expect(options.noBanner, isTrue);
      expect(options.quiet, isTrue);
      expect(options.jsonOutput, isTrue);
      expect(options.progressBar, isTrue);
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

    test('parseCliRequest settings show preserves blank provider and defaults', () {
      final CliRequest request = CliRequestParser.parseCliRequest(<String>[
        commandSettings,
        settingsActionShow,
      ]);

      expect(request.command, commandSettings);
      expect(request.settings!.action, settingsActionShow);
      expect(request.settings!.provider, isEmpty);
      expect(request.settings!.localScope, isFalse);
    });

    test('parseCliRequest settings keeps unknown provider aliases empty for later validation', () {
      final CliRequest request = CliRequestParser.parseCliRequest(<String>[
        commandSettings,
        settingsActionSetTokenEnv,
        '--provider',
        'azure',
        '--env-name',
        'AZ_TOKEN',
      ]);

      expect(request.settings!.provider, isEmpty);
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

    test('parseCliRequest setup request keeps defaults when optional flags are absent', () {
      final CliRequest request = CliRequestParser.parseCliRequest(<String>[commandSetup]);

      expect(request.command, commandSetup);
      expect(request.setup!.profile, isEmpty);
      expect(request.setup!.localScope, isFalse);
      expect(request.setup!.assumeYes, isFalse);
      expect(request.setup!.force, isFalse);
    });

    test('parseCliRequest setup --help returns setup usage', () {
      final CliRequest request = CliRequestParser.parseCliRequest(<String>[commandSetup, '--help']);

      expect(request.command, 'help');
      expect(request.usage, contains('Usage: $publicCommandName setup [options]'));
    });

    test('parseCliRequest migrate --help returns migrate usage', () {
      final CliRequest request = CliRequestParser.parseCliRequest(<String>[commandMigrate, '--help']);

      expect(request.command, 'help');
      expect(request.usage, contains('Usage: $publicCommandName migrate [options]'));
    });

    test('parseCliRequest resume --help returns resume usage', () {
      final CliRequest request = CliRequestParser.parseCliRequest(<String>[commandResume, '--help']);

      expect(request.command, 'help');
      expect(request.usage, contains('Usage: $publicCommandName resume [options]'));
    });

    test('parseCliRequest demo --help returns demo usage', () {
      final CliRequest request = CliRequestParser.parseCliRequest(<String>[commandDemo, '--help']);

      expect(request.command, 'help');
      expect(request.usage, contains('Usage: $publicCommandName demo [options]'));
    });

    test('parseCliRequest settings action --help returns action usage', () {
      final CliRequest request =
          CliRequestParser.parseCliRequest(<String>[commandSettings, settingsActionShow, '--help']);

      expect(request.command, 'help');
      expect(request.usage, contains('Usage: $publicCommandName settings $settingsActionShow [options]'));
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

    test('parseCliRequest rejects invalid migrate session-token-mode', () {
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
          '--session-token-mode',
          'invalid',
        ]),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.message,
            'message',
            '--session-token-mode must be one of: env, plain',
          ),
        ),
      );
    });

    test('parseCliRequest rejects invalid worker bounds for migrate', () {
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
          '--download-workers',
          '0',
        ]),
        throwsArgumentError,
      );
    });

    test('parseCliRequest allows missing resolved tokens so structured preflight can report them later', () {
      final Directory tempWorkdir = createTempDir('gfrm-dart-preflight-missing-token-');

      final CliRequest request = CliRequestParser.parseCliRequest(
          <String>[
            commandMigrate,
            '--source-provider',
            'github',
            '--source-url',
            'https://github.com/o/r',
            '--target-provider',
            'gitlab',
            '--target-url',
            'https://gitlab.com/g/p',
          ],
          cwd: tempWorkdir.path,
          env: <String, String>{});

      final RuntimeOptions options = request.options!;
      expect(options.sourceToken, isEmpty);
      expect(options.targetToken, isEmpty);
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
          'skip_release_migration': true,
          'skip_release_asset_migration': true,
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
      expect(options.skipReleaseMigration, isTrue);
      expect(options.skipReleaseAssetMigration, isTrue);
      expect(options.commandName, commandResume);
    });

    test('parseCliRequest resume allows explicit release skip overrides', () {
      final Directory temp = createTempDir('gfrm-dart-resume-skip-overrides-');

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
          'skip_release_migration': false,
          'skip_release_asset_migration': false,
        },
      );

      final CliRequest request = CliRequestParser.parseCliRequest(<String>[
        commandResume,
        '--session-file',
        sessionPath,
        '--skip-releases',
        '--skip-release-assets',
      ]);

      final RuntimeOptions options = request.options!;
      expect(options.skipReleaseMigration, isTrue);
      expect(options.skipReleaseAssetMigration, isTrue);
    });

    test('parseCliRequest resume rejects sessions without repository urls', () {
      final Directory temp = createTempDir('gfrm-dart-resume-missing-urls-');
      final String sessionPath = '${temp.path}/session.json';

      SessionStore.saveSession(
        sessionPath,
        <String, dynamic>{
          'source_provider': 'github',
          'target_provider': 'gitlab',
          'source_token': 'source-token',
          'target_token': 'target-token',
        },
      );

      expect(
        () => CliRequestParser.parseCliRequest(<String>[
          commandResume,
          '--session-file',
          sessionPath,
        ]),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.message,
            'message',
            'Session file is missing source_url/target_url',
          ),
        ),
      );
    });

    test('parseCliRequest resume rejects invalid session-token-mode override', () {
      final Directory temp = createTempDir('gfrm-dart-resume-invalid-mode-');
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

      expect(
        () => CliRequestParser.parseCliRequest(<String>[
          commandResume,
          '--session-file',
          sessionPath,
          '--session-token-mode',
          'bogus',
        ]),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError error) => error.message,
            'message',
            '--session-token-mode must be one of: env, plain',
          ),
        ),
      );
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

    test('parseCliRequest migrate falls back to env aliases when settings are absent', () {
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

    test('parseCliRequest resume preserves session defaults when optional flags are not passed', () {
      final Directory temp = createTempDir('gfrm-dart-resume-session-defaults-');
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
          'download_workers': 5,
          'release_workers': 2,
          'skip_tag_migration': true,
        },
      );

      final CliRequest request = CliRequestParser.parseCliRequest(<String>[
        commandResume,
        '--session-file',
        sessionPath,
      ]);

      final RuntimeOptions options = request.options!;
      expect(options.fromTag, 'v1.0.0');
      expect(options.toTag, 'v2.0.0');
      expect(options.downloadWorkers, 5);
      expect(options.releaseWorkers, 2);
      expect(options.skipTagMigration, isTrue);
    });

    test('parseCliRequest resume falls back to default session env names when session omits them', () {
      final Directory temp = createTempDir('gfrm-dart-resume-default-envs-');
      final String sessionPath = '${temp.path}/session.json';

      SessionStore.saveSession(
        sessionPath,
        <String, dynamic>{
          'source_provider': 'github',
          'source_url': 'https://github.com/acme/src',
          'target_provider': 'gitlab',
          'target_url': 'https://gitlab.com/acme/dst',
          'session_token_mode': 'env',
        },
      );

      final CliRequest request = CliRequestParser.parseCliRequest(
        <String>[
          commandResume,
          '--session-file',
          sessionPath,
        ],
        env: <String, String>{},
      );

      final RuntimeOptions options = request.options!;
      expect(options.sessionSourceTokenEnv, defaultSourceTokenEnv);
      expect(options.sessionTargetTokenEnv, defaultTargetTokenEnv);
      expect(options.sourceToken, isEmpty);
      expect(options.targetToken, isEmpty);
    });

    test('parseCliRequest resume reads tokens from env vars declared in session context', () {
      final Directory temp = createTempDir('gfrm-dart-resume-session-env-context-');
      final String sessionPath = '${temp.path}/session.json';

      SessionStore.saveSession(
        sessionPath,
        <String, dynamic>{
          'source_provider': 'github',
          'source_url': 'https://github.com/acme/src',
          'target_provider': 'gitlab',
          'target_url': 'https://gitlab.com/acme/dst',
          'source_token_env': 'SESSION_SOURCE_TOKEN',
          'target_token_env': 'SESSION_TARGET_TOKEN',
          'session_token_mode': 'env',
        },
      );

      final CliRequest request = CliRequestParser.parseCliRequest(
        <String>[
          commandResume,
          '--session-file',
          sessionPath,
        ],
        env: <String, String>{
          'SESSION_SOURCE_TOKEN': 'source-from-session-env',
          'SESSION_TARGET_TOKEN': 'target-from-session-env',
        },
      );

      final RuntimeOptions options = request.options!;
      expect(options.sourceToken, 'source-from-session-env');
      expect(options.targetToken, 'target-from-session-env');
      expect(options.sessionSourceTokenEnv, 'SESSION_SOURCE_TOKEN');
      expect(options.sessionTargetTokenEnv, 'SESSION_TARGET_TOKEN');
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

    test('parseCliRequest resume accepts session env names from CLI when session omits them', () {
      final Directory temp = createTempDir('gfrm-dart-resume-cli-env-context-');
      final String sessionPath = '${temp.path}/session.json';

      SessionStore.saveSession(
        sessionPath,
        <String, dynamic>{
          'source_provider': 'github',
          'source_url': 'https://github.com/acme/src',
          'target_provider': 'gitlab',
          'target_url': 'https://gitlab.com/acme/dst',
          'session_token_mode': 'env',
        },
      );

      final CliRequest request = CliRequestParser.parseCliRequest(
        <String>[
          commandResume,
          '--session-file',
          sessionPath,
          '--session-source-token-env',
          'CLI_SOURCE_TOKEN',
          '--session-target-token-env',
          'CLI_TARGET_TOKEN',
        ],
        env: <String, String>{
          'CLI_SOURCE_TOKEN': 'source-from-cli-env',
          'CLI_TARGET_TOKEN': 'target-from-cli-env',
        },
      );

      final RuntimeOptions options = request.options!;
      expect(options.sourceToken, 'source-from-cli-env');
      expect(options.targetToken, 'target-from-cli-env');
      expect(options.sessionSourceTokenEnv, 'CLI_SOURCE_TOKEN');
      expect(options.sessionTargetTokenEnv, 'CLI_TARGET_TOKEN');
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

    test('parseCliRequest resume uses default session path in current directory when omitted', () {
      final Directory temp = createTempDir('gfrm-dart-resume-default-session-path-');
      final Directory sessionsDir = Directory('${temp.path}/sessions')..createSync(recursive: true);
      final String sessionPath = '${sessionsDir.path}/last-session.json';

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

      final CliRequest request = IOOverrides.runZoned<CliRequest>(
        () => CliRequestParser.parseCliRequest(<String>[commandResume]),
        getCurrentDirectory: () => temp,
      );

      expect(request.options!.sessionFile, sessionPath);
      expect(request.options!.sourceToken, 'source-token');
      expect(request.options!.targetToken, 'target-token');
    });

    test('parseCliRequest resume lets CLI overrides replace session defaults', () {
      final Directory temp = createTempDir('gfrm-dart-resume-overrides-');
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
          'download_workers': 5,
          'release_workers': 2,
          'skip_tag_migration': false,
        },
      );

      final CliRequest request = CliRequestParser.parseCliRequest(<String>[
        commandResume,
        '--session-file',
        sessionPath,
        '--download-workers',
        '7',
        '--release-workers',
        '3',
        '--from-tag',
        'v3.0.0',
        '--to-tag',
        'v4.0.0',
        '--skip-tags',
      ]);

      final RuntimeOptions options = request.options!;
      expect(options.downloadWorkers, 7);
      expect(options.releaseWorkers, 3);
      expect(options.fromTag, 'v3.0.0');
      expect(options.toTag, 'v4.0.0');
      expect(options.skipTagMigration, isTrue);
    });

    test('parseCliRequest resume prefers CLI settings profile over session profile', () {
      final Directory temp = createTempDir('gfrm-dart-resume-settings-profile-override-');
      final String sessionPath = '${temp.path}/session.json';
      final String settingsPath = '${temp.path}/.gfrm/settings.yaml';

      SessionStore.saveSession(
        sessionPath,
        <String, dynamic>{
          'source_provider': 'github',
          'source_url': 'https://github.com/acme/src',
          'target_provider': 'gitlab',
          'target_url': 'https://gitlab.com/acme/dst',
          'session_token_mode': 'env',
          'settings_profile': 'default',
        },
      );
      SettingsManager.writeSettingsFile(
        settingsPath,
        <String, dynamic>{
          'profiles': <String, dynamic>{
            'default': <String, dynamic>{
              'providers': <String, dynamic>{
                'github': <String, dynamic>{'token_plain': 'source-default'},
                'gitlab': <String, dynamic>{'token_plain': 'target-default'},
              },
            },
            'work': <String, dynamic>{
              'providers': <String, dynamic>{
                'github': <String, dynamic>{'token_plain': 'source-work'},
                'gitlab': <String, dynamic>{'token_plain': 'target-work'},
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
          '--settings-profile',
          'work',
        ],
        cwd: temp.path,
        env: <String, String>{},
      );

      final RuntimeOptions options = request.options!;
      expect(options.settingsProfile, 'work');
      expect(options.sourceToken, 'source-work');
      expect(options.targetToken, 'target-work');
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

    test('parseCliRequest builds demo runtime with common flags and aliases', () {
      final CliRequest request = CliRequestParser.parseCliRequest(<String>[
        commandDemo,
        '--source-provider',
        'gh',
        '--source-url',
        'https://github.com/acme/src',
        '--target-provider',
        'gl',
        '--target-url',
        'https://gitlab.com/acme/dst',
        '--skip-tags',
        '--dry-run',
        '--workdir',
        '/tmp/demo-results',
        '--log-file',
        '/tmp/demo-log.jsonl',
        '--checkpoint-file',
        '/tmp/demo-checkpoints.jsonl',
        '--tags-file',
        '/tmp/demo-tags.txt',
        '--no-banner',
        '--quiet',
        '--json',
        '--progress-bar',
      ]);

      final RuntimeOptions options = request.options!;
      expect(options.commandName, commandDemo);
      expect(options.sourceProvider, 'github');
      expect(options.targetProvider, 'gitlab');
      expect(options.skipTagMigration, isTrue);
      expect(options.dryRun, isTrue);
      expect(options.workdir, '/tmp/demo-results');
      expect(options.logFile, '/tmp/demo-log.jsonl');
      expect(options.checkpointFile, '/tmp/demo-checkpoints.jsonl');
      expect(options.tagsFile, '/tmp/demo-tags.txt');
      expect(options.noBanner, isTrue);
      expect(options.quiet, isTrue);
      expect(options.jsonOutput, isTrue);
      expect(options.progressBar, isTrue);
    });

    test('parseCliRequest rejects invalid demo release count', () {
      expect(
        () => CliRequestParser.parseCliRequest(<String>[
          commandDemo,
          '--source-provider',
          'github',
          '--target-provider',
          'gitlab',
          '--demo-releases',
          '0',
        ]),
        throwsArgumentError,
      );
    });

    test('parseCliRequest rejects invalid demo sleep seconds', () {
      expect(
        () => CliRequestParser.parseCliRequest(<String>[
          commandDemo,
          '--source-provider',
          'github',
          '--target-provider',
          'gitlab',
          '--demo-sleep-seconds',
          '-1',
        ]),
        throwsArgumentError,
      );
    });
  });
}
