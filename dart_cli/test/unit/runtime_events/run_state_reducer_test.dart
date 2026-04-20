import 'package:gfrm_dart/src/runtime_events/run_state.dart';
import 'package:gfrm_dart/src/runtime_events/run_state_reducer.dart';
import 'package:gfrm_dart/src/runtime_events/run_state_runtime_event_sink.dart';
import 'package:gfrm_dart/src/runtime_events/runtime_event_envelope.dart';
import 'package:gfrm_dart/src/runtime_events/runtime_event_sink_failure_mode.dart';
import 'package:gfrm_dart/src/runtime_events/runtime_event_type.dart';
import 'package:test/test.dart';

void main() {
  group('RunState reducer', () {
    test('derives typed snapshot for successful ordered stream', () {
      final RunStateRuntimeEventSink sink = RunStateRuntimeEventSink();

      for (final RuntimeEventEnvelope envelope in _successfulRunStream()) {
        sink.consume(envelope);
      }

      expect(sink.state.toMap(), <String, dynamic>{
        'event_schema_version': 1,
        'run_id': 'run-state-success',
        'last_sequence': 8,
        'last_occurred_at': '2026-04-13T12:00:08Z',
        'lifecycle': 'completed',
        'active_phase': 'completed',
        'source_provider': 'gitlab',
        'target_provider': 'github',
        'mode': 'migrate',
        'dry_run': false,
        'skip_tags': false,
        'skip_releases': false,
        'skip_release_assets': false,
        'settings_profile': 'team-a',
        'preflight': <String, dynamic>{
          'status': 'ok',
          'check_count': 4,
          'blocking_count': 0,
          'warning_count': 1,
        },
        'tag_counts': <String, dynamic>{
          'created': 1,
          'would_create': 0,
          'skipped_existing': 0,
          'failed': 0,
        },
        'release_counts': <String, dynamic>{
          'created': 1,
          'would_create': 0,
          'skipped_existing': 0,
          'failed': 0,
        },
        'tags': <String, dynamic>{
          'v1.0.0': <String, dynamic>{
            'tag': 'v1.0.0',
            'status': 'created',
            'message': '',
          },
        },
        'releases': <String, dynamic>{
          'v1.0.0': <String, dynamic>{
            'tag': 'v1.0.0',
            'status': 'created',
            'asset_count': 2,
            'message': '',
          },
        },
        'artifacts': <String, dynamic>{
          'migration_log_path': 'migration-results/run-state-success/migration-log.jsonl',
          'failed_tags_path': 'migration-results/run-state-success/failed-tags.txt',
          'summary_path': 'migration-results/run-state-success/summary.json',
          'paths_by_type': <String, dynamic>{
            'migration_log': 'migration-results/run-state-success/migration-log.jsonl',
            'failed_tags': 'migration-results/run-state-success/failed-tags.txt',
            'summary': 'migration-results/run-state-success/summary.json',
          },
        },
        'latest_failure': null,
        'completion_status': 'success',
        'retry_command': '',
        'total_tags': 1,
        'failed_tags': 0,
      });
    });

    test('keeps partial-failure results data without expanding event payloads', () {
      final RunStateRuntimeEventSink sink = RunStateRuntimeEventSink();

      for (final RuntimeEventEnvelope envelope in _partialFailureRunStream()) {
        sink.consume(envelope);
      }

      expect(sink.state.toMap()['lifecycle'], 'completed');
      expect(sink.state.toMap()['completion_status'], 'partial_failure');
      expect(sink.state.toMap()['retry_command'],
          'gfrm resume --tags-file migration-results/run-state-partial/failed-tags.txt');
      expect(sink.state.toMap()['failed_tags'], 1);
      expect(
        sink.state.toMap()['tag_counts'],
        <String, dynamic>{
          'created': 0,
          'would_create': 0,
          'skipped_existing': 0,
          'failed': 1,
        },
      );
    });

    test('captures preflight-stop failure and keeps phase aligned', () {
      final RunStateRuntimeEventSink sink = RunStateRuntimeEventSink(
        failureMode: RuntimeEventSinkFailureMode.mandatory,
      );

      for (final RuntimeEventEnvelope envelope in _preflightFailureStream()) {
        sink.consume(envelope);
      }

      expect(sink.state.toMap()['lifecycle'], 'failed');
      expect(sink.state.toMap()['active_phase'], 'preflight');
      expect(sink.state.toMap()['preflight'], <String, dynamic>{
        'status': 'failed',
        'check_count': 3,
        'blocking_count': 1,
        'warning_count': 0,
      });
      expect(sink.state.toMap()['latest_failure'], <String, dynamic>{
        'code': 'preflight-failed',
        'message': 'Missing target repository access.',
        'retryable': false,
        'phase': 'preflight',
      });
    });

    test('replay is deterministic for identical event sequences', () {
      final List<RuntimeEventEnvelope> stream = _successfulRunStream();
      final RunStateRuntimeEventSink first = RunStateRuntimeEventSink();
      final RunStateRuntimeEventSink second = RunStateRuntimeEventSink();

      for (final RuntimeEventEnvelope envelope in stream) {
        first.consume(envelope);
      }
      for (final RuntimeEventEnvelope envelope in stream) {
        second.consume(envelope);
      }

      expect(first.state.toMap(), second.state.toMap());
    });

    test('applies successful flow transitions step by step', () {
      final List<RunState> states = _replayStates(_successfulRunStream());

      expect(states[0].lifecycle.value, 'running');
      expect(states[0].activePhase.value, 'preflight');
      expect(states[0].sourceProvider, 'gitlab');
      expect(states[0].targetProvider, 'github');

      expect(states[1].preflightSummary.status, 'ok');
      expect(states[1].preflightSummary.checkCount, 4);
      expect(states[1].activePhase.value, 'preflight');

      expect(states[2].activePhase.value, 'tags');
      expect(states[2].tagCreatedCount, 1);
      expect(states[2].releaseCreatedCount, 0);

      expect(states[3].activePhase.value, 'releases');
      expect(states[3].tagCreatedCount, 1);
      expect(states[3].releaseCreatedCount, 1);

      expect(states[4].activePhase.value, 'artifact_finalization');
      expect(states[4].artifactPaths.migrationLogPath, 'migration-results/run-state-success/migration-log.jsonl');

      expect(states[5].artifactPaths.failedTagsPath, 'migration-results/run-state-success/failed-tags.txt');
      expect(states[6].artifactPaths.summaryPath, 'migration-results/run-state-success/summary.json');

      expect(states[7].lifecycle.value, 'completed');
      expect(states[7].activePhase.value, 'completed');
      expect(states[7].completionStatus, 'success');
      expect(states[7].totalTags, 1);
      expect(states[7].failedTags, 0);
    });

    test('replays captured envelope maps into the same final snapshot deterministically', () {
      final List<Map<String, dynamic>> captured =
          _successfulRunStream().map((RuntimeEventEnvelope envelope) => envelope.toMap()).toList(growable: false);

      RunState directState = const RunState.initial();
      for (final RuntimeEventEnvelope envelope in _successfulRunStream()) {
        directState = reduceRunState(directState, envelope);
      }

      RunState replayedState = const RunState.initial();
      for (final Map<String, dynamic> raw in captured) {
        replayedState = reduceRunState(replayedState, RuntimeEventEnvelope.fromMap(raw));
      }

      expect(replayedState.toMap(), directState.toMap());
    });

    test('evolves partial-failure flow through preflight tags artifacts and completion', () {
      final List<RunState> states = _replayStates(_partialFailureRunStream());

      expect(states[0].lifecycle.value, 'running');
      expect(states[0].mode, 'resume');

      expect(states[1].preflightSummary.status, 'ok');
      expect(states[1].activePhase.value, 'preflight');

      expect(states[2].activePhase.value, 'tags');
      expect(states[2].tagFailedCount, 1);
      expect(states[2].tagSnapshots['v2.0.0']?.message, 'network error');

      expect(states[3].activePhase.value, 'artifact_finalization');
      expect(states[3].artifactPaths.migrationLogPath, 'migration-results/run-state-partial/migration-log.jsonl');
      expect(states[4].artifactPaths.failedTagsPath, 'migration-results/run-state-partial/failed-tags.txt');
      expect(states[5].artifactPaths.summaryPath, 'migration-results/run-state-partial/summary.json');

      expect(states[6].lifecycle.value, 'completed');
      expect(states[6].completionStatus, 'partial_failure');
      expect(states[6].retryCommand, 'gfrm resume --tags-file migration-results/run-state-partial/failed-tags.txt');
      expect(states[6].failedTags, 1);
    });

    test('keeps reducer replay-safe for unknown event types and resets on new run_started', () {
      final RunStateRuntimeEventSink sink = RunStateRuntimeEventSink();

      sink.consume(
        _event(
          sequence: 1,
          occurredAt: '2026-04-13T12:30:01Z',
          eventType: RuntimeEventType.runStarted,
          runId: 'run-state-reset',
          payload: <String, dynamic>{
            'source_provider': 'gitlab',
            'target_provider': 'github',
            'mode': 'migrate',
            'dry_run': 'true',
            'skip_tags': 1,
          },
        ),
      );
      sink.consume(
        _event(
          sequence: 2,
          occurredAt: '2026-04-13T12:30:02Z',
          eventType: RuntimeEventType.tagMigrated,
          runId: 'run-state-reset',
          payload: <String, dynamic>{
            'tag': 'v1.2.3',
            'status': 'failed',
            'message': 'network error',
          },
        ),
      );
      sink.consume(
        RuntimeEventEnvelope(
          runId: 'run-state-reset',
          sequence: 3,
          occurredAt: '2026-04-13T12:30:03Z',
          eventType: 'unknown_event',
          payload: <String, dynamic>{'raw': 'value'},
        ),
      );
      sink.consume(
        _event(
          sequence: 4,
          occurredAt: '2026-04-13T12:30:04Z',
          eventType: RuntimeEventType.runStarted,
          runId: 'run-state-reset-2',
          payload: <String, dynamic>{
            'source_provider': 'bitbucket',
            'target_provider': 'gitlab',
            'mode': 'resume',
            'dry_run': false,
            'skip_tags': false,
          },
        ),
      );

      expect(sink.state.runId, 'run-state-reset-2');
      expect(sink.state.sourceProvider, 'bitbucket');
      expect(sink.state.targetProvider, 'gitlab');
      expect(sink.state.mode, 'resume');
      expect(sink.state.dryRun, isFalse);
      expect(sink.state.skipTags, isFalse);
      expect(sink.state.tagSnapshots, isEmpty);
      expect(sink.state.lastSequence, 4);
    });

    test('maps execution failures back to active execution phase when available', () {
      final RunStateRuntimeEventSink sink = RunStateRuntimeEventSink();

      sink.consume(
        _event(
          sequence: 1,
          occurredAt: '2026-04-13T12:40:01Z',
          eventType: RuntimeEventType.runStarted,
          runId: 'run-state-failure-phase',
          payload: <String, dynamic>{
            'source_provider': 'gitlab',
            'target_provider': 'github',
            'mode': 'migrate',
          },
        ),
      );
      sink.consume(
        _event(
          sequence: 2,
          occurredAt: '2026-04-13T12:40:02Z',
          eventType: RuntimeEventType.tagMigrated,
          runId: 'run-state-failure-phase',
          payload: <String, dynamic>{
            'tag': 'v9.9.9',
            'status': 'created',
          },
        ),
      );
      sink.consume(
        _event(
          sequence: 3,
          occurredAt: '2026-04-13T12:40:03Z',
          eventType: RuntimeEventType.runFailed,
          runId: 'run-state-failure-phase',
          payload: <String, dynamic>{
            'code': 'runtime-failed',
            'message': 'sink exploded',
            'phase': 'runtime_event_sink',
            'retryable': false,
          },
        ),
      );

      expect(sink.state.lifecycle.value, 'failed');
      expect(sink.state.activePhase.value, 'tags');
      expect(sink.state.latestFailure?.phase, 'runtime_event_sink');
    });
  });
}

