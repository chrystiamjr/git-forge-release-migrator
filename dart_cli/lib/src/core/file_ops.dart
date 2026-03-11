import 'dart:io';

import 'package:gfrm_dart/src/core/file_ops_driver.dart';
import 'package:gfrm_dart/src/core/system_file_ops_driver.dart';

final class FileOps {
  const FileOps._();

  static const FileOpsDriver _defaultDriver = SystemFileOpsDriver();

  static void ensureParentSecurity(Directory directory, {FileOpsDriver driver = _defaultDriver}) {
    directory.createSync(recursive: true);
    if (Platform.isWindows) {
      return;
    }

    try {
      driver.runProcess('chmod', <String>['700', directory.path]);
    } catch (_) {
      // Ignore permission hardening failures.
    }
  }

  static void hardenFilePermissions(String pathValue, {FileOpsDriver driver = _defaultDriver}) {
    if (Platform.isWindows) {
      return;
    }

    try {
      driver.runProcess('chmod', <String>['600', pathValue]);
    } catch (_) {
      // Ignore permission hardening failures.
    }
  }

  static void replaceFile(File tmpFile, File targetFile, {FileOpsDriver driver = _defaultDriver}) {
    try {
      driver.renameFile(tmpFile, targetFile.path);
      return;
    } on FileSystemException {
      // Continue to overwrite-safe fallback.
    }

    File? backupFile;
    if (targetFile.existsSync()) {
      backupFile = File('${targetFile.path}.bak-${DateTime.now().microsecondsSinceEpoch}');
      try {
        driver.renameFile(targetFile, backupFile.path);
      } on FileSystemException {
        backupFile = null;
      }
    }

    bool replaced = false;
    try {
      driver.renameFile(tmpFile, targetFile.path);
      replaced = true;
    } on FileSystemException {
      try {
        driver.copyFile(tmpFile, targetFile.path);
        driver.deleteFile(tmpFile);
        replaced = true;
      } on FileSystemException {
        replaced = false;
      }
    }

    if (replaced) {
      if (backupFile != null && backupFile.existsSync()) {
        driver.deleteFile(backupFile);
      }

      return;
    }

    if (backupFile != null && backupFile.existsSync() && !targetFile.existsSync()) {
      try {
        driver.renameFile(backupFile, targetFile.path);
        return;
      } on FileSystemException {
        driver.copyFile(backupFile, targetFile.path);
        driver.deleteFile(backupFile);
        return;
      }
    }

    throw FileSystemException('Failed to replace file', targetFile.path);
  }
}
