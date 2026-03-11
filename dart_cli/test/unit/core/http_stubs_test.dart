import 'package:test/test.dart';

import '../../support/http_stubs.dart';

void main() {
  group('ScriptedHttpClientHelper', () {
    test('requestJson throws when called without a scripted response', () async {
      final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper();

      await expectLater(stub.requestJson('https://example.com/json'), throwsA(isA<StateError>()));
    });

    test('requestStatus throws when called without a scripted response', () async {
      final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper();

      await expectLater(stub.requestStatus('https://example.com/status'), throwsA(isA<StateError>()));
    });

    test('downloadFile throws when called without a scripted response', () async {
      final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper();

      await expectLater(
        stub.downloadFile('https://example.com/file.zip', '/tmp/file.zip'),
        throwsA(isA<StateError>()),
      );
    });

    test('allowUnscriptedJson returns empty map', () async {
      final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(allowUnscriptedJson: true);

      expect(await stub.requestJson('https://example.com/json'), <String, dynamic>{});
    });

    test('allowUnscriptedStatus returns zero', () async {
      final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(allowUnscriptedStatus: true);

      expect(await stub.requestStatus('https://example.com/status'), 0);
    });

    test('allowUnscriptedDownload returns true', () async {
      final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(allowUnscriptedDownload: true);

      expect(await stub.downloadFile('https://example.com/file.zip', '/tmp/file.zip'), isTrue);
    });

    test('jsonResponse null is treated as an explicit first response', () async {
      final ScriptedHttpClientHelper stub = ScriptedHttpClientHelper(jsonResponse: null);

      expect(await stub.requestJson('https://example.com/json'), isNull);
      await expectLater(stub.requestJson('https://example.com/json'), throwsA(isA<StateError>()));
    });
  });
}
