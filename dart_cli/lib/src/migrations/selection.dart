import 'dart:io';

import '../core/versioning.dart';

final RegExp semverTagPattern = RegExp(r'^v(\d+)\.(\d+)\.(\d+)$');

String capitalizeProvider(String provider) {
  if (provider.isEmpty) {
    return provider;
  }

  return provider[0].toUpperCase() + provider.substring(1);
}

int semverCompare(String a, String b) {
  final RegExpMatch? ma = semverTagPattern.firstMatch(a);
  final RegExpMatch? mb = semverTagPattern.firstMatch(b);
  if (ma == null && mb == null) {
    return a.compareTo(b);
  }

  if (ma == null) {
    return 1;
  }

  if (mb == null) {
    return -1;
  }

  for (int index = 1; index <= 3; index += 1) {
    final int ai = int.parse(ma.group(index)!);
    final int bi = int.parse(mb.group(index)!);
    if (ai != bi) {
      return ai.compareTo(bi);
    }
  }

  return 0;
}

List<String> collectSelectedTags(List<Map<String, dynamic>> releases, String fromTag, String toTag) {
  final Set<String> tags = <String>{};
  for (final Map<String, dynamic> release in releases) {
    final String tag = (release['tag_name'] ?? '').toString();
    if (semverTagPattern.hasMatch(tag)) {
      tags.add(tag);
    }
  }

  final List<String> sorted = tags.toList(growable: true)..sort(semverCompare);
  final List<String> selected = <String>[];
  for (final String tag in sorted) {
    if (fromTag.isNotEmpty && !versionLe(fromTag, tag)) {
      continue;
    }

    if (toTag.isNotEmpty && !versionLe(tag, toTag)) {
      continue;
    }

    selected.add(tag);
  }

  return selected;
}

Map<String, dynamic>? releaseByTag(List<Map<String, dynamic>> releases, String tag) {
  for (final Map<String, dynamic> item in releases) {
    if ((item['tag_name'] ?? '').toString() == tag) {
      return item;
    }
  }

  return null;
}

Set<String> loadTagsFile(String tagsFile) {
  final File file = File(tagsFile);
  if (!file.existsSync()) {
    throw StateError('Tags file not found: $tagsFile');
  }

  final Set<String> tags = <String>{};
  for (final String raw in file.readAsLinesSync()) {
    final String line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) {
      continue;
    }

    tags.add(line);
  }

  if (tags.isEmpty) {
    throw StateError('Tags file is empty: $tagsFile');
  }

  return tags;
}

List<String> applyTagsFilter(List<String> selectedTags, String tagsFile) {
  if (tagsFile.isEmpty) {
    return selectedTags;
  }

  final Set<String> allowed = loadTagsFile(tagsFile);
  return selectedTags.where(allowed.contains).toList(growable: false);
}

String reserveOutputName(Set<String> usedNames, String rawName) {
  String clean = rawName.split('/').last;
  clean = clean.split('?').first;
  clean = clean.replaceAll(' ', '_').replaceAll(':', '_').replaceAll('\t', '_');
  clean = clean.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '');
  if (clean.isEmpty) {
    clean = 'asset';
  }

  String stem = clean;
  String suffix = '';
  final int dot = clean.lastIndexOf('.');
  if (dot > 0) {
    stem = clean.substring(0, dot);
    suffix = clean.substring(dot);
  }

  String candidate = '$stem$suffix';
  int index = 2;
  while (usedNames.contains(candidate)) {
    candidate = '$stem-$index$suffix';
    index += 1;
  }
  usedNames.add(candidate);
  return candidate;
}
