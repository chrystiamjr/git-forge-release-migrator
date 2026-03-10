import 'dart:convert';
import 'dart:io';

import 'file_ops.dart';

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
    FileOps.ensureParentSecurity(sessionFile.parent);

    final File tmpFile = File('${sessionFile.path}.tmp-${DateTime.now().microsecondsSinceEpoch}');
    tmpFile.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(payload)}\n');
    FileOps.hardenFilePermissions(tmpFile.path);
    FileOps.replaceFile(tmpFile, sessionFile);
    FileOps.hardenFilePermissions(sessionFile.path);
  }
}
