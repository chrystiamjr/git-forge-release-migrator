import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:gfrm_dart/src/core/enums/logger_prefix.dart';

import 'test_helper.dart';
import 'time.dart';

class ConsoleLogger {
  ConsoleLogger({required this.quiet, required this.jsonOutput, bool? silent})
      : _silent = silent ?? TestEnvironment.isTestProcess(),
        _tty = !(silent ?? TestEnvironment.isTestProcess()) && stdout.supportsAnsiEscapes && !quiet && !jsonOutput;

  final bool quiet;
  final bool jsonOutput;
  final bool _silent;
  final bool _tty;
  final List<String> _frames = const <String>['|', '/', '-', '\\'];

  int _frame = 0;
  bool _spinnerRunning = false;
  String _spinnerMessage = '';
  LoggerPrefix _spinnerPrefix = LoggerPrefix.info;

  void _emit(LoggerPrefix prefix, String message, IOSink sink) {
    if (_silent) {
      return;
    }

    if (jsonOutput) {
      sink.writeln(
        jsonEncode(<String, String>{
          'timestamp': TimeUtils.utcTimestamp(),
          'level': prefix.label.toLowerCase(),
          'message': message,
        }),
      );

      return;
    }

    sink.writeln('[${prefix.label}] $message');
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
      stdout.write('\r${' ' * max(10, _spinnerMessage.length + 15)}\r');
      _spinnerRunning = false;
    }

    if (finalMessage != null && finalMessage.isNotEmpty) {
      _emit(prefix, finalMessage, stdout);
    }
  }

  void _renderSpinner() {
    if (!_spinnerRunning || !_tty) {
      return;
    }

    final String glyph = _frames[_frame % _frames.length];

    _frame += 1;
    stdout.write('\r[${_spinnerPrefix.label}] $_spinnerMessage $glyph');
  }

  void tickSpinner() => _renderSpinner();

  void info(String message) => _stopSpinnerAndEmit(LoggerPrefix.info, message, stdout);

  void warn(String message) => _stopSpinnerAndEmit(LoggerPrefix.warning, message, stderr);

  void error(String message) => _stopSpinnerAndEmit(LoggerPrefix.error, message, stderr);

  void _stopSpinnerAndEmit(LoggerPrefix prefix, String message, IOSink sink) {
    if (prefix == LoggerPrefix.info && quiet && !jsonOutput) {
      return;
    }

    if (_spinnerRunning) {
      stopSpinner();
    }

    _emit(prefix, message, sink);
  }
}
