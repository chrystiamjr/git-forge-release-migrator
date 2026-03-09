class CanonicalLink {
  CanonicalLink({
    required this.name,
    required this.url,
    required this.directUrl,
    required this.type,
  });

  final String name;
  final String url;
  final String directUrl;
  final String type;

  factory CanonicalLink.fromMap(Map<String, dynamic> payload) {
    return CanonicalLink(
      name: (payload['name'] ?? '').toString(),
      url: (payload['url'] ?? '').toString(),
      directUrl: (payload['direct_url'] ?? '').toString(),
      type: (payload['type'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'name': name,
      'url': url,
      'direct_url': directUrl,
      'type': type,
    };
  }
}
