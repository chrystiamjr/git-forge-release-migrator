List<int> _normalize(String tag) {
  String value = tag.trim();
  if (value.startsWith('v')) {
    value = value.substring(1);
  }

  final List<String> parts = value.split('.');
  if (parts.length != 3) {
    throw ArgumentError('Invalid semantic tag: $tag');
  }

  return <int>[
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  ];
}

bool versionLe(String left, String right) {
  final List<int> l = _normalize(left);
  final List<int> r = _normalize(right);
  for (int i = 0; i < 3; i += 1) {
    if (l[i] < r[i]) {
      return true;
    }

    if (l[i] > r[i]) {
      return false;
    }
  }

  return true;
}
