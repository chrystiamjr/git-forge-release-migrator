import 'package:gfrm_dart/src/runtime_events/runtime_event_type.dart';
import 'package:test/test.dart';

void main() {
  group('RuntimeEventType', () {
    test('exposes canonical underscore event values', () {
      expect(
        RuntimeEventType.values.map((RuntimeEventType type) => type.value),
        <String>[
          'run_started',
          'preflight_completed',
          'tag_migrated',
          'release_migrated',
          'artifact_written',
          'run_completed',
          'run_failed',
        ],
      );
    });

    test('tryParse resolves canonical values only', () {
      expect(RuntimeEventType.tryParse('run_started'), RuntimeEventType.runStarted);
      expect(RuntimeEventType.tryParse('run.started'), isNull);
      expect(RuntimeEventType.tryParse('unknown'), isNull);
    });
  });
}
