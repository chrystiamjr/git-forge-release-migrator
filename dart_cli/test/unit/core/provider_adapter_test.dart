import 'dart:io';

import 'package:gfrm_dart/src/core/adapters/provider_adapter.dart';
import 'package:gfrm_dart/src/core/types/canonical_link.dart';
import 'package:gfrm_dart/src/core/types/canonical_release.dart';
import 'package:gfrm_dart/src/core/types/canonical_source.dart';
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

final class _ThrowingAdapter extends ProviderAdapter {
  @override
  String get name => 'throwing';

  @override
  ProviderRef parseUrl(String url) {
    throw ArgumentError('invalid URL: $url');
  }

  @override
  CanonicalRelease toCanonicalRelease(Map<String, dynamic> payload) {
    return CanonicalRelease.fromMap(payload);
  }
}

CanonicalRelease _canonical({String commitSha = '', Map<String, dynamic>? metadata}) {
  return CanonicalRelease.fromMap(<String, dynamic>{
    'tag_name': 'v1.0.0',
    'name': 'v1.0.0',
    'description_markdown': '',
    'commit_sha': commitSha,
    'assets': <String, dynamic>{'links': <dynamic>[], 'sources': <dynamic>[]},
    'provider_metadata': metadata ?? <String, dynamic>{},
  });
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

    test('validateUrl returns true for a parseable URL', () {
      expect(_NoopAdapter().validateUrl('https://example.com/project'), isTrue);
    });

    test('validateUrl returns false when parseUrl throws', () {
      expect(_ThrowingAdapter().validateUrl('bad-url'), isFalse);
    });

    test('supportsSourceFallbackTagNotes returns false by default', () {
      expect(_NoopAdapter().supportsSourceFallbackTagNotes(), isFalse);
    });

    test('requiresLegacySourceNotes returns true when legacy_no_manifest is true', () {
      final _NoopAdapter adapter = _NoopAdapter();
      expect(adapter.requiresLegacySourceNotes(_canonical(metadata: <String, dynamic>{'legacy_no_manifest': true})),
          isTrue);
      expect(adapter.requiresLegacySourceNotes(_canonical(metadata: <String, dynamic>{'legacy_no_manifest': false})),
          isFalse);
      expect(adapter.requiresLegacySourceNotes(_canonical()), isFalse);
    });

    test('resolveCommitShaForMigration returns canonical sha when non-empty', () async {
      final _NoopAdapter adapter = _NoopAdapter();
      final ProviderRef ref = adapter.parseUrl('https://example.com/project');

      final String sha =
          await adapter.resolveCommitShaForMigration(ref, 'token', 'v1.0.0', _canonical(commitSha: 'abc123'));
      expect(sha, 'abc123');
    });

    test('downloadCanonicalLink returns false when both url and directUrl are empty', () async {
      final _NoopAdapter adapter = _NoopAdapter();
      final DownloadLinkInput input = DownloadLinkInput(
        providerRef: adapter.parseUrl('https://example.com/project'),
        token: 'token',
        tag: 'v1.0.0',
        link: CanonicalLink(name: 'file.zip', url: '', directUrl: '', type: 'other'),
        outputPath: '/tmp/file.zip',
      );

      expect(await adapter.downloadCanonicalLink(input), isFalse);
    });

    test('downloadCanonicalSource returns false when source url is empty', () async {
      final _NoopAdapter adapter = _NoopAdapter();
      final DownloadSourceInput input = DownloadSourceInput(
        providerRef: adapter.parseUrl('https://example.com/project'),
        token: 'token',
        tag: 'v1.0.0',
        source: CanonicalSource(name: 'src.zip', url: '', format: 'zip'),
        outputPath: '/tmp/src.zip',
      );

      expect(await adapter.downloadCanonicalSource(input), isFalse);
    });

    test('isReleaseAlreadyProcessed returns false when status is not terminal', () async {
      final _NoopAdapter adapter = _NoopAdapter();
      final ProviderRef ref = adapter.parseUrl('https://example.com/project');

      final bool result = await adapter.isReleaseAlreadyProcessed(ref, 'token', 'v1.0.0', 'in_progress', <String>{});
      expect(result, isFalse);
    });

    test('isReleaseAlreadyProcessed returns true when terminal and tag is in targetReleaseTags', () async {
      final _NoopAdapter adapter = _NoopAdapter();
      final ProviderRef ref = adapter.parseUrl('https://example.com/project');

      final bool result = await adapter.isReleaseAlreadyProcessed(
        ref,
        'token',
        'v1.0.0',
        'created',
        <String>{'v1.0.0'},
      );
      expect(result, isTrue);
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

    test('listReleases throws UnimplementedError by default', () async {
      final _NoopAdapter adapter = _NoopAdapter();
      final ProviderRef ref = adapter.parseUrl('https://example.com/project');
      await expectLater(adapter.listReleases(ref, 'token'), throwsUnimplementedError);
    });

    test('listTags throws UnimplementedError by default', () async {
      final _NoopAdapter adapter = _NoopAdapter();
      final ProviderRef ref = adapter.parseUrl('https://example.com/project');
      await expectLater(adapter.listTags(ref, 'token'), throwsUnimplementedError);
    });

    test('tagExists throws UnimplementedError by default', () async {
      final _NoopAdapter adapter = _NoopAdapter();
      final ProviderRef ref = adapter.parseUrl('https://example.com/project');
      await expectLater(adapter.tagExists(ref, 'token', 'v1.0.0'), throwsUnimplementedError);
    });

    test('tagCommitSha throws UnimplementedError by default', () async {
      final _NoopAdapter adapter = _NoopAdapter();
      final ProviderRef ref = adapter.parseUrl('https://example.com/project');
      await expectLater(adapter.tagCommitSha(ref, 'token', 'v1.0.0'), throwsUnimplementedError);
    });

    test('createTag throws UnimplementedError by default', () async {
      final _NoopAdapter adapter = _NoopAdapter();
      final ProviderRef ref = adapter.parseUrl('https://example.com/project');
      await expectLater(adapter.createTag(ref, 'token', 'v1.0.0', 'sha'), throwsUnimplementedError);
    });

    test('releaseExists throws UnimplementedError by default', () async {
      final _NoopAdapter adapter = _NoopAdapter();
      final ProviderRef ref = adapter.parseUrl('https://example.com/project');
      await expectLater(adapter.releaseExists(ref, 'token', 'v1.0.0'), throwsUnimplementedError);
    });

    test('releaseByTag throws UnimplementedError by default', () async {
      final _NoopAdapter adapter = _NoopAdapter();
      final ProviderRef ref = adapter.parseUrl('https://example.com/project');
      await expectLater(adapter.releaseByTag(ref, 'token', 'v1.0.0'), throwsUnimplementedError);
    });

    test('createOrUpdateRelease throws UnimplementedError by default', () async {
      final _NoopAdapter adapter = _NoopAdapter();
      final ProviderRef ref = adapter.parseUrl('https://example.com/project');
      await expectLater(
        adapter.createOrUpdateRelease(ref, 'token', 'v1.0.0', 'v1.0.0', 'notes', <Map<String, dynamic>>[]),
        throwsUnimplementedError,
      );
    });

    test('uploadFile throws UnimplementedError by default', () async {
      final _NoopAdapter adapter = _NoopAdapter();
      final ProviderRef ref = adapter.parseUrl('https://example.com/project');
      await expectLater(adapter.uploadFile(ref, 'token', '/tmp/file.zip'), throwsUnimplementedError);
    });

    test('downloadWithAuth throws UnimplementedError by default', () async {
      final _NoopAdapter adapter = _NoopAdapter();
      await expectLater(
        adapter.downloadWithAuth('token', 'https://example.com/file.zip', '/tmp/file.zip'),
        throwsUnimplementedError,
      );
    });

    test('buildTagUrl throws UnimplementedError by default', () {
      final _NoopAdapter adapter = _NoopAdapter();
      final ProviderRef ref = adapter.parseUrl('https://example.com/project');
      expect(() => adapter.buildTagUrl(ref, 'v1.0.0'), throwsUnimplementedError);
    });

    test('createTagForMigration delegates to createTag which throws by default', () async {
      final _NoopAdapter adapter = _NoopAdapter();
      final ProviderRef ref = adapter.parseUrl('https://example.com/project');
      await expectLater(
        adapter.createTagForMigration(ref, 'token', 'v1.0.0', 'sha', _canonical()),
        throwsUnimplementedError,
      );
    });

    test('resolveCommitShaForMigration calls tagCommitSha when canonical sha is empty', () async {
      final _NoopAdapter adapter = _NoopAdapter();
      final ProviderRef ref = adapter.parseUrl('https://example.com/project');
      await expectLater(
        adapter.resolveCommitShaForMigration(ref, 'token', 'v1.0.0', _canonical(commitSha: '')),
        throwsUnimplementedError,
      );
    });

    test('isReleaseAlreadyProcessed calls releaseExists when terminal and tag not in set', () async {
      final _NoopAdapter adapter = _NoopAdapter();
      final ProviderRef ref = adapter.parseUrl('https://example.com/project');
      await expectLater(
        adapter.isReleaseAlreadyProcessed(ref, 'token', 'v1.0.0', 'created', <String>{}),
        throwsUnimplementedError,
      );
    });
  });
}
