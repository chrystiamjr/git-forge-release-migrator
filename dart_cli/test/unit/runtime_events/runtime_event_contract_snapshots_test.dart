import 'package:gfrm_dart/src/runtime_events/runtime_event_envelope.dart';
import 'package:gfrm_dart/src/runtime_events/runtime_event_payload_contract.dart';
import 'package:gfrm_dart/src/runtime_events/runtime_event_payload_contracts.dart';
import 'package:gfrm_dart/src/runtime_events/runtime_event_type.dart';
import 'package:test/test.dart';

void main() {
  group('runtime event contract snapshots', () {
    test('locks the initial runtime event schema version', () {
      expect(runtimeEventSchemaVersion, 1);

      final RuntimeEventEnvelope envelope = RuntimeEventEnvelope(
        runId: 'run-contract',
        sequence: 1,
        occurredAt: '2026-03-14T20:30:00Z',
        eventType: RuntimeEventType.runStarted.value,
        payload: <String, dynamic>{
          'source_provider': 'gitlab',
          'target_provider': 'github',
          'mode': 'migrate',
        },
      );

      expect(envelope.toMap()['schema_version'], runtimeEventSchemaVersion);
    });

    test('keeps representative event envelope snapshots stable', () {
      final List<_RuntimeEventSnapshot> snapshots = <_RuntimeEventSnapshot>[
        _RuntimeEventSnapshot(
          sequence: 1,
          eventType: RuntimeEventType.runStarted,
          payload: <String, dynamic>{
            'source_provider': 'gitlab',
            'target_provider': 'github',
            'mode': 'migrate',
            'dry_run': false,
          },
          expected: <String, dynamic>{
            'schema_version': 1,
            'run_id': 'run-contract',
            'sequence': 1,
            'occurred_at': '2026-03-14T20:30:00Z',
            'event_type': 'run_started',
            'payload': <String, dynamic>{
              'source_provider': 'gitlab',
              'target_provider': 'github',
              'mode': 'migrate',
              'dry_run': false,
            },
          },
        ),
        _RuntimeEventSnapshot(
          sequence: 2,
          eventType: RuntimeEventType.tagMigrated,
          payload: <String, dynamic>{
            'tag': 'v1.0.0',
            'status': 'created',
          },
          expected: <String, dynamic>{
            'schema_version': 1,
            'run_id': 'run-contract',
            'sequence': 2,
            'occurred_at': '2026-03-14T20:30:00Z',
            'event_type': 'tag_migrated',
            'payload': <String, dynamic>{
              'tag': 'v1.0.0',
              'status': 'created',
            },
          },
        ),
        _RuntimeEventSnapshot(
          sequence: 3,
          eventType: RuntimeEventType.artifactWritten,
          payload: <String, dynamic>{
            'artifact_type': 'summary',
            'path': 'migration-results/run-contract/summary.json',
            'schema_version': 2,
          },
          expected: <String, dynamic>{
            'schema_version': 1,
            'run_id': 'run-contract',
            'sequence': 3,
            'occurred_at': '2026-03-14T20:30:00Z',
            'event_type': 'artifact_written',
            'payload': <String, dynamic>{
              'artifact_type': 'summary',
              'path': 'migration-results/run-contract/summary.json',
              'schema_version': 2,
            },
          },
        ),
        _RuntimeEventSnapshot(
          sequence: 4,
          eventType: RuntimeEventType.runCompleted,
          payload: <String, dynamic>{
            'status': 'success',
            'summary_path': 'migration-results/run-contract/summary.json',
            'failed_tags_path': 'migration-results/run-contract/failed-tags.txt',
            'retry_command': 'gfrm resume --session-file migration-results/run-contract/session.json',
          },
          expected: <String, dynamic>{
            'schema_version': 1,
            'run_id': 'run-contract',
            'sequence': 4,
            'occurred_at': '2026-03-14T20:30:00Z',
            'event_type': 'run_completed',
            'payload': <String, dynamic>{
              'status': 'success',
              'summary_path': 'migration-results/run-contract/summary.json',
              'failed_tags_path': 'migration-results/run-contract/failed-tags.txt',
              'retry_command': 'gfrm resume --session-file migration-results/run-contract/session.json',
            },
          },
        ),
        _RuntimeEventSnapshot(
          sequence: 5,
          eventType: RuntimeEventType.runFailed,
          payload: <String, dynamic>{
            'code': 'runtime-failed',
            'message': 'migration failed',
            'phase': 'release',
            'retryable': true,
          },
          expected: <String, dynamic>{
            'schema_version': 1,
            'run_id': 'run-contract',
            'sequence': 5,
            'occurred_at': '2026-03-14T20:30:00Z',
            'event_type': 'run_failed',
            'payload': <String, dynamic>{
              'code': 'runtime-failed',
              'message': 'migration failed',
              'phase': 'release',
              'retryable': true,
            },
          },
        ),
      ];

      for (final _RuntimeEventSnapshot snapshot in snapshots) {
        final RuntimeEventPayloadContract? contract = findRuntimeEventPayloadContract(snapshot.eventType);
        expect(contract, isNotNull, reason: 'Missing payload contract for ${snapshot.eventType.value}');
        expect(contract?.accepts(snapshot.payload), isTrue, reason: 'Payload drift for ${snapshot.eventType.value}');

        final RuntimeEventEnvelope envelope = RuntimeEventEnvelope(
          runId: 'run-contract',
          sequence: snapshot.sequence,
          occurredAt: '2026-03-14T20:30:00Z',
          eventType: snapshot.eventType.value,
          payload: snapshot.payload,
        );

        expect(envelope.toMap(), snapshot.expected, reason: 'Snapshot drift for ${snapshot.eventType.value}');

        final RuntimeEventEnvelope parsedEnvelope = RuntimeEventEnvelope.fromMap(snapshot.expected);
        expect(parsedEnvelope.toMap(), snapshot.expected,
            reason: 'Envelope compatibility drift for ${snapshot.eventType.value}');
      }
    });
  });
}

final class _RuntimeEventSnapshot {
  const _RuntimeEventSnapshot({
    required this.sequence,
    required this.eventType,
    required this.payload,
    required this.expected,
  });

  final int sequence;
  final RuntimeEventType eventType;
  final Map<String, dynamic> payload;
  final Map<String, dynamic> expected;
}
