import 'package:gfrm_dart/src/core/logging.dart';

ConsoleLogger createSilentLogger() {
  return ConsoleLogger(quiet: true, jsonOutput: false);
}
