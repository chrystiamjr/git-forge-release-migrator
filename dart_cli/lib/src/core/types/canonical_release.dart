import 'canonical_assets.dart';

class CanonicalRelease {
  CanonicalRelease({
    required this.tagName,
    required this.name,
    required this.descriptionMarkdown,
    required this.commitSha,
    required this.assets,
    required this.providerMetadata,
  });

  final String tagName;
  final String name;
  final String descriptionMarkdown;
  final String commitSha;
  final CanonicalAssets assets;
  final Map<String, dynamic> providerMetadata;

  factory CanonicalRelease.fromMap(Map<String, dynamic> payload) {
    final dynamic assetsRaw = payload['assets'];
    final Map<String, dynamic> assetsMap =
        assetsRaw is Map ? Map<String, dynamic>.from(assetsRaw) : <String, dynamic>{};

    final dynamic metadataRaw = payload['provider_metadata'];
    final Map<String, dynamic> metadata =
        metadataRaw is Map ? Map<String, dynamic>.from(metadataRaw) : <String, dynamic>{};

    final String tagName = (payload['tag_name'] ?? '').toString();
    final String releaseNameRaw = (payload['name'] ?? '').toString();

    return CanonicalRelease(
      tagName: tagName,
      name: releaseNameRaw.isEmpty ? tagName : releaseNameRaw,
      descriptionMarkdown: (payload['description_markdown'] ?? '').toString(),
      commitSha: (payload['commit_sha'] ?? '').toString(),
      assets: CanonicalAssets.fromMap(assetsMap),
      providerMetadata: metadata,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'tag_name': tagName,
      'name': name,
      'description_markdown': descriptionMarkdown,
      'commit_sha': commitSha,
      'assets': assets.toMap(),
      'provider_metadata': providerMetadata,
    };
  }
}
