// ignore_for_file: implementation_imports

import 'package:gfrm_dart/src/runtime_events/run_state.dart';
import 'package:gfrm_dart/src/runtime_events/run_state_artifact_paths.dart';
import 'package:gfrm_dart/src/runtime_events/run_state_lifecycle.dart';
import 'package:gfrm_dart/src/runtime_events/run_state_phase.dart';
import 'package:gfrm_dart/src/runtime_events/run_state_reducer.dart';
import 'package:gfrm_dart/src/runtime_events/run_state_release_snapshot.dart';
import 'package:gfrm_dart/src/runtime_events/run_state_tag_snapshot.dart';
import 'package:gfrm_dart/src/runtime_events/runtime_event_envelope.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_snapshot.dart';
import 'package:gfrm_gui/src/runtime/run/mappers/map_run_state_to_snapshot.dart';

const String resultsDirectory = 'migration-results/2026-10-15T12-00-00';
const String resultsRetryCommand = 'gfrm resume --session-file sessions/run-1.json';

DesktopRunSnapshot resultsSnapshot(String scenario) =>
    mapRunStateToSnapshot(sessionId: scenario == 'idle' ? '' : 'session-1', state: resultsState(scenario));

RunState resultsState(String scenario) {
  if (scenario == 'idle') {
    return const RunState.initial();
  }
  final RunState started = const RunState.initial().copyWith(
    runId: 'run-1',
    lifecycle: RunStateLifecycle.running,
    activePhase: RunStatePhase.preflight,
  );
  if (scenario == 'running') {
    return started;
  }
  if (scenario == 'early-failure') {
    return reduceRunState(
      started,
      RuntimeEventEnvelope(
        runId: 'run-1',
        sequence: 2,
        occurredAt: '2026-10-15T12:00:00Z',
        eventType: 'run_failed',
        payload: <String, dynamic>{
          'code': 'preflight_failed',
          'message': 'Destination tags are missing.',
          'phase': 'preflight',
          'retryable': false,
        },
      ),
    );
  }
  final bool partial = scenario == 'partial-failure';
  final RunState migrated = started.copyWith(
    activePhase: RunStatePhase.releases,
    tagSnapshots: const <String, RunStateTagSnapshot>{
      'v1.0.0': RunStateTagSnapshot(tag: 'v1.0.0', status: 'created', message: ''),
      'v2.0.0': RunStateTagSnapshot(tag: 'v2.0.0', status: 'would_create', message: ''),
      'v3.0.0': RunStateTagSnapshot(tag: 'v3.0.0', status: 'skipped_existing', message: ''),
    },
    releaseSnapshots: <String, RunStateReleaseSnapshot>{
      'v1.0.0': const RunStateReleaseSnapshot(tag: 'v1.0.0', status: 'created', assetCount: 2, message: ''),
      'v2.0.0': const RunStateReleaseSnapshot(tag: 'v2.0.0', status: 'would_create', assetCount: 0, message: ''),
      'v3.0.0': RunStateReleaseSnapshot(
        tag: 'v3.0.0',
        status: partial ? 'failed' : 'skipped_existing',
        assetCount: 0,
        message: partial ? 'Asset upload failed.' : '',
      ),
    },
    artifactPaths: const RunStateArtifactPaths(
      pathsByType: <String, String>{'migration_log': '$resultsDirectory/migration-log.jsonl'},
    ),
  );
  return reduceRunState(
    migrated,
    RuntimeEventEnvelope(
      runId: 'run-1',
      sequence: 10,
      occurredAt: '2026-10-15T12:01:00Z',
      eventType: 'run_completed',
      payload: <String, dynamic>{
        'status': partial ? 'partial_failure' : 'success',
        'summary_path': '$resultsDirectory/summary.json',
        'failed_tags_path': '$resultsDirectory/failed-tags.txt',
        'retry_command': partial ? resultsRetryCommand : '',
        'total_tags': 3,
        'failed_tags': partial ? 1 : 0,
      },
    ),
  );
}
