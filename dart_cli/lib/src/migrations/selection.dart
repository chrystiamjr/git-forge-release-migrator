import 'dart:io';

import '../core/versioning.dart';

final class SelectionService {
  const SelectionService._();

  static final RegExp semverTagPattern = RegExp(r'^v(\d+)\.(\d+)\.(\d+)$');

  static String capitalizeProvider(String provider) {
    if (provider.isEmpty) {
      return provider;
    }

    return provider[0].toUpperCase() + provider.substring(1);
  }

  static int semverCompare(String left, String right) {
    final RegExpMatch? leftMatch = semverTagPattern.firstMatch(left);
    final RegExpMatch? rightMatch = semverTagPattern.firstMatch(right);
    if (leftMatch == null && rightMatch == null) {
      return left.compareTo(right);
    }

    if (leftMatch == null) {
      return 1;
    }

    if (rightMatch == null) {
      return -1;
    }

    for (int index = 1; index <= 3; index += 1) {
      final int leftNumber = int.parse(leftMatch.group(index)!);
      final int rightNumber = int.parse(rightMatch.group(index)!);
      if (leftNumber != rightNumber) {
        return leftNumber.compareTo(rightNumber);
      }
    }

    return 0;
  }

  static List<String> collectSelectedTags(List<Map<String, dynamic>> releases, String fromTag, String toTag) {
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
      if (fromTag.isNotEmpty && !SemverUtils.versionLe(fromTag, tag)) {
        continue;
      }

      if (toTag.isNotEmpty && !SemverUtils.versionLe(tag, toTag)) {
        continue;
      }

      selected.add(tag);
    }

    return selected;
  }

  static Map<String, dynamic>? releaseByTag(List<Map<String, dynamic>> releases, String tag) {
    for (final Map<String, dynamic> item in releases) {
      if ((item['tag_name'] ?? '').toString() == tag) {
        return item;
      }
    }

    return null;
  }

  static Set<String> loadTagsFile(String tagsFile) {
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

  static List<String> applyTagsFilter(List<String> selectedTags, String tagsFile) {
    if (tagsFile.isEmpty) {
      return selectedTags;
    }

    final Set<String> allowed = loadTagsFile(tagsFile);
    return selectedTags.where(allowed.contains).toList(growable: false);
  }

  static String reserveOutputName(Set<String> usedNames, String rawName) {
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
}
