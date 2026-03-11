import 'dart:convert';
import 'dart:math';

import 'package:gfrm_dart/src/core/console_output.dart';
import 'package:gfrm_dart/src/core/enums/logger_prefix.dart';
import 'package:gfrm_dart/src/core/std_console_output.dart';

import 'test_helper.dart';
import 'time.dart';

class ConsoleLogger {
  ConsoleLogger({
    required this.quiet,
    required this.jsonOutput,
    ConsoleOutput? output,
    bool? silent,
  })  : output = output ?? const StdConsoleOutput(),
        _silent = silent ?? TestEnvironment.isTestProcess(),
        _tty = _resolveTty(
          output ?? const StdConsoleOutput(),
          silent ?? TestEnvironment.isTestProcess(),
          quiet,
          jsonOutput,
        );

  static bool _resolveTty(ConsoleOutput output, bool silent, bool quiet, bool jsonOutput) =>
      !silent && output.supportsAnsiEscapes && !quiet && !jsonOutput;

  final bool quiet;
  final bool jsonOutput;
  final ConsoleOutput output;
  final bool _silent;
  final bool _tty;
  final List<String> _frames = const <String>['|', '/', '-', '\\'];

  int _frame = 0;
  bool _spinnerRunning = false;
  String _spinnerMessage = '';
  LoggerPrefix _spinnerPrefix = LoggerPrefix.info;

  void _emit(LoggerPrefix prefix, String message, {required bool useErrorStream}) {
    if (_silent) {
      return;
    }

    if (jsonOutput) {
      final String encoded = jsonEncode(<String, String>{
        'timestamp': TimeUtils.utcTimestamp(),
        'level': prefix.label.toLowerCase(),
        'message': message,
      });
      if (useErrorStream) {
        output.writeErrLine(encoded);
      } else {
        output.writeOutLine(encoded);
      }
      return;
    }

    final String formatted = '[${prefix.label}] $message';
    if (useErrorStream) {
      output.writeErrLine(formatted);
    } else {
      output.writeOutLine(formatted);
    }
  }

  bool startSpinner(String message, {LoggerPrefix prefix = LoggerPrefix.info}) {
    if (_silent) {
      return false;
    }

    if (!_tty) {
      info(message);
      return false;
    }

    _spinnerRunning = true;
    _spinnerMessage = message;
    _spinnerPrefix = prefix;
    _frame = 0;

    _renderSpinner();

    return true;
  }

  void updateSpinner(String message) {
    if (!_spinnerRunning) {
      return;
    }

    _spinnerMessage = message;
    _renderSpinner();
  }

  void stopSpinner({String? finalMessage, LoggerPrefix prefix = LoggerPrefix.info}) {
    if (_spinnerRunning) {
      output.writeOut('\r${' ' * max(10, _spinnerMessage.length + 15)}\r');
      _spinnerRunning = false;
    }

    if (finalMessage != null && finalMessage.isNotEmpty) {
      _emit(prefix, finalMessage, useErrorStream: false);
    }
  }

  void _renderSpinner() {
    if (!_spinnerRunning || !_tty) {
      return;
    }

    final String glyph = _frames[_frame % _frames.length];

    _frame += 1;
    output.writeOut('\r[${_spinnerPrefix.label}] $_spinnerMessage $glyph');
  }

  void tickSpinner() => _renderSpinner();

  void info(String message) => _stopSpinnerAndEmit(LoggerPrefix.info, message, useErrorStream: false);

  void warn(String message) => _stopSpinnerAndEmit(LoggerPrefix.warning, message, useErrorStream: true);

  void error(String message) => _stopSpinnerAndEmit(LoggerPrefix.error, message, useErrorStream: true);

  void _stopSpinnerAndEmit(LoggerPrefix prefix, String message, {required bool useErrorStream}) {
    if (prefix == LoggerPrefix.info && quiet && !jsonOutput) {
      return;
    }

    if (_spinnerRunning) {
      stopSpinner();
    }

    _emit(prefix, message, useErrorStream: useErrorStream);
  }
}
