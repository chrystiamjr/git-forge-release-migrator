import 'package:gfrm_dart/src/core/std_console_output.dart';
import 'package:test/test.dart';

void main() {
  group('StdConsoleOutput', () {
    test('accesses terminal capability getters without throwing', () {
      final StdConsoleOutput output = const StdConsoleOutput();

      expect(() => output.hasTerminal, returnsNormally);
      expect(() => output.supportsAnsiEscapes, returnsNormally);
    });
  });
}
