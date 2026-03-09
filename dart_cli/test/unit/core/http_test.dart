import 'package:gfrm_dart/src/core/http.dart';
import 'package:test/test.dart';

void main() {
  group('http', () {
    test('addQueryParam appends key to URL without query', () {
      final HttpClientHelper helper = HttpClientHelper();

      final String result = helper.addQueryParam('https://example.com/path', 'token', 'abc123');

      expect(result, 'https://example.com/path?token=abc123');
    });

    test('addQueryParam replaces existing key and preserves others', () {
      final HttpClientHelper helper = HttpClientHelper();

      final String result = helper.addQueryParam('https://example.com/path?a=1&token=old', 'token', 'new');
      final Uri uri = Uri.parse(result);

      expect(uri.queryParameters['a'], '1');
      expect(uri.queryParameters['token'], 'new');
      expect(uri.path, '/path');
    });
  });
}
