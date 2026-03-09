import 'dart:io';

import 'package:gfrm_dart/src/core/checkpoint.dart';
import 'package:test/test.dart';

void main() {
  group('checkpoint', () {
    test('append and load state by signature', () {
      final Directory temp = Directory.systemTemp.createTempSync('gfrm-dart-checkpoint-');
      addTearDown(() => temp.deleteSync(recursive: true));

      final String path = '${temp.path}/checkpoints/state.jsonl';
      appendCheckpoint(
        path,
        signature: 'sig-1',
        key: 'tag:v1.0.0',
        tag: 'v1.0.0',
        status: 'tag_created',
        message: 'ok',
      );
      appendCheckpoint(
        path,
        signature: 'sig-1',
        key: 'release:v1.0.0',
        tag: 'v1.0.0',
        status: 'created',
        message: 'ok',
      );
      appendCheckpoint(
        path,
        signature: 'sig-2',
        key: 'tag:v2.0.0',
        tag: 'v2.0.0',
        status: 'tag_created',
        message: 'ok',
      );

      final Map<String, String> state = loadCheckpointState(path, 'sig-1');
      expect(state['tag:v1.0.0'], 'tag_created');
      expect(state['release:v1.0.0'], 'created');
      expect(state.containsKey('tag:v2.0.0'), isFalse);
    });

    test('terminal status helpers', () {
      expect(isTerminalReleaseStatus('created'), isTrue);
      expect(isTerminalReleaseStatus('failed'), isFalse);
      expect(isTerminalTagStatus('tag_skipped_existing'), isTrue);
      expect(isTerminalTagStatus('pending'), isFalse);
    });
  });
}
