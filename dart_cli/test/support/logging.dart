import 'package:gfrm_dart/src/core/console_output.dart';
import 'package:gfrm_dart/src/core/logging.dart';

ConsoleLogger createSilentLogger({ConsoleOutput? output}) {
  return ConsoleLogger(quiet: true, jsonOutput: false, output: output);
}
