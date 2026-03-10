import 'dart:io';

import 'package:gfrm_dart/src/core/files.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('files', () {
    test('ensureDir creates nested directory when missing', () {
      final Directory temp = Directory.systemTemp.createTempSync('gfrm-dart-files-');
      addTearDown(() => temp.deleteSync(recursive: true));

      final String nestedPath = p.join(temp.path, 'a', 'b', 'c');
      expect(Directory(nestedPath).existsSync(), isFalse);

      final Directory created = FileSystemUtils.ensureDir(nestedPath);

      expect(created.path, nestedPath);
      expect(created.existsSync(), isTrue);
    });

    test('cleanupDir removes directory recursively', () {
      final Directory temp = Directory.systemTemp.createTempSync('gfrm-dart-cleanup-');
      addTearDown(() {
        if (temp.existsSync()) {
          temp.deleteSync(recursive: true);
        }
      });

      final String targetPath = p.join(temp.path, 'work', 'nested');
      FileSystemUtils.ensureDir(targetPath);
      File(p.join(targetPath, 'file.txt')).writeAsStringSync('data');
      expect(Directory(targetPath).existsSync(), isTrue);

      FileSystemUtils.cleanupDir(p.join(temp.path, 'work'));

      expect(Directory(p.join(temp.path, 'work')).existsSync(), isFalse);
      FileSystemUtils.cleanupDir(p.join(temp.path, 'work'));
    });

    test('sanitizeFilename normalizes path query and special chars', () {
      final String sanitized = FileSystemUtils.sanitizeFilename('https://host/path/my file:1?.zip');
      expect(sanitized, 'my_file_1');
      expect(FileSystemUtils.sanitizeFilename('??'), 'asset');
    });

    test('uniqueAssetFilename returns non-colliding name', () {
      final Directory temp = Directory.systemTemp.createTempSync('gfrm-dart-unique-');
      addTearDown(() => temp.deleteSync(recursive: true));

      final String first = p.join(temp.path, 'release.zip');
      File(first).writeAsStringSync('x');

      final String candidate = FileSystemUtils.uniqueAssetFilename(temp.path, 'release.zip');

      expect(candidate, 'release-2.zip');
      expect(File(p.join(temp.path, candidate)).existsSync(), isFalse);
    });
  });
}
