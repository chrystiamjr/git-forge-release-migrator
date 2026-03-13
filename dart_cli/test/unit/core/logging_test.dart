import 'package:gfrm_dart/src/core/logging.dart';
import 'package:gfrm_dart/src/core/enums/logger_prefix.dart';
import 'package:test/test.dart';

import '../../support/buffer_console_output.dart';

void main() {
  group('ConsoleLogger', () {
    test('info does not emit in silent mode', () {
      final BufferConsoleOutput output = BufferConsoleOutput();
      final ConsoleLogger logger = ConsoleLogger(
        quiet: false,
        jsonOutput: false,
        output: output,
        silent: true,
      );

      logger.info('hello');

      expect(output.stdoutLines, isEmpty);
      expect(output.stderrLines, isEmpty);
      expect(output.rawWrites, isEmpty);
    });

    test('logger defaults to silent mode under dart test when silent is omitted', () {
      final BufferConsoleOutput output = BufferConsoleOutput();
      final ConsoleLogger logger = ConsoleLogger(
        quiet: false,
        jsonOutput: false,
        output: output,
      );

      logger.info('hello');
      logger.warn('warning');

      expect(output.stdoutLines, isEmpty);
      expect(output.stderrLines, isEmpty);
      expect(output.rawWrites, isEmpty);
    });

    test('warn does not emit in silent mode', () {
      final BufferConsoleOutput output = BufferConsoleOutput();
      final ConsoleLogger logger = ConsoleLogger(
        quiet: false,
        jsonOutput: false,
        output: output,
        silent: true,
      );

      logger.warn('warning');

      expect(output.stdoutLines, isEmpty);
      expect(output.stderrLines, isEmpty);
    });

    test('error does not emit in silent mode', () {
      final BufferConsoleOutput output = BufferConsoleOutput();
      final ConsoleLogger logger = ConsoleLogger(
        quiet: false,
        jsonOutput: false,
        output: output,
        silent: true,
      );

      logger.error('error');

      expect(output.stdoutLines, isEmpty);
      expect(output.stderrLines, isEmpty);
    });

    test('info is suppressed when quiet is true and jsonOutput is false', () {
      final BufferConsoleOutput output = BufferConsoleOutput();
      final ConsoleLogger logger = ConsoleLogger(
        quiet: true,
        jsonOutput: false,
        output: output,
        silent: false,
      );

      logger.info('suppressed');

      expect(output.stdoutLines, isEmpty);
      expect(output.stderrLines, isEmpty);
    });

    test('warn is not suppressed by quiet flag', () {
      final BufferConsoleOutput output = BufferConsoleOutput();
      final ConsoleLogger logger = ConsoleLogger(
        quiet: true,
        jsonOutput: false,
        output: output,
        silent: false,
      );

      logger.warn('not suppressed');

      expect(output.stderrLines, <String>['[WARN] not suppressed']);
    });

    test('startSpinner returns false in silent mode', () {
      final BufferConsoleOutput output = BufferConsoleOutput(supportsAnsiEscapes: true);
      final ConsoleLogger logger = ConsoleLogger(
        quiet: false,
        jsonOutput: false,
        output: output,
        silent: true,
      );

      expect(logger.startSpinner('working...'), isFalse);
      expect(output.rawWrites, isEmpty);
      expect(output.stdoutLines, isEmpty);
    });

    test('stopSpinner does not emit when spinner is not running and final message is absent', () {
      final BufferConsoleOutput output = BufferConsoleOutput();
      final ConsoleLogger logger = ConsoleLogger(
        quiet: false,
        jsonOutput: false,
        output: output,
        silent: false,
      );

      logger.stopSpinner();

      expect(output.stdoutLines, isEmpty);
      expect(output.rawWrites, isEmpty);
    });

    test('updateSpinner does nothing when spinner is not running', () {
      final BufferConsoleOutput output = BufferConsoleOutput(supportsAnsiEscapes: true);
      final ConsoleLogger logger = ConsoleLogger(
        quiet: false,
        jsonOutput: false,
        output: output,
        silent: false,
      );

      logger.updateSpinner('updated');

      expect(output.rawWrites, isEmpty);
    });

    test('tickSpinner does nothing when spinner is not running', () {
      final BufferConsoleOutput output = BufferConsoleOutput(supportsAnsiEscapes: true);
      final ConsoleLogger logger = ConsoleLogger(
        quiet: false,
        jsonOutput: false,
        output: output,
        silent: false,
      );

      logger.tickSpinner();

      expect(output.rawWrites, isEmpty);
    });

    test('spinner lifecycle writes through the output adapter', () {
      final BufferConsoleOutput output = BufferConsoleOutput(
        hasTerminal: true,
        supportsAnsiEscapes: true,
      );
      final ConsoleLogger logger = ConsoleLogger(
        quiet: false,
        jsonOutput: false,
        output: output,
        silent: false,
      );

      expect(logger.startSpinner('step 1'), isTrue);
      logger.updateSpinner('step 2');
      logger.tickSpinner();
      logger.stopSpinner(finalMessage: 'done');

      expect(output.rawWrites, isNotEmpty);
      expect(output.stdoutLines, contains('[INFO] done'));
    });

    test('spinner can start with warning prefix and emits warning final message', () {
      final BufferConsoleOutput output = BufferConsoleOutput(
        hasTerminal: true,
        supportsAnsiEscapes: true,
      );
      final ConsoleLogger logger = ConsoleLogger(
        quiet: false,
        jsonOutput: false,
        output: output,
        silent: false,
      );

      expect(logger.startSpinner('checking', prefix: LoggerPrefix.warning), isTrue);
      logger.stopSpinner(finalMessage: 'done with warning', prefix: LoggerPrefix.warning);

      expect(output.rawWrites.first, contains('[WARN] checking'));
      expect(output.stdoutLines, contains('[WARN] done with warning'));
    });

    test('info stops an active spinner before emitting', () {
      final BufferConsoleOutput output = BufferConsoleOutput(
        hasTerminal: true,
        supportsAnsiEscapes: true,
      );
      final ConsoleLogger logger = ConsoleLogger(
        quiet: false,
        jsonOutput: false,
        output: output,
        silent: false,
      );

      expect(logger.startSpinner('loading'), isTrue);

      logger.info('finished');

      expect(output.rawWrites.last, contains('\r'));
      expect(output.stdoutLines.last, '[INFO] finished');
    });

    test('warn stops an active spinner and emits to stderr', () {
      final BufferConsoleOutput output = BufferConsoleOutput(
        hasTerminal: true,
        supportsAnsiEscapes: true,
      );
      final ConsoleLogger logger = ConsoleLogger(
        quiet: false,
        jsonOutput: false,
        output: output,
        silent: false,
      );

      expect(logger.startSpinner('loading'), isTrue);

      logger.warn('watch out');

      expect(output.rawWrites.last, contains('\r'));
      expect(output.stderrLines.last, '[WARN] watch out');
    });

    test('jsonOutput mode writes JSON to the correct streams', () {
      final BufferConsoleOutput output = BufferConsoleOutput();
      final ConsoleLogger logger = ConsoleLogger(
        quiet: false,
        jsonOutput: true,
        output: output,
        silent: false,
      );

      logger.info('json info');
      logger.warn('json warning');
      logger.error('json error');

      expect(output.stdoutLines.single, allOf(contains('"level":"info"'), contains('json info')));
      expect(output.stderrLines[0], allOf(contains('"level":"warn"'), contains('json warning')));
      expect(output.stderrLines[1], allOf(contains('"level":"error"'), contains('json error')));
    });

    test('_tty is false when supportsAnsiEscapes is false', () {
      final BufferConsoleOutput output = BufferConsoleOutput(supportsAnsiEscapes: false);
      final ConsoleLogger logger = ConsoleLogger(
        quiet: false,
        jsonOutput: false,
        output: output,
        silent: false,
      );

      // startSpinner returns false when _tty is false (falls back to info)
      expect(logger.startSpinner('msg'), isFalse);
      expect(output.rawWrites, isEmpty);
    });

    test('startSpinner falls back to info output when ansi is unavailable', () {
      final BufferConsoleOutput output = BufferConsoleOutput(supportsAnsiEscapes: false);
      final ConsoleLogger logger = ConsoleLogger(
        quiet: false,
        jsonOutput: false,
        output: output,
        silent: false,
      );

      expect(logger.startSpinner('working...'), isFalse);

      expect(output.stdoutLines, <String>['[INFO] working...']);
      expect(output.rawWrites, isEmpty);
    });

    test('plain text info, warn, and error use the expected streams', () {
      final BufferConsoleOutput output = BufferConsoleOutput();
      final ConsoleLogger logger = ConsoleLogger(
        quiet: false,
        jsonOutput: false,
        output: output,
        silent: false,
      );

      logger.info('plain text message');
      logger.warn('plain warning');
      logger.error('plain error');

      expect(output.stdoutLines, <String>['[INFO] plain text message']);
      expect(output.stderrLines, <String>['[WARN] plain warning', '[ERROR] plain error']);
    });
  });
}
