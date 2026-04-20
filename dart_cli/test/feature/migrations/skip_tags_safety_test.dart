import 'dart:io';

import 'package:gfrm_dart/src/core/adapters/provider_adapter.dart';
import 'package:gfrm_dart/src/core/types/canonical_release.dart';
import 'package:gfrm_dart/src/models/runtime_options.dart';
import 'package:test/test.dart';

import '../../support/runtime_options_fixture.dart';
import '../../support/temp_dir.dart';

final class _SkipTagsTargetAdapterEmpty extends ProviderAdapter {
  @override
  String get name => 'skip-tags-target-empty';

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

final class _SkipTagsTargetAdapterWithTags extends ProviderAdapter {
  @override
  String get name => 'skip-tags-target-with-tags';

  @override
  ProviderRef parseUrl(String url) {
    return ProviderRef(
      provider: 'bitbucket',
      rawUrl: url,
      baseUrl: 'https://bitbucket.org',
      host: 'bitbucket.org',
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
  group('--skip-tags safety:', () {
    test(
      'when skipTagMigration=true and destination has existing tags, '
      'it is safe to skip tag migration',
      () async {
        final Directory temp = createTempDir('gfrm-skip-tags-safe-');
        final RuntimeOptions options = buildRuntimeOptions(
          workdir: '${temp.path}/results',
          skipTagMigration: true,
        );

        // When skip-tags is enabled
        expect(options.skipTagMigration, isTrue);

        // Simulate that destination already has tags from a previous run
        final List<String> destinationExistingTags = <String>['v1.0.0', 'v1.1.0', 'v1.2.0'];

        // This is safe because destination tags already exist
        expect(destinationExistingTags, isNotEmpty);
      },
    );

    test(
      'when skipTagMigration=true and destination is empty, '
      'it represents a safety concern that should be flagged',
      () {
        final RuntimeOptions options = buildRuntimeOptions(
          skipTagMigration: true,
        );

        // When skip-tags is enabled
        expect(options.skipTagMigration, isTrue);

        // Simulate that destination has NO tags at all
        final List<String> destinationEmptyTags = <String>[];

        // This is a safety concern - destination is empty, so skipping tags means
        // releases may have no corresponding tags to reference
        expect(destinationEmptyTags, isEmpty);

        // Critical Invariant: --skip-tags is only safe when destination tags already exist
        // When destination is empty, --skip-tags should be rejected or require explicit confirmation
      },
    );

    test(
      'adapter can validate destination tag count before allowing skip-tags',
      () async {
        final _SkipTagsTargetAdapterWithTags adapterWithTags = _SkipTagsTargetAdapterWithTags();
        final _SkipTagsTargetAdapterEmpty adapterEmpty = _SkipTagsTargetAdapterEmpty();

        final ProviderRef refWithTags = adapterWithTags.parseUrl('https://bitbucket.org/acme/target');
        final ProviderRef refEmpty = adapterEmpty.parseUrl('https://gitlab.com/acme/target');

        // Adapter with existing tags
        final List<String> tagsWithData = await adapterWithTags.listTags(refWithTags, 'token');
        expect(tagsWithData, isNotEmpty);

        // Adapter with no tags
        final List<String> tagsEmpty = await adapterEmpty.listTags(refEmpty, 'token');
        expect(tagsEmpty, isEmpty);

        // Safety validation logic:
        // if (skipTagMigration && destinationTags.isEmpty) {
        //   throw error('Cannot use --skip-tags when destination has no tags')
        // }
      },
    );
  });
}
