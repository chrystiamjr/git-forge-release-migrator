import 'canonical_link.dart';
import 'canonical_source.dart';

class CanonicalAssets {
  CanonicalAssets({
    required this.links,
    required this.sources,
  });

  final List<CanonicalLink> links;
  final List<CanonicalSource> sources;

  factory CanonicalAssets.empty() {
    return CanonicalAssets(
      links: const <CanonicalLink>[],
      sources: const <CanonicalSource>[],
    );
  }

  factory CanonicalAssets.fromMap(Map<String, dynamic> payload) {
    final dynamic linksRaw = payload['links'];
    final List<CanonicalLink> links = linksRaw is List
        ? linksRaw
            .whereType<Map<String, dynamic>>()
            .map((Map<String, dynamic> item) => CanonicalLink.fromMap(Map<String, dynamic>.from(item)))
            .toList(growable: false)
        : const <CanonicalLink>[];

    final dynamic sourcesRaw = payload['sources'];
    final List<CanonicalSource> sources = sourcesRaw is List
        ? sourcesRaw
            .whereType<Map<String, dynamic>>()
            .map((Map<String, dynamic> item) => CanonicalSource.fromMap(Map<String, dynamic>.from(item)))
            .toList(growable: false)
        : const <CanonicalSource>[];

    return CanonicalAssets(
      links: links,
      sources: sources,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'links': links.map((CanonicalLink item) => item.toMap()).toList(growable: false),
      'sources': sources.map((CanonicalSource item) => item.toMap()).toList(growable: false),
    };
  }
}
