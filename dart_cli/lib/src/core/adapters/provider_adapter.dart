import '../checkpoint.dart';
import '../types/canonical_release.dart';
import '../types/phase.dart';

class ProviderRef {
  ProviderRef({
    required this.provider,
    required this.rawUrl,
    required this.baseUrl,
    required this.host,
    required this.resource,
    Map<String, String>? metadata,
  }) : metadata = metadata ?? <String, String>{};

  final String provider;
  final String rawUrl;
  final String baseUrl;
  final String host;
  final String resource;
  final Map<String, String> metadata;
}

abstract class ProviderAdapter {
  String get name;

  ProviderRef parseUrl(String url);

  bool validateUrl(String url) {
    try {
      parseUrl(url);
      return true;
    } catch (_) {
      return false;
    }
  }

  CanonicalRelease toCanonicalRelease(Map<String, dynamic> payload);

  Future<List<Map<String, dynamic>>> listReleases(ProviderRef ref, String token) async {
    throw UnimplementedError('listReleases not implemented for $name');
  }

  Future<List<String>> listTags(ProviderRef ref, String token) async {
    throw UnimplementedError('listTags not implemented for $name');
  }

  Future<bool> tagExists(ProviderRef ref, String token, String tag) async {
    throw UnimplementedError('tagExists not implemented for $name');
  }

  Future<String> tagCommitSha(ProviderRef ref, String token, String tag) async {
    throw UnimplementedError('tagCommitSha not implemented for $name');
  }

  Future<bool> commitExists(ProviderRef ref, String token, String sha) async {
    return true;
  }

  Future<void> createTag(ProviderRef ref, String token, String tag, String sha, {String message = ''}) async {
    throw UnimplementedError('createTag not implemented for $name');
  }

  Future<bool> releaseExists(ProviderRef ref, String token, String tag) async {
    throw UnimplementedError('releaseExists not implemented for $name');
  }

  Future<Map<String, dynamic>?> releaseByTag(ProviderRef ref, String token, String tag) async {
    throw UnimplementedError('releaseByTag not implemented for $name');
  }

  Future<void> createOrUpdateRelease(
    ProviderRef ref,
    String token,
    String tag,
    String name,
    String description,
    List<Map<String, dynamic>> links,
  ) async {
    throw UnimplementedError('createOrUpdateRelease not implemented for $name');
  }

  Future<String> uploadFile(ProviderRef ref, String token, String filepath) async {
    throw UnimplementedError('uploadFile not implemented for $name');
  }

  Future<bool> downloadWithAuth(String token, String url, String destination) async {
    throw UnimplementedError('downloadWithAuth not implemented for $name');
  }

  String buildTagUrl(ProviderRef ref, String tag) {
    throw UnimplementedError('buildTagUrl not implemented for $name');
  }

  Future<Set<String>> listTargetReleaseTags(ProviderRef ref, String token, Set<String> fallbackTags) async {
    return fallbackTags.toSet();
  }

  Future<void> createTagForMigration(
    ProviderRef ref,
    String token,
    String tag,
    String sha,
    CanonicalRelease canonical,
  ) async {
    await createTag(ref, token, tag, sha);
  }

  Future<String> resolveCommitShaForMigration(
    ProviderRef ref,
    String token,
    String tag,
    CanonicalRelease canonical,
  ) async {
    if (canonical.commitSha.isNotEmpty) {
      return canonical.commitSha;
    }

    return tagCommitSha(ref, token, tag);
  }

  Future<bool> isReleaseAlreadyProcessed(
    ProviderRef ref,
    String token,
    String tag,
    String checkpointStatus,
    Set<String> targetReleaseTags,
  ) async {
    if (!CheckpointStore.isTerminalReleaseStatus(checkpointStatus)) {
      return false;
    }

    if (targetReleaseTags.contains(tag)) {
      return true;
    }

    return releaseExists(ref, token, tag);
  }

  Future<ExistingReleaseInfo> existingReleaseInfo(
    ProviderRef ref,
    String token,
    String tag,
    int expectedLinkAssets,
  ) async {
    final bool exists = await releaseExists(ref, token, tag);
    if (!exists) {
      return const ExistingReleaseInfo(exists: false, shouldRetry: false, reason: '');
    }

    return const ExistingReleaseInfo(exists: true, shouldRetry: false, reason: '');
  }

  Future<String> publishRelease(PublishReleaseInput input) async {
    throw UnimplementedError(
      'publishRelease must be implemented by the concrete provider adapter.',
    );
  }

  Future<bool> downloadCanonicalLink(DownloadLinkInput input) async {
    final String resolved = input.link.directUrl.isNotEmpty ? input.link.directUrl : input.link.url;
    if (resolved.isEmpty) {
      return false;
    }

    return downloadWithAuth(input.token, resolved, input.outputPath);
  }

  Future<bool> downloadCanonicalSource(DownloadSourceInput input) async {
    if (input.source.url.isEmpty) {
      return false;
    }

    return downloadWithAuth(input.token, input.source.url, input.outputPath);
  }

  bool supportsSourceFallbackTagNotes() {
    return false;
  }

  bool requiresLegacySourceNotes(CanonicalRelease canonical) {
    return canonical.providerMetadata['legacy_no_manifest'] == true;
  }
}
