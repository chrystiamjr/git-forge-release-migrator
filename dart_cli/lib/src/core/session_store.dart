import 'dart:convert';
import 'dart:io';

void _ensureParentSecurity(Directory directory) {
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

void _hardenFilePermissions(String pathValue) {
  if (Platform.isWindows) {
    return;
  }

  try {
    Process.runSync('chmod', <String>['600', pathValue]);
  } catch (_) {
    // Ignore permission hardening failures.
  }
}

void _replaceFile(File tmpFile, File targetFile) {
  try {
    tmpFile.renameSync(targetFile.path);
    return;
  } on FileSystemException {
    // Continue to overwrite-safe fallback.
  }

  if (targetFile.existsSync()) {
    targetFile.deleteSync();
  }

  try {
    tmpFile.renameSync(targetFile.path);
  } on FileSystemException {
    tmpFile.copySync(targetFile.path);
    tmpFile.deleteSync();
  }
}

final class SessionStore {
  const SessionStore._();

  static Map<String, dynamic> loadSession(String path) {
    final File sessionFile = File(path);
    if (!sessionFile.existsSync()) {
      throw FileSystemException('Session file not found', path);
    }

    final dynamic payload = jsonDecode(sessionFile.readAsStringSync());
    if (payload is! Map<String, dynamic>) {
      throw ArgumentError('Invalid session payload in $path');
    }

    return payload;
  }

  static void saveSession(String path, Map<String, dynamic> payload) {
    final File sessionFile = File(path);
    _ensureParentSecurity(sessionFile.parent);

    final File tmpFile = File('${sessionFile.path}.tmp-${DateTime.now().microsecondsSinceEpoch}');
    tmpFile.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(payload)}\n');
    _hardenFilePermissions(tmpFile.path);
    _replaceFile(tmpFile, sessionFile);
    _hardenFilePermissions(sessionFile.path);
  }
}
