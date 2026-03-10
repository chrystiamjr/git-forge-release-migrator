import 'dart:io';

import 'package:gfrm_dart/src/core/adapters/provider_adapter.dart';
import 'package:gfrm_dart/src/core/types/canonical_release.dart';
import 'package:gfrm_dart/src/core/types/phase.dart';
import 'package:test/test.dart';

final class _NoopAdapter extends ProviderAdapter {
  @override
  String get name => 'noop';

  @override
  ProviderRef parseUrl(String url) {
    return ProviderRef(
      provider: 'noop',
      rawUrl: url,
      baseUrl: 'https://example.com',
      host: 'example.com',
      resource: 'example/project',
    );
  }

  @override
  CanonicalRelease toCanonicalRelease(Map<String, dynamic> payload) {
    return CanonicalRelease.fromMap(payload);
  }
}

void main() {
  group('provider adapter', () {
    test('listTargetReleaseTags returns a copy of fallback tags by default', () async {
      final _NoopAdapter adapter = _NoopAdapter();
      final ProviderRef ref = adapter.parseUrl('https://example.com/project');
      final Set<String> fallback = <String>{'v1.0.0', 'v2.0.0'};

      final Set<String> tags = await adapter.listTargetReleaseTags(ref, 'token', fallback);
      expect(tags, equals(fallback));

      tags.add('v3.0.0');
      expect(fallback.contains('v3.0.0'), isFalse);
    });

    test('publishRelease throws by default when adapter does not override it', () async {
      final _NoopAdapter adapter = _NoopAdapter();
      final ProviderRef ref = adapter.parseUrl('https://example.com/project');
      final Directory temp = Directory.systemTemp.createTempSync('gfrm-provider-adapter-publish-');
      addTearDown(() => temp.deleteSync(recursive: true));

      final File notes = File('${temp.path}/notes.md')..writeAsStringSync('# v1.0.0\n\nnotes');
      final PublishReleaseInput input = PublishReleaseInput(
        providerRef: ref,
        token: 'token',
        tag: 'v1.0.0',
        releaseName: 'v1.0.0',
        notesFile: notes,
        downloadedFiles: const <String>[],
        expectedAssets: 0,
        existingInfo: const ExistingReleaseInfo(exists: false, shouldRetry: false, reason: ''),
      );

      await expectLater(adapter.publishRelease(input), throwsUnimplementedError);
    });
  });
}
