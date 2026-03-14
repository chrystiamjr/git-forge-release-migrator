import 'package:gfrm_dart/src/runtime_events/runtime_event_envelope.dart';
import 'package:test/test.dart';

void main() {
  group('RuntimeEventEnvelope', () {
    test('toMap serializes the base runtime event contract shape', () {
      final RuntimeEventEnvelope envelope = RuntimeEventEnvelope(
        runId: 'run-001',
        sequence: 3,
        occurredAt: '2026-03-14T20:30:00Z',
        eventType: 'run.started',
        payload: <String, dynamic>{'source_provider': 'gitlab'},
      );

      expect(envelope.toMap(), <String, dynamic>{
        'schema_version': 1,
        'run_id': 'run-001',
        'sequence': 3,
        'occurred_at': '2026-03-14T20:30:00Z',
        'event_type': 'run.started',
        'payload': <String, dynamic>{'source_provider': 'gitlab'},
      });
    });

    test('fromMap keeps round-trip serialization stable', () {
      final Map<String, dynamic> raw = <String, dynamic>{
        'schema_version': 1,
        'run_id': 'run-abc',
        'sequence': 10,
        'occurred_at': '2026-03-14T20:31:00Z',
        'event_type': 'tag.migrated',
        'payload': <String, dynamic>{'tag': 'v1.0.0', 'status': 'ok'},
      };

      final RuntimeEventEnvelope envelope = RuntimeEventEnvelope.fromMap(raw);
      expect(envelope.toMap(), raw);
    });

    test('fromMap falls back to contract-safe defaults for invalid fields', () {
      final RuntimeEventEnvelope envelope = RuntimeEventEnvelope.fromMap(<String, dynamic>{
        'schema_version': 'invalid',
        'run_id': null,
        'sequence': 'not-a-number',
        'occurred_at': null,
        'event_type': null,
        'payload': 'invalid-payload',
      });

      expect(envelope.schemaVersion, runtimeEventSchemaVersion);
      expect(envelope.runId, isEmpty);
      expect(envelope.sequence, 0);
      expect(envelope.occurredAt, isEmpty);
      expect(envelope.eventType, isEmpty);
      expect(envelope.payload, isEmpty);
      expect(
          envelope.toMap().keys,
          containsAll(<String>[
            'schema_version',
            'run_id',
            'sequence',
            'occurred_at',
            'event_type',
            'payload',
          ]));
    });
  });
}
