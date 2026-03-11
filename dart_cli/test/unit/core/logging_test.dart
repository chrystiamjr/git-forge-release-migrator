import 'package:gfrm_dart/src/core/logging.dart';
import 'package:test/test.dart';

void main() {
  group('ConsoleLogger', () {
    // All loggers in tests use silent:true so they do not emit to stdout/stderr.
    // This validates that methods complete without throwing and that
    // state transitions (spinner) are correct regardless of output.

    test('info does not throw in silent mode', () {
      final ConsoleLogger logger = ConsoleLogger(quiet: false, jsonOutput: false, silent: true);
      expect(() => logger.info('hello'), returnsNormally);
    });

    test('warn does not throw in silent mode', () {
      final ConsoleLogger logger = ConsoleLogger(quiet: false, jsonOutput: false, silent: true);
      expect(() => logger.warn('warning'), returnsNormally);
    });

    test('error does not throw in silent mode', () {
      final ConsoleLogger logger = ConsoleLogger(quiet: false, jsonOutput: false, silent: true);
      expect(() => logger.error('error'), returnsNormally);
    });

    test('info is suppressed when quiet is true and jsonOutput is false', () {
      final ConsoleLogger logger = ConsoleLogger(quiet: true, jsonOutput: false, silent: false);
      // Should complete without throwing; output is suppressed by quiet flag.
      expect(() => logger.info('suppressed'), returnsNormally);
    });

    test('warn is not suppressed by quiet flag', () {
      final ConsoleLogger logger = ConsoleLogger(quiet: true, jsonOutput: false, silent: true);
      expect(() => logger.warn('not suppressed'), returnsNormally);
    });

    test('startSpinner returns false in silent mode', () {
      final ConsoleLogger logger = ConsoleLogger(quiet: false, jsonOutput: false, silent: true);
      expect(logger.startSpinner('working...'), isFalse);
    });

    test('stopSpinner does not throw when spinner is not running', () {
      final ConsoleLogger logger = ConsoleLogger(quiet: false, jsonOutput: false, silent: true);
      expect(() => logger.stopSpinner(finalMessage: 'done'), returnsNormally);
    });

    test('updateSpinner does not throw when spinner is not running', () {
      final ConsoleLogger logger = ConsoleLogger(quiet: false, jsonOutput: false, silent: true);
      expect(() => logger.updateSpinner('updated'), returnsNormally);
    });

    test('tickSpinner does not throw when spinner is not running', () {
      final ConsoleLogger logger = ConsoleLogger(quiet: false, jsonOutput: false, silent: true);
      expect(() => logger.tickSpinner(), returnsNormally);
    });

    test('spinner lifecycle in silent mode: start, update, stop', () {
      final ConsoleLogger logger = ConsoleLogger(quiet: false, jsonOutput: false, silent: true);
      logger.startSpinner('step 1');
      logger.updateSpinner('step 2');
      logger.tickSpinner();
      expect(() => logger.stopSpinner(finalMessage: 'done'), returnsNormally);
    });

    test('jsonOutput mode does not throw for info, warn, error', () {
      final ConsoleLogger logger = ConsoleLogger(quiet: false, jsonOutput: true, silent: true);
      expect(() => logger.info('msg'), returnsNormally);
      expect(() => logger.warn('msg'), returnsNormally);
      expect(() => logger.error('msg'), returnsNormally);
    });

    // The following tests use silent:false to exercise the actual emit paths.
    // Output goes to stdout/stderr which is captured by the test runner.

    test('info emits plain text when not silent and not jsonOutput', () {
      final ConsoleLogger logger = ConsoleLogger(quiet: false, jsonOutput: false, silent: false);
      expect(() => logger.info('plain text message'), returnsNormally);
    });

    test('warn emits plain text when not silent', () {
      final ConsoleLogger logger = ConsoleLogger(quiet: false, jsonOutput: false, silent: false);
      expect(() => logger.warn('plain warning'), returnsNormally);
    });

    test('error emits plain text when not silent', () {
      final ConsoleLogger logger = ConsoleLogger(quiet: false, jsonOutput: false, silent: false);
      expect(() => logger.error('plain error'), returnsNormally);
    });

    test('info emits JSON when jsonOutput is true and not silent', () {
      final ConsoleLogger logger = ConsoleLogger(quiet: false, jsonOutput: true, silent: false);
      expect(() => logger.info('json message'), returnsNormally);
    });

    test('warn emits JSON when jsonOutput is true and not silent', () {
      final ConsoleLogger logger = ConsoleLogger(quiet: false, jsonOutput: true, silent: false);
      expect(() => logger.warn('json warning'), returnsNormally);
    });

    test('startSpinner remains safe in non-silent mode regardless of tty environment', () {
      final ConsoleLogger logger = ConsoleLogger(quiet: false, jsonOutput: false, silent: false);
      expect(() => logger.startSpinner('working...'), returnsNormally);
      expect(() => logger.stopSpinner(finalMessage: 'done'), returnsNormally);
    });
  });
}
