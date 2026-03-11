import 'dart:io';

final class FileOps {
  const FileOps._();

  static ProcessResult Function(String executable, List<String> arguments) _runProcess =
      (String executable, List<String> arguments) => Process.runSync(executable, arguments);
  static void Function(File file, String newPath) _renameFile = (File file, String newPath) => file.renameSync(newPath);
  static File Function(File file, String newPath) _copyFile = (File file, String newPath) => file.copySync(newPath);
  static void Function(File file) _deleteFile = (File file) => file.deleteSync();

  static void configureForTests({
    ProcessResult Function(String executable, List<String> arguments)? runProcess,
    void Function(File file, String newPath)? renameFile,
    File Function(File file, String newPath)? copyFile,
    void Function(File file)? deleteFile,
  }) {
    _runProcess = runProcess ?? _runProcess;
    _renameFile = renameFile ?? _renameFile;
    _copyFile = copyFile ?? _copyFile;
    _deleteFile = deleteFile ?? _deleteFile;
  }

  static void resetTestConfiguration() {
    _runProcess = (String executable, List<String> arguments) => Process.runSync(executable, arguments);
    _renameFile = (File file, String newPath) => file.renameSync(newPath);
    _copyFile = (File file, String newPath) => file.copySync(newPath);
    _deleteFile = (File file) => file.deleteSync();
  }

  static void ensureParentSecurity(Directory directory) {
    directory.createSync(recursive: true);
    if (Platform.isWindows) {
      return;
    }

    try {
      _runProcess('chmod', <String>['700', directory.path]);
    } catch (_) {
      // Ignore permission hardening failures.
    }
  }

  static void hardenFilePermissions(String pathValue) {
    if (Platform.isWindows) {
      return;
    }

    try {
      _runProcess('chmod', <String>['600', pathValue]);
    } catch (_) {
      // Ignore permission hardening failures.
    }
  }

  static void replaceFile(File tmpFile, File targetFile) {
    try {
      _renameFile(tmpFile, targetFile.path);
      return;
    } on FileSystemException {
      // Continue to overwrite-safe fallback.
    }

    File? backupFile;
    if (targetFile.existsSync()) {
      backupFile = File('${targetFile.path}.bak-${DateTime.now().microsecondsSinceEpoch}');
      try {
        _renameFile(targetFile, backupFile.path);
      } on FileSystemException {
        backupFile = null;
      }
    }

    bool replaced = false;
    try {
      _renameFile(tmpFile, targetFile.path);
      replaced = true;
    } on FileSystemException {
      try {
        _copyFile(tmpFile, targetFile.path);
        _deleteFile(tmpFile);
        replaced = true;
      } on FileSystemException {
        replaced = false;
      }
    }

    if (replaced) {
      if (backupFile != null && backupFile.existsSync()) {
        _deleteFile(backupFile);
      }

      return;
    }

    if (backupFile != null && backupFile.existsSync() && !targetFile.existsSync()) {
      try {
        _renameFile(backupFile, targetFile.path);
        return;
      } on FileSystemException {
        _copyFile(backupFile, targetFile.path);
        _deleteFile(backupFile);
        return;
      }
    }

    throw FileSystemException('Failed to replace file', targetFile.path);
  }
}
