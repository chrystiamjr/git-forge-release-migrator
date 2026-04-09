import 'package:gfrm_dart/src/runtime_events/runtime_event_type.dart';
import 'package:gfrm_dart/src/runtime_events/serial_runtime_event_publisher.dart';
import 'package:test/test.dart';

void main() {
  group('SerialRuntimeEventPublisher', () {
    test('assigns monotonic sequence numbers per run', () {
      final SerialRuntimeEventPublisher publisher = SerialRuntimeEventPublisher(
        runId: 'run-001',
        timestampFactory: () => '2026-04-08T12:00:00Z',
      );

      final Map<String, dynamic> firstPayload = <String, dynamic>{
        'source_provider': 'gitlab',
        'target_provider': 'github',
        'mode': 'migrate',
      };
      final Map<String, dynamic> secondPayload = <String, dynamic>{
        'status': 'ok',
      };
      final Map<String, dynamic> thirdPayload = <String, dynamic>{
        'tag': 'v1.0.0',
        'status': 'created',
      };

      final int firstSequence = publisher
          .publish(
            eventType: RuntimeEventType.runStarted,
            payload: firstPayload,
          )
          .sequence;
      final int secondSequence = publisher
          .publish(
            eventType: RuntimeEventType.preflightCompleted,
            payload: secondPayload,
          )
          .sequence;
      final int thirdSequence = publisher
          .publish(
            eventType: RuntimeEventType.tagMigrated,
            payload: thirdPayload,
          )
          .sequence;

      expect(<int>[firstSequence, secondSequence, thirdSequence], <int>[1, 2, 3]);
      expect(publisher.lastSequence, 3);
    });

    test('starts a new sequence per publisher instance and run', () {
      final SerialRuntimeEventPublisher firstPublisher = SerialRuntimeEventPublisher(
        runId: 'run-001',
        timestampFactory: () => '2026-04-08T12:00:00Z',
      );
      final SerialRuntimeEventPublisher secondPublisher = SerialRuntimeEventPublisher(
        runId: 'run-002',
        timestampFactory: () => '2026-04-08T12:00:01Z',
      );

      final int firstRunSequence = firstPublisher.publish(
        eventType: RuntimeEventType.runStarted,
        payload: <String, dynamic>{
          'source_provider': 'gitlab',
          'target_provider': 'github',
          'mode': 'migrate',
        },
      ).sequence;
      final int secondRunSequence = secondPublisher.publish(
        eventType: RuntimeEventType.runStarted,
        payload: <String, dynamic>{
          'source_provider': 'github',
          'target_provider': 'gitlab',
          'mode': 'resume',
        },
      ).sequence;

      expect(firstRunSequence, 1);
      expect(secondRunSequence, 1);
    });

    test('keeps sequence ordering authoritative even when timestamps move backward', () {
      final List<String> timestamps = <String>[
        '2026-04-08T12:00:05Z',
        '2026-04-08T12:00:01Z',
      ];
      int index = 0;
      final SerialRuntimeEventPublisher publisher = SerialRuntimeEventPublisher(
        runId: 'run-001',
        timestampFactory: () {
          final String timestamp = timestamps[index];
          index += 1;
          return timestamp;
        },
      );

      final firstEvent = publisher.publish(
        eventType: RuntimeEventType.tagMigrated,
        payload: <String, dynamic>{
          'tag': 'v1.0.0',
          'status': 'created',
        },
      );
      final secondEvent = publisher.publish(
        eventType: RuntimeEventType.tagMigrated,
        payload: <String, dynamic>{
          'tag': 'v1.0.1',
          'status': 'created',
        },
      );

      expect(firstEvent.occurredAt, '2026-04-08T12:00:05Z');
      expect(secondEvent.occurredAt, '2026-04-08T12:00:01Z');
      expect(firstEvent.sequence, 1);
      expect(secondEvent.sequence, 2);
      expect(firstEvent.sequence < secondEvent.sequence, isTrue);
    });

    test('copies payload data into the emitted envelope', () {
      final SerialRuntimeEventPublisher publisher = SerialRuntimeEventPublisher(
        runId: 'run-001',
        timestampFactory: () => '2026-04-08T12:00:00Z',
      );
      final Map<String, dynamic> payload = <String, dynamic>{
        'artifact_type': 'summary',
        'path': 'migration-results/run-001/summary.json',
      };

      final emitted = publisher.publish(
        eventType: RuntimeEventType.artifactWritten,
        payload: payload,
      );
      payload['path'] = 'mutated';

      expect(emitted.payload['path'], 'migration-results/run-001/summary.json');
    });
  });
}