List<RunState> _replayStates(List<RuntimeEventEnvelope> stream) {
  final List<RunState> states = <RunState>[];
  RunState currentState = const RunState.initial();

  for (final RuntimeEventEnvelope envelope in stream) {
    currentState = reduceRunState(currentState, envelope);
    states.add(currentState);
  }

  return states;
}

List<RuntimeEventEnvelope> _successfulRunStream() {
  return <RuntimeEventEnvelope>[
    _event(
      sequence: 1,
      occurredAt: '2026-04-13T12:00:01Z',
      eventType: RuntimeEventType.runStarted,
      runId: 'run-state-success',
      payload: <String, dynamic>{
        'source_provider': 'gitlab',
        'target_provider': 'github',
        'mode': 'migrate',
        'dry_run': false,
        'skip_tags': false,
        'settings_profile': 'team-a',
      },
    ),
    _event(
      sequence: 2,
      occurredAt: '2026-04-13T12:00:02Z',
      eventType: RuntimeEventType.preflightCompleted,
      runId: 'run-state-success',
      payload: <String, dynamic>{
        'status': 'ok',
        'check_count': 4,
        'blocking_count': 0,
        'warning_count': 1,
      },
    ),
    _event(
      sequence: 3,
      occurredAt: '2026-04-13T12:00:03Z',
      eventType: RuntimeEventType.tagMigrated,
      runId: 'run-state-success',
      payload: <String, dynamic>{
        'tag': 'v1.0.0',
        'status': 'created',
      },
    ),
    _event(
      sequence: 4,
      occurredAt: '2026-04-13T12:00:04Z',
      eventType: RuntimeEventType.releaseMigrated,
      runId: 'run-state-success',
      payload: <String, dynamic>{
        'tag': 'v1.0.0',
        'status': 'created',
        'asset_count': 2,
      },
    ),
    _event(
      sequence: 5,
      occurredAt: '2026-04-13T12:00:05Z',
      eventType: RuntimeEventType.artifactWritten,
      runId: 'run-state-success',
      payload: <String, dynamic>{
        'artifact_type': 'migration_log',
        'path': 'migration-results/run-state-success/migration-log.jsonl',
      },
    ),
    _event(
      sequence: 6,
      occurredAt: '2026-04-13T12:00:06Z',
      eventType: RuntimeEventType.artifactWritten,
      runId: 'run-state-success',
      payload: <String, dynamic>{
        'artifact_type': 'failed_tags',
        'path': 'migration-results/run-state-success/failed-tags.txt',
      },
    ),
    _event(
      sequence: 7,
      occurredAt: '2026-04-13T12:00:07Z',
      eventType: RuntimeEventType.artifactWritten,
      runId: 'run-state-success',
      payload: <String, dynamic>{
        'artifact_type': 'summary',
        'path': 'migration-results/run-state-success/summary.json',
        'schema_version': 2,
      },
    ),
    _event(
      sequence: 8,
      occurredAt: '2026-04-13T12:00:08Z',
      eventType: RuntimeEventType.runCompleted,
      runId: 'run-state-success',
      payload: <String, dynamic>{
        'status': 'success',
        'summary_path': 'migration-results/run-state-success/summary.json',
        'failed_tags_path': 'migration-results/run-state-success/failed-tags.txt',
        'total_tags': 1,
        'failed_tags': 0,
      },
    ),
  ];
}

