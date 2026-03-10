import 'dart:io';

import 'package:gfrm_dart/src/core/session_store.dart';
import 'package:test/test.dart';

void main() {
  group('session_store', () {
    test('saveSession and loadSession keep payload data', () {
      final Directory temp = Directory.systemTemp.createTempSync('gfrm-dart-session-');
      addTearDown(() => temp.deleteSync(recursive: true));

      final String path = '${temp.path}/sessions/last-session.json';
      final Map<String, dynamic> payload = <String, dynamic>{
        'source_provider': 'github',
        'target_provider': 'gitlab',
        'download_workers': 4,
        'nested': <String, dynamic>{'enabled': true},
      };

      SessionStore.saveSession(path, payload);

      final Map<String, dynamic> restored = SessionStore.loadSession(path);
      expect(restored['source_provider'], 'github');
      expect(restored['target_provider'], 'gitlab');
      expect(restored['download_workers'], 4);
      expect((restored['nested'] as Map<String, dynamic>)['enabled'], isTrue);
    });

    test('loadSession throws when file is missing', () {
      expect(
        () => SessionStore.loadSession('/tmp/gfrm-session-missing-file.json'),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('saveSession overwrites an existing session file', () {
      final Directory temp = Directory.systemTemp.createTempSync('gfrm-dart-session-overwrite-');
      addTearDown(() => temp.deleteSync(recursive: true));

      final String path = '${temp.path}/sessions/last-session.json';

      SessionStore.saveSession(path, <String, dynamic>{
        'source_provider': 'github',
        'target_provider': 'gitlab',
        'download_workers': 2,
      });

      SessionStore.saveSession(path, <String, dynamic>{
        'source_provider': 'bitbucket',
        'target_provider': 'github',
        'download_workers': 6,
      });

      final Map<String, dynamic> restored = SessionStore.loadSession(path);
      expect(restored['source_provider'], 'bitbucket');
      expect(restored['target_provider'], 'github');
      expect(restored['download_workers'], 6);
    });

    test('loadSession throws for non-map payload', () {
      final Directory temp = Directory.systemTemp.createTempSync('gfrm-dart-session-invalid-');
      addTearDown(() => temp.deleteSync(recursive: true));

      final String path = '${temp.path}/session.json';
      File(path).writeAsStringSync('[1,2,3]');

      expect(() => SessionStore.loadSession(path), throwsArgumentError);
    });
  });
}
