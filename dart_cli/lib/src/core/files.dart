import 'dart:io';

import 'package:path/path.dart' as p;

Directory ensureDir(String pathValue) {
  final Directory dir = Directory(pathValue);
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }

  return dir;
}

void cleanupDir(String pathValue) {
  final Directory dir = Directory(pathValue);
  if (dir.existsSync()) {
    dir.deleteSync(recursive: true);
  }
}

String sanitizeFilename(String name) {
  String base = name.split('/').last;
  base = base.split('?').first;
  base = base.replaceAll(' ', '_').replaceAll(':', '_').replaceAll('\t', '_');
  base = base.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '');

  return base.isEmpty ? 'asset' : base;
}

String uniqueAssetFilename(String targetDir, String rawName) {
  final String clean = sanitizeFilename(rawName);
  String stem = clean;
  String suffix = '';

  final int dot = clean.lastIndexOf('.');
  if (dot > 0) {
    stem = clean.substring(0, dot);
    suffix = clean.substring(dot);
  }

  int i = 2;
  String candidate = '$stem$suffix';
  while (File(p.join(targetDir, candidate)).existsSync()) {
    i += 1;
    candidate = '$stem-$i$suffix';
  }

  return candidate;
}
