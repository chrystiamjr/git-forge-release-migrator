import 'package:gfrm_dart/src/core/test_helper.dart';
import 'package:test/test.dart';

void main() {
  group('TestEnvironment', () {
    test('isTestProcess returns true under dart test runtime', () {
      expect(TestEnvironment.isTestProcess(), isTrue);
    });
  });
}
