import 'dart:convert';
import 'dart:io';

import 'time.dart';

final class CheckpointStore {
  const CheckpointStore._();

  static const Set<String> _terminalReleaseStatuses = <String>{'created', 'updated', 'skipped_existing'};
  static const Set<String> _terminalTagStatuses = <String>{'tag_created', 'tag_skipped_existing'};

  static Map<String, String> loadCheckpointState(String path, String signature) {
    final File file = File(path);
    if (!file.existsSync()) {
      return <String, String>{};
    }

    final Map<String, String> state = <String, String>{};
    final List<String> lines = file.readAsLinesSync();
    for (final String rawLine in lines) {
      final String text = rawLine.trim();
      if (text.isEmpty) {
        continue;
      }

      Map<String, dynamic> item;
      try {
        item = jsonDecode(text) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }

      if ((item['signature'] ?? '').toString() != signature) {
        continue;
      }

      final String key = (item['key'] ?? '').toString();
      final String status = (item['status'] ?? '').toString();
      if (key.isNotEmpty && status.isNotEmpty) {
        state[key] = status;
      }
    }

    return state;
  }

  static void appendCheckpoint(
    String path, {
    required String signature,
    required String key,
    required String tag,
    required String status,
    required String message,
  }) {
    final Map<String, String> record = <String, String>{
      'timestamp': TimeUtils.utcTimestamp(),
      'signature': signature,
      'key': key,
      'tag': tag,
      'status': status,
      'message': message,
    };

    final File file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('${jsonEncode(record)}\n', mode: FileMode.append);
  }

  static bool isTerminalReleaseStatus(String status) => _terminalReleaseStatuses.contains(status);

  static bool isTerminalTagStatus(String status) => _terminalTagStatuses.contains(status);
}
