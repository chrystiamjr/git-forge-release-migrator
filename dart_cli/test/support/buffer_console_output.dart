import 'package:gfrm_dart/src/core/console_output.dart';

final class BufferConsoleOutput extends ConsoleOutput {
  BufferConsoleOutput({
    this.hasTerminal = false,
    this.supportsAnsiEscapes = false,
  });

  @override
  final bool hasTerminal;

  @override
  final bool supportsAnsiEscapes;

  final List<String> stdoutLines = <String>[];
  final List<String> stderrLines = <String>[];
  final List<String> rawWrites = <String>[];

  @override
  void writeOut(String text) {
    rawWrites.add(text);
  }

  @override
  void writeOutLine(String line) {
    stdoutLines.add(line);
  }

  @override
  void writeErrLine(String line) {
    stderrLines.add(line);
  }
}
