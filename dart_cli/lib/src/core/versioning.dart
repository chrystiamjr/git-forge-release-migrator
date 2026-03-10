final class SemverUtils {
  const SemverUtils._();

  static List<int> _normalize(String tag) {
    String value = tag.trim();
    if (value.startsWith('v')) {
      value = value.substring(1);
    }

    final List<String> parts = value.split('.');
    if (parts.length != 3) {
      throw ArgumentError('Invalid semantic tag: $tag');
    }

    try {
      return <int>[
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      ];
    } on FormatException {
      throw ArgumentError('Invalid semantic tag: $tag');
    }
  }

  static bool versionLe(String left, String right) {
    final List<int> normalizedLeft = _normalize(left);
    final List<int> normalizedRight = _normalize(right);
    for (int index = 0; index < 3; index += 1) {
      if (normalizedLeft[index] < normalizedRight[index]) {
        return true;
      }

      if (normalizedLeft[index] > normalizedRight[index]) {
        return false;
      }
    }

    return true;
  }
}
