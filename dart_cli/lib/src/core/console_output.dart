abstract class ConsoleOutput {
  const ConsoleOutput();

  bool get hasTerminal;

  bool get supportsAnsiEscapes;

  void writeOut(String text);

  void writeOutLine(String line);

  void writeErrLine(String line);
}
