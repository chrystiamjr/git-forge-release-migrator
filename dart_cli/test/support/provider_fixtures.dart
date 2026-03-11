import 'package:gfrm_dart/src/core/types/canonical_release.dart';

Map<String, dynamic> buildMinimalReleasePayload(
  String tag, {
  String name = '',
  String descriptionMarkdown = '',
  String commitSha = 'abc123',
  List<Map<String, dynamic>> links = const <Map<String, dynamic>>[],
  List<Map<String, dynamic>> sources = const <Map<String, dynamic>>[],
  Map<String, dynamic> providerMetadata = const <String, dynamic>{},
}) {
  return <String, dynamic>{
    'tag_name': tag,
    'name': name.isEmpty ? tag : name,
    'description_markdown': descriptionMarkdown,
    'commit_sha': commitSha,
    'assets': <String, dynamic>{
      'links': links,
      'sources': sources,
    },
    if (providerMetadata.isNotEmpty) 'provider_metadata': providerMetadata,
  };
}

CanonicalRelease buildCanonicalRelease(
  String tag, {
  String name = '',
  String descriptionMarkdown = '',
  String commitSha = 'abc123',
  List<Map<String, dynamic>> links = const <Map<String, dynamic>>[],
  List<Map<String, dynamic>> sources = const <Map<String, dynamic>>[],
  Map<String, dynamic> providerMetadata = const <String, dynamic>{},
}) {
  return CanonicalRelease.fromMap(
    buildMinimalReleasePayload(
      tag,
      name: name,
      descriptionMarkdown: descriptionMarkdown,
      commitSha: commitSha,
      links: links,
      sources: sources,
      providerMetadata: providerMetadata,
    ),
  );
}

Map<String, dynamic> buildLinkAsset({
  required String name,
  required String url,
  String directUrl = '',
  String type = 'other',
}) {
  return <String, dynamic>{
    'name': name,
    'url': url,
    'direct_url': directUrl,
    'type': type,
  };
}

Map<String, dynamic> buildSourceAsset({
  required String name,
  required String url,
  required String format,
}) {
  return <String, dynamic>{
    'name': name,
    'url': url,
    'format': format,
  };
}
