import 'dart:convert';
import 'dart:io';

import 'package:gfrm_dart/src/core/jsonl.dart';
import 'package:test/test.dart';

void main() {
  group('jsonl', () {
    test('appendLog writes one structured json line', () {
      final Directory temp = Directory.systemTemp.createTempSync('gfrm-dart-jsonl-');
      addTearDown(() => temp.deleteSync(recursive: true));

      final String path = '${temp.path}/logs/migration-log.jsonl';
      appendLog(
        path,
        status: 'created',
        tag: 'v1.0.0',
        message: 'ok',
        assetCount: 3,
        durationMs: 250,
        dryRun: false,
      );

      final List<String> lines = File(path).readAsLinesSync();
      expect(lines, hasLength(1));

      final Map<String, dynamic> data = jsonDecode(lines.first) as Map<String, dynamic>;
      expect(data['status'], 'created');
      expect(data['tag'], 'v1.0.0');
      expect(data['message'], 'ok');
      expect(data['asset_count'], 3);
      expect(data['duration_ms'], 250);
      expect(data['dry_run'], isFalse);
      expect(data['timestamp'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$')));
    });
  });
}
