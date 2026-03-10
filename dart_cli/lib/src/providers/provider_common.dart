import 'package:path/path.dart' as path_pack;

final class ProviderCommon {
  const ProviderCommon._();

  static String normalizeRepositoryUrl(String url) {
    String clean = url.trim().split('?').first.split('#').first;
    if (clean.endsWith('.git')) {
      clean = clean.substring(0, clean.length - 4);
    }

    return clean;
  }

  static Map<String, dynamic> mapFrom(dynamic payload) {
    if (payload is Map) {
      return Map<String, dynamic>.from(payload);
    }

    return <String, dynamic>{};
  }

  static List<Map<String, dynamic>> mapListFrom(dynamic payload) {
    if (payload is! List) {
      return <Map<String, dynamic>>[];
    }

    final List<Map<String, dynamic>> list = <Map<String, dynamic>>[];
    for (final dynamic item in payload) {
      if (item is Map) {
        list.add(Map<String, dynamic>.from(item));
      }
    }

    return list;
  }

  static String basename(String pathValue) {
    return path_pack.basename(pathValue);
  }
}
