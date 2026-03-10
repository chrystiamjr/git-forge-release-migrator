class CanonicalSource {
  CanonicalSource({
    required this.name,
    required this.url,
    required this.format,
  });

  final String name;
  final String url;
  final String format;

  factory CanonicalSource.fromMap(Map<String, dynamic> payload) {
    return CanonicalSource(
      name: (payload['name'] ?? '').toString(),
      url: (payload['url'] ?? '').toString(),
      format: (payload['format'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'name': name,
      'url': url,
      'format': format,
    };
  }
}
