import 'dart:io';

final class FileOps {
  const FileOps._();

  static void ensureParentSecurity(Directory directory) {
    directory.createSync(recursive: true);
    if (Platform.isWindows) {
      return;
    }

    try {
      Process.runSync('chmod', <String>['700', directory.path]);
    } catch (_) {
      // Ignore permission hardening failures.
    }
  }

  static void hardenFilePermissions(String pathValue) {
    if (Platform.isWindows) {
      return;
    }

    try {
      Process.runSync('chmod', <String>['600', pathValue]);
    } catch (_) {
      // Ignore permission hardening failures.
    }
  }

  static void replaceFile(File tmpFile, File targetFile) {
    try {
      tmpFile.renameSync(targetFile.path);
      return;
    } on FileSystemException {
      // Continue to overwrite-safe fallback.
    }

    File? backupFile;
    if (targetFile.existsSync()) {
      backupFile = File('${targetFile.path}.bak-${DateTime.now().microsecondsSinceEpoch}');
      try {
        targetFile.renameSync(backupFile.path);
      } on FileSystemException {
        backupFile = null;
      }
    }

    bool replaced = false;
    try {
      tmpFile.renameSync(targetFile.path);
      replaced = true;
    } on FileSystemException {
      try {
        tmpFile.copySync(targetFile.path);
        tmpFile.deleteSync();
        replaced = true;
      } on FileSystemException {
        replaced = false;
      }
    }

    if (replaced) {
      if (backupFile != null && backupFile.existsSync()) {
        backupFile.deleteSync();
      }
      return;
    }

    if (backupFile != null && backupFile.existsSync() && !targetFile.existsSync()) {
      try {
        backupFile.renameSync(targetFile.path);
        return;
      } on FileSystemException {
        backupFile.copySync(targetFile.path);
        backupFile.deleteSync();
        return;
      }
    }

    throw FileSystemException('Failed to replace file', targetFile.path);
  }
}
