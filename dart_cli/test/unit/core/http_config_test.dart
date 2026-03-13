import 'package:gfrm_dart/src/core/types/http_config.dart';
import 'package:test/test.dart';

void main() {
  group('HttpConfig', () {
    test('exposes default duration values', () {
      const HttpConfig config = HttpConfig();

      expect(config.connectTimeoutMs, 10000);
      expect(config.receiveTimeoutMs, 90000);
      expect(config.maxRetries, 3);
      expect(config.retryDelayMs, 750);
      expect(config.connectTimeout, const Duration(milliseconds: 10000));
      expect(config.receiveTimeout, const Duration(milliseconds: 90000));
      expect(config.retryDelay, const Duration(milliseconds: 750));
    });

    test('builds duration values from custom milliseconds', () {
      const HttpConfig config = HttpConfig(
        connectTimeoutMs: 1500,
        receiveTimeoutMs: 3200,
        maxRetries: 5,
        retryDelayMs: 125,
      );

      expect(config.connectTimeout, const Duration(milliseconds: 1500));
      expect(config.receiveTimeout, const Duration(milliseconds: 3200));
      expect(config.maxRetries, 5);
      expect(config.retryDelay, const Duration(milliseconds: 125));
    });
  });
}
