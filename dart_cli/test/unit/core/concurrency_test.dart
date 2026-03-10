import 'dart:async';

import 'package:gfrm_dart/src/core/concurrency.dart';
import 'package:test/test.dart';

void main() {
  group('concurrency', () {
    test('mapWithLimit preserves result order', () async {
      final List<int> input = <int>[1, 2, 3, 4];
      final List<int> output = await Concurrency.mapWithLimit<int, int>(
        items: input,
        limit: 3,
        task: (int value, int _) async {
          await Future<void>.delayed(Duration(milliseconds: (5 - value) * 2));
          return value * 10;
        },
      );

      expect(output, <int>[10, 20, 30, 40]);
    });

    test('mapWithLimit enforces max active workers', () async {
      int running = 0;
      int maxRunning = 0;
      final Completer<void> gate = Completer<void>();
      final Future<List<int>> run = Concurrency.mapWithLimit<int, int>(
        items: <int>[1, 2, 3, 4, 5],
        limit: 2,
        task: (int value, int _) async {
          running += 1;
          if (running > maxRunning) {
            maxRunning = running;
          }

          await gate.future;
          running -= 1;
          return value;
        },
      );

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(maxRunning, 2);
      gate.complete();
      final List<int> values = await run;
      expect(values, <int>[1, 2, 3, 4, 5]);
    });

    test('mapWithLimit treats non-positive limits as sequential execution', () async {
      int maxRunning = 0;
      int running = 0;
      final List<int> values = await Concurrency.mapWithLimit<int, int>(
        items: <int>[1, 2, 3],
        limit: 0,
        task: (int value, int _) async {
          running += 1;
          if (running > maxRunning) {
            maxRunning = running;
          }

          await Future<void>.delayed(const Duration(milliseconds: 1));
          running -= 1;
          return value;
        },
      );

      expect(values, <int>[1, 2, 3]);
      expect(maxRunning, 1);
    });
  });
}
