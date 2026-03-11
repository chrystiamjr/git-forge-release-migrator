import 'dart:io';

import 'input_reader.dart';

final class StdInputReader extends InputReader {
  const StdInputReader();

  @override
  String readLine() {
    return stdin.readLineSync() ?? '';
  }
}
