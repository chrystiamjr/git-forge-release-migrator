// ignore_for_file: implementation_imports

import 'package:gfrm_dart/src/core/adapters/provider_adapter.dart';
import 'package:gfrm_dart/src/core/logging.dart';
import 'package:gfrm_dart/src/core/types/canonical_release.dart';
import 'package:gfrm_dart/src/core/types/existing_release_info.dart';
import 'package:gfrm_dart/src/core/types/publish_release_input.dart';
import 'package:gfrm_dart/src/providers/registry.dart';

Map<String, dynamic> buildMinimalReleasePayload(String tag, {String commitSha = 'abc123'}) {
  return <String, dynamic>{
    'tag_name': tag,
    'name': tag,
    'description_markdown': '',
    'commit_sha': commitSha,
    'assets': <String, dynamic>{'links': const <Map<String, dynamic>>[], 'sources': const <Map<String, dynamic>>[]},
  };
}

ConsoleLogger createSilentLogger() {
  return ConsoleLogger(quiet: true, jsonOutput: false);
}

ProviderRegistry buildTestRegistry({List<Map<String, dynamic>> releases = const <Map<String, dynamic>>[]}) {
  return ProviderRegistry(<String, ProviderAdapter>{
    'github': _SourceAdapter(releases: releases),
    'gitlab': _TargetAdapter(),
  });
}

final class _SourceAdapter extends ProviderAdapter {
  _SourceAdapter({required this.releases});

  final List<Map<String, dynamic>> releases;

  @override
  String get name => 'stub-source';

  @override
  ProviderRef parseUrl(String url) {
    if (!url.startsWith('https://github.com/')) {
      throw ArgumentError('Invalid GitHub repository URL: $url');
    }

    return ProviderRef(
      provider: 'github',
      rawUrl: url,
      baseUrl: 'https://github.com',
      host: 'github.com',
      resource: 'acme/source',
    );
  }

  @override
  CanonicalRelease toCanonicalRelease(Map<String, dynamic> payload) => CanonicalRelease.fromMap(payload);

  @override
  Future<List<Map<String, dynamic>>> listReleases(ProviderRef ref, String token) async => releases;

  @override
  Future<String> resolveCommitShaForMigration(
    ProviderRef ref,
    String token,
    String tag,
    CanonicalRelease canonical,
  ) async {
    return canonical.commitSha.isEmpty ? 'abc123' : canonical.commitSha;
  }
}

final class _TargetAdapter extends ProviderAdapter {
  final Set<String> _createdTags = <String>{};

  @override
  String get name => 'stub-target';

  @override
  ProviderRef parseUrl(String url) {
    if (!url.startsWith('https://gitlab.com/')) {
      throw ArgumentError('Invalid GitLab repository URL: $url');
    }

    return ProviderRef(
      provider: 'gitlab',
      rawUrl: url,
      baseUrl: 'https://gitlab.com',
      host: 'gitlab.com',
      resource: 'acme/target',
    );
  }

  @override
  CanonicalRelease toCanonicalRelease(Map<String, dynamic> payload) => CanonicalRelease.fromMap(payload);

  @override
  Future<List<String>> listTags(ProviderRef ref, String token) async => <String>[];

  @override
  Future<bool> tagExists(ProviderRef ref, String token, String tag) async => _createdTags.contains(tag);

  @override
  Future<bool> commitExists(ProviderRef ref, String token, String sha) async => true;

  @override
  Future<void> createTagForMigration(
    ProviderRef ref,
    String token,
    String tag,
    String sha,
    CanonicalRelease canonical,
  ) async {
    _createdTags.add(tag);
  }

  @override
  Future<bool> releaseExists(ProviderRef ref, String token, String tag) async => false;

  @override
  Future<ExistingReleaseInfo> existingReleaseInfo(
    ProviderRef ref,
    String token,
    String tag,
    int expectedLinkAssets,
  ) async {
    return const ExistingReleaseInfo(exists: false, shouldRetry: false, reason: '');
  }

  @override
  Future<String> publishRelease(PublishReleaseInput input) async => 'created';
}