List<RuntimeEventEnvelope> _partialFailureRunStream() {
  return <RuntimeEventEnvelope>[
    _event(
      sequence: 1,
      occurredAt: '2026-04-13T12:10:01Z',
      eventType: RuntimeEventType.runStarted,
      runId: 'run-state-partial',
      payload: <String, dynamic>{
        'source_provider': 'github',
        'target_provider': 'gitlab',
        'mode': 'resume',
      },
    ),
    _event(
      sequence: 2,
      occurredAt: '2026-04-13T12:10:02Z',
      eventType: RuntimeEventType.preflightCompleted,
      runId: 'run-state-partial',
      payload: <String, dynamic>{
        'status': 'ok',
        'check_count': 2,
        'blocking_count': 0,
        'warning_count': 0,
      },
    ),
    _event(
      sequence: 3,
      occurredAt: '2026-04-13T12:10:03Z',
      eventType: RuntimeEventType.tagMigrated,
      runId: 'run-state-partial',
      payload: <String, dynamic>{
        'tag': 'v2.0.0',
        'status': 'failed',
        'message': 'network error',
      },
    ),
    _event(
      sequence: 4,
      occurredAt: '2026-04-13T12:10:04Z',
      eventType: RuntimeEventType.artifactWritten,
      runId: 'run-state-partial',
      payload: <String, dynamic>{
        'artifact_type': 'migration_log',
        'path': 'migration-results/run-state-partial/migration-log.jsonl',
      },
    ),
    _event(
      sequence: 5,
      occurredAt: '2026-04-13T12:10:05Z',
      eventType: RuntimeEventType.artifactWritten,
      runId: 'run-state-partial',
      payload: <String, dynamic>{
        'artifact_type': 'failed_tags',
        'path': 'migration-results/run-state-partial/failed-tags.txt',
      },
    ),
    _event(
      sequence: 6,
      occurredAt: '2026-04-13T12:10:06Z',
      eventType: RuntimeEventType.artifactWritten,
      runId: 'run-state-partial',
      payload: <String, dynamic>{
        'artifact_type': 'summary',
        'path': 'migration-results/run-state-partial/summary.json',
        'schema_version': 2,
      },
    ),
    _event(
      sequence: 7,
      occurredAt: '2026-04-13T12:10:07Z',
      eventType: RuntimeEventType.runCompleted,
      runId: 'run-state-partial',
      payload: <String, dynamic>{
        'status': 'partial_failure',
        'summary_path': 'migration-results/run-state-partial/summary.json',
        'failed_tags_path': 'migration-results/run-state-partial/failed-tags.txt',
        'retry_command': 'gfrm resume --tags-file migration-results/run-state-partial/failed-tags.txt',
        'total_tags': 1,
        'failed_tags': 1,
      },
    ),
  ];
}

