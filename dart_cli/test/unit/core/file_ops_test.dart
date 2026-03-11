import 'dart:io';

import 'package:gfrm_dart/src/core/file_ops.dart';
import 'package:gfrm_dart/src/core/file_ops_driver.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../support/temp_dir.dart';

final class _TestFileOpsDriver implements FileOpsDriver {
  _TestFileOpsDriver({
    this.onRunProcess,
    this.onRenameFile,
    this.onCopyFile,
  });

  final ProcessResult Function(String executable, List<String> arguments)? onRunProcess;
  final void Function(File file, String newPath)? onRenameFile;
  final File Function(File file, String newPath)? onCopyFile;

  @override
  ProcessResult runProcess(String executable, List<String> arguments) {
    if (onRunProcess != null) {
      return onRunProcess!(executable, arguments);
    }
    return Process.runSync(executable, arguments);
  }

  @override
  void renameFile(File file, String newPath) {
    if (onRenameFile != null) {
      onRenameFile!(file, newPath);
      return;
    }
    file.renameSync(newPath);
  }

  @override
  File copyFile(File file, String newPath) {
    if (onCopyFile != null) {
      return onCopyFile!(file, newPath);
    }
    return file.copySync(newPath);
  }

  @override
  void deleteFile(File file) {
    file.deleteSync();
  }
}

