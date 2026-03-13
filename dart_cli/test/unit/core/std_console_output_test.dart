import 'package:gfrm_dart/src/core/std_console_output.dart';
import 'package:test/test.dart';

void main() {
  group('StdConsoleOutput', () {
    test('exposes terminal capability getters', () {
      final StdConsoleOutput output = const StdConsoleOutput();

      expect(output.hasTerminal, anyOf(isTrue, isFalse));
      expect(output.supportsAnsiEscapes, anyOf(isTrue, isFalse));
    });
  });
}