List<RuntimeEventEnvelope> _preflightFailureStream() {
  return <RuntimeEventEnvelope>[
    _event(
      sequence: 1,
      occurredAt: '2026-04-13T12:20:01Z',
      eventType: RuntimeEventType.runStarted,
      runId: 'run-state-preflight',
      payload: <String, dynamic>{
        'source_provider': 'gitlab',
        'target_provider': 'bitbucket',
        'mode': 'migrate',
      },
    ),
    _event(
      sequence: 2,
      occurredAt: '2026-04-13T12:20:02Z',
      eventType: RuntimeEventType.preflightCompleted,
      runId: 'run-state-preflight',
      payload: <String, dynamic>{
        'status': 'failed',
        'check_count': 3,
        'blocking_count': 1,
        'warning_count': 0,
      },
    ),
    _event(
      sequence: 3,
      occurredAt: '2026-04-13T12:20:03Z',
      eventType: RuntimeEventType.runFailed,
      runId: 'run-state-preflight',
      payload: <String, dynamic>{
        'code': 'preflight-failed',
        'message': 'Missing target repository access.',
        'phase': 'preflight',
        'retryable': false,
      },
    ),
  ];
}

RuntimeEventEnvelope _event({
  required int sequence,
  required String occurredAt,
  required RuntimeEventType eventType,
  required String runId,
  required Map<String, dynamic> payload,
}) {
  return RuntimeEventEnvelope(
    runId: runId,
    sequence: sequence,
    occurredAt: occurredAt,
    eventType: eventType.value,
    payload: payload,
  );
}
