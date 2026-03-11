import 'dart:io';

import 'package:gfrm_dart/src/core/adapters/provider_adapter.dart';
import 'package:gfrm_dart/src/core/exceptions/migration_phase_error.dart';
import 'package:gfrm_dart/src/core/types/canonical_release.dart';
import 'package:gfrm_dart/src/migrations/engine.dart';
import 'package:gfrm_dart/src/models/runtime_options.dart';
import 'package:gfrm_dart/src/providers/registry.dart';
import '../../support/logging.dart';
import '../../support/runtime_options_fixture.dart';
import '../../support/temp_dir.dart';
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

void main() {
  group('engine', () {
    test('creates parent directory for custom --log-file before truncating file', () async {
      final Directory temp = createTempDir('gfrm-engine-log-path-');

      final String workdirPath = '${temp.path}/results';
      final String logPath = '${temp.path}/logs/nested/migration-log.jsonl';
      final RuntimeOptions options = buildRuntimeOptions(workdir: workdirPath, logFile: logPath);

      final _EmptySourceAdapter source = _EmptySourceAdapter();
      final _TargetAdapter target = _TargetAdapter();
      final ProviderRegistry registry = ProviderRegistry(<String, ProviderAdapter>{
        'github': source,
        'gitlab': target,
      });
      final MigrationEngine engine = MigrationEngine(
        registry: registry,
        logger: createSilentLogger(),
      );

      await expectLater(
        engine.run(
          options,
          source.parseUrl(options.sourceUrl),
          target.parseUrl(options.targetUrl),
        ),
        throwsA(isA<MigrationPhaseError>()),
      );

      expect(File(logPath).parent.existsSync(), isTrue);
      expect(File(logPath).existsSync(), isTrue);
    });
  });
}
