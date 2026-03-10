import 'dart:io';

import 'package:gfrm_dart/src/core/adapters/provider_adapter.dart';
import 'package:gfrm_dart/src/core/logging.dart';
import 'package:gfrm_dart/src/core/types/canonical_release.dart';
import 'package:gfrm_dart/src/migrations/engine.dart';
import 'package:gfrm_dart/src/models/runtime_options.dart';
import 'package:gfrm_dart/src/providers/registry.dart';
import 'package:test/test.dart';

final class _EmptySourceAdapter extends ProviderAdapter {
  @override
  String get name => 'empty-source';

  @override
  ProviderRef parseUrl(String url) {
    return ProviderRef(
      provider: 'github',
      rawUrl: url,
      baseUrl: 'https://github.com',
      host: 'github.com',
      resource: 'acme/source',
    );
  }

  @override
  CanonicalRelease toCanonicalRelease(Map<String, dynamic> payload) {
    return CanonicalRelease.fromMap(payload);
  }

  @override
  Future<List<Map<String, dynamic>>> listReleases(ProviderRef ref, String token) async {
    return <Map<String, dynamic>>[];
  }
}

final class _TargetAdapter extends ProviderAdapter {
  @override
  String get name => 'target';

  @override
  ProviderRef parseUrl(String url) {
    return ProviderRef(
      provider: 'gitlab',
      rawUrl: url,
      baseUrl: 'https://gitlab.com',
      host: 'gitlab.com',
      resource: 'acme/target',
    );
  }

  @override
  CanonicalRelease toCanonicalRelease(Map<String, dynamic> payload) {
    return CanonicalRelease.fromMap(payload);
  }
}

RuntimeOptions _buildOptions(String workdirPath, String logPath) {
  return RuntimeOptions(
    commandName: commandMigrate,
    sourceProvider: 'github',
    sourceUrl: 'https://github.com/acme/source',
    sourceToken: 'src-token',
    targetProvider: 'gitlab',
    targetUrl: 'https://gitlab.com/acme/target',
    targetToken: 'dst-token',
    migrationOrder: 'github-to-gitlab',
    skipTagMigration: false,
    fromTag: '',
    toTag: '',
    dryRun: false,
    nonInteractive: true,
    workdir: workdirPath,
    logFile: logPath,
    loadSession: false,
    saveSession: false,
    resumeSession: false,
    sessionFile: '',
    sessionTokenMode: 'env',
    sessionSourceTokenEnv: defaultSourceTokenEnv,
    sessionTargetTokenEnv: defaultTargetTokenEnv,
    settingsProfile: '',
    downloadWorkers: 4,
    releaseWorkers: 1,
    checkpointFile: '',
    tagsFile: '',
    noBanner: true,
    quiet: true,
    jsonOutput: false,
    progressBar: false,
    demoMode: false,
    demoReleases: 5,
    demoSleepSeconds: 1.0,
  );
}

void main() {
  group('engine', () {
    test('creates parent directory for custom --log-file before truncating file', () async {
      final Directory temp = Directory.systemTemp.createTempSync('gfrm-engine-log-path-');
      addTearDown(() => temp.deleteSync(recursive: true));

      final String workdirPath = '${temp.path}/results';
      final String logPath = '${temp.path}/logs/nested/migration-log.jsonl';
      final RuntimeOptions options = _buildOptions(workdirPath, logPath);

      final _EmptySourceAdapter source = _EmptySourceAdapter();
      final _TargetAdapter target = _TargetAdapter();
      final ProviderRegistry registry = ProviderRegistry(<String, ProviderAdapter>{
        'github': source,
        'gitlab': target,
      });
      final MigrationEngine engine = MigrationEngine(
        registry: registry,
        logger: ConsoleLogger(quiet: true, jsonOutput: false),
      );

      await expectLater(
        engine.run(
          options,
          source.parseUrl(options.sourceUrl),
          target.parseUrl(options.targetUrl),
        ),
        throwsA(isA<StateError>()),
      );

      expect(File(logPath).parent.existsSync(), isTrue);
      expect(File(logPath).existsSync(), isTrue);
    });
  });
}
