import 'package:gfrm_dart/src/core/input_reader.dart';

final class FakeInputReader extends InputReader {
  FakeInputReader({List<String>? answers}) : _answers = List<String>.from(answers ?? const <String>[]);

  final List<String> _answers;

  @override
  String readLine() {
    if (_answers.isEmpty) {
      throw StateError('FakeInputReader: unexpected readLine() call — queue exhausted.');
    }

    return _answers.removeAt(0);
  }
}
