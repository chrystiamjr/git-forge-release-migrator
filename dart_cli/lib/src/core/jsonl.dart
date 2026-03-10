import 'dart:convert';
import 'dart:io';

import 'time.dart';

final class JsonlLogWriter {
  const JsonlLogWriter._();

  static void appendLog(
    String path, {
    required String status,
    required String tag,
    required String message,
    required int assetCount,
    required int durationMs,
    required bool dryRun,
  }) {
    final Map<String, Object> record = <String, Object>{
      'timestamp': TimeUtils.utcTimestamp(),
      'status': status,
      'tag': tag,
      'message': message,
      'asset_count': assetCount,
      'duration_ms': durationMs,
      'dry_run': dryRun,
    };

    final File file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('${jsonEncode(record)}\n', mode: FileMode.append);
  }
}
