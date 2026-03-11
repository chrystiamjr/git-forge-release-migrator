import 'package:test/test.dart';

import '../../support/fake_input_reader.dart';

void main() {
  group('FakeInputReader', () {
    test('returns answers in FIFO order', () {
      final FakeInputReader reader = FakeInputReader(answers: <String>['first', 'second', 'third']);

      expect(reader.readLine(), 'first');
      expect(reader.readLine(), 'second');
      expect(reader.readLine(), 'third');
    });

    test('throws StateError when queue is exhausted', () {
      final FakeInputReader reader = FakeInputReader(answers: <String>['only']);

      reader.readLine();

      expect(() => reader.readLine(), throwsA(isA<StateError>()));
    });

    test('throws StateError immediately when created with no answers', () {
      final FakeInputReader reader = FakeInputReader();

      expect(() => reader.readLine(), throwsA(isA<StateError>()));
    });
  });
}
