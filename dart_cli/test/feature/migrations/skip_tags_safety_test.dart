import 'dart:io';

import 'package:gfrm_dart/src/application/preflight_check.dart';
import 'package:gfrm_dart/src/application/preflight_service.dart';
import 'package:gfrm_dart/src/core/adapters/provider_adapter.dart';
import 'package:gfrm_dart/src/core/types/canonical_release.dart';
import 'package:gfrm_dart/src/models/migration_context.dart';
import 'package:test/test.dart';

import '../../support/migration_context_fixture.dart';
import '../../support/temp_dir.dart';

final class _SourceAdapter extends ProviderAdapter {
  @override
  String get name => 'stub-source';

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
  Future<List<String>> listTags(ProviderRef ref, String token) async => <String>[];

  @override
  Future<List<Map<String, dynamic>>> listReleases(ProviderRef ref, String token) async {
    return <Map<String, dynamic>>[];
  }
}

final class _TargetAdapterEmpty extends ProviderAdapter {
  @override
  String get name => 'stub-target-empty';

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

  // Destination has NO tags
  @override
  Future<List<String>> listTags(ProviderRef ref, String token) async => <String>[];

  @override
  Future<List<Map<String, dynamic>>> listReleases(ProviderRef ref, String token) async {
    return <Map<String, dynamic>>[];
  }
}

final class _TargetAdapterWithTags extends ProviderAdapter {
  @override
  String get name => 'stub-target-with-tags';

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

  // Destination already has 3 tags
  @override
  Future<List<String>> listTags(ProviderRef ref, String token) async {
    return <String>['v1.0.0', 'v1.1.0', 'v1.2.0'];
  }

  @override
  Future<List<Map<String, dynamic>>> listReleases(ProviderRef ref, String token) async {
    return <Map<String, dynamic>>[];
  }
}

void main() {
  group('PreflightService.buildSkipTagsSafetyCheck():', () {
    test(
      'when skipTagMigration=false, check returns null (no validation needed)',
      () async {
        final Directory temp = createTempDir('gfrm-skip-tags-safe-');
        final _SourceAdapter source = _SourceAdapter();
        final _TargetAdapterWithTags target = _TargetAdapterWithTags();

        final MigrationContext ctx = buildMigrationContext(
          temp,
          source,
          target,
          skipTagMigration: false,
          targetTags: const {'v1.0.0', 'v1.1.0', 'v1.2.0'},
        );

        // When skip-tags is NOT enabled
        expect(ctx.options.skipTagMigration, isFalse);

        final PreflightService service = PreflightService();
        final PreflightCheck? check = service.buildSkipTagsSafetyCheck(ctx);

        // Check should be null - no safety concern
        expect(check, isNull);
      },
    );

    test(
      'when skipTagMigration=true and target is empty, check status=error with skip-tags-unsafe code',
      () async {
        final Directory temp = createTempDir('gfrm-skip-tags-unsafe-');
        final _SourceAdapter source = _SourceAdapter();
        final _TargetAdapterEmpty target = _TargetAdapterEmpty();

        final MigrationContext ctx = buildMigrationContext(
          temp,
          source,
          target,
          skipTagMigration: true,
          targetTags: const <String>{},
        );

        // When skip-tags is enabled AND target has no tags
        expect(ctx.options.skipTagMigration, isTrue);
        expect(ctx.targetTags, isEmpty);

        final PreflightService service = PreflightService();
        final PreflightCheck? check = service.buildSkipTagsSafetyCheck(ctx);

        // Check must be present with error status
        expect(check, isNotNull);
        expect(check!.status, equals(PreflightCheckStatus.error));
        expect(check.code, equals('skip-tags-unsafe'));
        expect(check.message, contains('not safe'));
        expect(check.hint, isNotNull);
        expect(check.hint, contains('target repository must already contain all tags'));
      },
    );

    test(
      'when skipTagMigration=true and target has existing tags, check returns null',
      () async {
        final Directory temp = createTempDir('gfrm-skip-tags-safe-with-tags-');
        final _SourceAdapter source = _SourceAdapter();
        final _TargetAdapterWithTags target = _TargetAdapterWithTags();

        final MigrationContext ctx = buildMigrationContext(
          temp,
          source,
          target,
          skipTagMigration: true,
          targetTags: const {'v1.0.0', 'v1.1.0', 'v1.2.0'},
        );

        // When skip-tags is enabled AND target already has tags
        expect(ctx.options.skipTagMigration, isTrue);
        expect(ctx.targetTags, isNotEmpty);

        final PreflightService service = PreflightService();
        final PreflightCheck? check = service.buildSkipTagsSafetyCheck(ctx);

        // Check should be null - destination tags already exist, it is safe
        expect(check, isNull);
      },
    );
  });
}