void main() {
  group('FileOps', () {
    group('ensureParentSecurity', () {
      test('creates nested directory when it does not exist', () {
        final Directory temp = createTempDir('gfrm-fileops-parent-');

        final Directory nested = Directory(p.join(temp.path, 'a', 'b', 'c'));
        expect(nested.existsSync(), isFalse);

        FileOps.ensureParentSecurity(nested);

        expect(nested.existsSync(), isTrue);
      });

      test('is idempotent when directory already exists', () {
        final Directory temp = createTempDir('gfrm-fileops-idem-');

        FileOps.ensureParentSecurity(temp);
        FileOps.ensureParentSecurity(temp);

        expect(temp.existsSync(), isTrue);
      });

      test('ignores chmod failures', () {
        final Directory temp = createTempDir('gfrm-fileops-parent-chmod-');
        final Directory nested = Directory(p.join(temp.path, 'a', 'b'));
        final FileOpsDriver driver = _TestFileOpsDriver(
          onRunProcess: (String _, List<String> __) => throw ProcessException('chmod', const <String>[]),
        );

        expect(() => FileOps.ensureParentSecurity(nested, driver: driver), returnsNormally);
        expect(nested.existsSync(), isTrue);
      });
    });

    group('hardenFilePermissions', () {
      test('does not throw on a valid file path', () {
        final Directory temp = createTempDir('gfrm-fileops-harden-');
        final File file = File(p.join(temp.path, 'secret.txt'))..writeAsStringSync('data');

        expect(() => FileOps.hardenFilePermissions(file.path), returnsNormally);
      });

      test('does not throw on non-existent path', () {
        expect(() => FileOps.hardenFilePermissions('/tmp/gfrm-nonexistent-file.txt'), returnsNormally);
      });

      test('ignores chmod failures', () {
        final Directory temp = createTempDir('gfrm-fileops-harden-chmod-');
        final File file = File(p.join(temp.path, 'secret.txt'))..writeAsStringSync('data');
        final FileOpsDriver driver = _TestFileOpsDriver(
          onRunProcess: (String _, List<String> __) => throw ProcessException('chmod', const <String>[]),
        );

        expect(() => FileOps.hardenFilePermissions(file.path, driver: driver), returnsNormally);
      });
    });

    group('replaceFile', () {
      test('replaces target with tmp file content', () {
        final Directory temp = createTempDir('gfrm-fileops-replace-');
        final File tmp = File(p.join(temp.path, 'tmp.txt'))..writeAsStringSync('new content');
        final File target = File(p.join(temp.path, 'target.txt'))..writeAsStringSync('old content');

        FileOps.replaceFile(tmp, target);

        expect(target.existsSync(), isTrue);
        expect(target.readAsStringSync(), 'new content');
        expect(tmp.existsSync(), isFalse);
      });

      test('creates target when it does not exist', () {
        final Directory temp = createTempDir('gfrm-fileops-new-');
        final File tmp = File(p.join(temp.path, 'tmp.txt'))..writeAsStringSync('content');
        final File target = File(p.join(temp.path, 'target.txt'));

        expect(target.existsSync(), isFalse);

        FileOps.replaceFile(tmp, target);

        expect(target.existsSync(), isTrue);
        expect(target.readAsStringSync(), 'content');
      });

      test('throws when tmp source does not exist', () {
        final Directory temp = createTempDir('gfrm-fileops-missing-');
        final File tmp = File(p.join(temp.path, 'missing.txt'));
        final File target = File(p.join(temp.path, 'target.txt'));

        expect(() => FileOps.replaceFile(tmp, target), throwsA(isA<FileSystemException>()));
      });

      test('falls back to copy after rename failure and removes backup', () {
        final Directory temp = createTempDir('gfrm-fileops-copy-fallback-');
        final File tmp = File(p.join(temp.path, 'tmp.txt'))..writeAsStringSync('new content');
        final File target = File(p.join(temp.path, 'target.txt'))..writeAsStringSync('old content');
        int tmpRenameAttempts = 0;
        final FileOpsDriver driver = _TestFileOpsDriver(
          onRenameFile: (File file, String newPath) {
            if (file.path == tmp.path) {
              tmpRenameAttempts += 1;
              if (tmpRenameAttempts <= 2) {
                throw FileSystemException('rename failed', file.path);
              }
            }

            file.renameSync(newPath);
          },
        );

        FileOps.replaceFile(tmp, target, driver: driver);

        expect(target.readAsStringSync(), 'new content');
        expect(tmp.existsSync(), isFalse);
        expect(Directory(temp.path).listSync().whereType<File>().where((File file) => file.path.contains('.bak-')),
            isEmpty);
      });

      test('restores backup with rename when replacement fails', () {
        final Directory temp = createTempDir('gfrm-fileops-restore-rename-');
        final File tmp = File(p.join(temp.path, 'tmp.txt'))..writeAsStringSync('new content');
        final File target = File(p.join(temp.path, 'target.txt'))..writeAsStringSync('old content');
        final FileOpsDriver driver = _TestFileOpsDriver(
          onRenameFile: (File file, String newPath) {
            if (file.path == tmp.path) {
              throw FileSystemException('rename failed', file.path);
            }

            file.renameSync(newPath);
          },
          onCopyFile: (File file, String newPath) {
            if (file.path == tmp.path) {
              throw FileSystemException('copy failed', file.path);
            }

            return file.copySync(newPath);
          },
        );

        FileOps.replaceFile(tmp, target, driver: driver);

        expect(target.existsSync(), isTrue);
        expect(target.readAsStringSync(), 'old content');
        expect(tmp.existsSync(), isTrue);
      });

      test('restores backup with copy when backup rename also fails', () {
        final Directory temp = createTempDir('gfrm-fileops-restore-copy-');
        final File tmp = File(p.join(temp.path, 'tmp.txt'))..writeAsStringSync('new content');
        final File target = File(p.join(temp.path, 'target.txt'))..writeAsStringSync('old content');
        final FileOpsDriver driver = _TestFileOpsDriver(
          onRenameFile: (File file, String newPath) {
            final bool isTmpRename = file.path == tmp.path;
            final bool isBackupRestore = file.path.contains('.bak-') && newPath == target.path;
            if (isTmpRename || isBackupRestore) {
              throw FileSystemException('rename failed', file.path);
            }

            file.renameSync(newPath);
          },
          onCopyFile: (File file, String newPath) {
            if (file.path == tmp.path) {
              throw FileSystemException('copy failed', file.path);
            }

            return file.copySync(newPath);
          },
        );

        FileOps.replaceFile(tmp, target, driver: driver);

        expect(target.existsSync(), isTrue);
        expect(target.readAsStringSync(), 'old content');
        expect(Directory(temp.path).listSync().whereType<File>().where((File file) => file.path.contains('.bak-')),
            isEmpty);
      });

      test('throws when replacement and backup restore both fail', () {
        final Directory temp = createTempDir('gfrm-fileops-total-failure-');
        final File tmp = File(p.join(temp.path, 'tmp.txt'))..writeAsStringSync('new content');
        final File target = File(p.join(temp.path, 'target.txt'))..writeAsStringSync('old content');
        final FileOpsDriver driver = _TestFileOpsDriver(
          onRenameFile: (File file, String newPath) {
            if (file.path == tmp.path || file.path.contains('.bak-')) {
              throw FileSystemException('rename failed', file.path);
            }

            file.renameSync(newPath);
          },
          onCopyFile: (File file, String newPath) => throw FileSystemException('copy failed', file.path),
        );

        expect(() => FileOps.replaceFile(tmp, target, driver: driver), throwsA(isA<FileSystemException>()));
      });
    });
  });
}
