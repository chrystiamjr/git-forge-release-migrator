import 'dart:io';

import 'console_output.dart';

final class StdConsoleOutput extends ConsoleOutput {
  const StdConsoleOutput();

  @override
  bool get hasTerminal => stdout.hasTerminal;

  @override
  bool get supportsAnsiEscapes => stdout.supportsAnsiEscapes;

  @override
  void writeOut(String text) {
    stdout.write(text);
  }

  @override
  void writeOutLine(String line) {
    stdout.writeln(line);
  }

  @override
  void writeErrLine(String line) {
    stderr.writeln(line);
  }
}
