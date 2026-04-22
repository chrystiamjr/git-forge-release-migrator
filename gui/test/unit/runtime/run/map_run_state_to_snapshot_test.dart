// ignore_for_file: implementation_imports

import 'package:flutter_test/flutter_test.dart';
import 'package:gfrm_dart/src/runtime_events/run_state.dart';
import 'package:gfrm_dart/src/runtime_events/run_state_artifact_paths.dart';
import 'package:gfrm_dart/src/runtime_events/run_state_failure.dart';
import 'package:gfrm_dart/src/runtime_events/run_state_lifecycle.dart';
import 'package:gfrm_dart/src/runtime_events/run_state_phase.dart';
import 'package:gfrm_dart/src/runtime_events/run_state_preflight_summary.dart';
import 'package:gfrm_dart/src/runtime_events/run_state_release_snapshot.dart';
import 'package:gfrm_dart/src/runtime_events/run_state_tag_snapshot.dart';
import 'package:gfrm_gui/src/runtime/run/mappers/map_run_state_to_snapshot.dart';

void main() {
  group('mapRunStateToSnapshot', () {
    test('maps run state into sorted GUI snapshot data', () {
      final RunState state = const RunState.initial().copyWith(
        runId: 'run-1',
        lifecycle: RunStateLifecycle.running,
        activePhase: RunStatePhase.releases,
        preflightSummary: const RunStatePreflightSummary(
          status: 'ok',
          checkCount: 4,
          blockingCount: 0,
          warningCount: 1,
        ),
        tagSnapshots: const <String, RunStateTagSnapshot>{
          'v2.0.0': RunStateTagSnapshot(tag: 'v2.0.0', status: 'failed', message: 'tag failed'),
          'v1.0.0': RunStateTagSnapshot(tag: 'v1.0.0', status: 'created', message: 'tag created'),
        },
        releaseSnapshots: const <String, RunStateReleaseSnapshot>{
          'v1.0.0': RunStateReleaseSnapshot(
            tag: 'v1.0.0',
            status: 'created',
            assetCount: 2,
            message: 'release created',
          ),
        },
        artifactPaths: const RunStateArtifactPaths(
          pathsByType: <String, String>{
            'migration_log': '/tmp/migration-log.jsonl',
            'failed_tags': '/tmp/failed-tags.txt',
            'summary': '/tmp/summary.json',
          },
        ),
        latestFailure: const RunStateFailure(
          code: 'release_failed',
          message: 'release failed',
          retryable: true,
          phase: 'releases',
        ),
        retryCommand: 'gfrm resume --from /tmp/failed-tags.txt',
        totalTags: 2,
        failedTags: 1,
      );

      final snapshot = mapRunStateToSnapshot(sessionId: 'session-1', state: state);

      expect(snapshot.sessionId, 'session-1');
      expect(snapshot.runId, 'run-1');
      expect(snapshot.lifecycle, 'running');
      expect(snapshot.activePhase, 'releases');
      expect(snapshot.preflight.status, 'ok');
      expect(snapshot.preflight.checkCount, 4);
      expect(snapshot.artifacts.summaryPath, '/tmp/summary.json');
      expect(snapshot.tagCounts.created, 1);
      expect(snapshot.tagCounts.failed, 1);
      expect(snapshot.releaseCounts.created, 1);
      expect(snapshot.progressItems.map((item) => '${item.tag}:${item.kind}:${item.status}'), <String>[
        'v1.0.0:release:created',
        'v1.0.0:tag:created',
        'v2.0.0:tag:failed',
      ]);
      expect(snapshot.progressItems.first.assetCount, 2);
      expect(snapshot.latestFailure?.code, 'release_failed');
      expect(snapshot.latestFailure?.retryable, isTrue);
      expect(snapshot.totalTags, 2);
      expect(snapshot.failedTags, 1);
      expect(snapshot.canCancel, isFalse);
      expect(snapshot.canResume, isTrue);
    });

    test('uses idle preflight fallback when runtime status is empty', () {
      final snapshot = mapRunStateToSnapshot(sessionId: 'session-2', state: const RunState.initial());

      expect(snapshot.preflight.status, 'idle');
      expect(snapshot.progressItems, isEmpty);
      expect(snapshot.canResume, isFalse);
      expect(snapshot.elapsedTime, Duration.zero);
      expect(snapshot.estimatedRemainingTime, isNull);
      expect(snapshot.progressPercent, 0.0);
    });

    test('progressPercent reflects partial tag completion', () {
      final RunState state = const RunState.initial().copyWith(
        lifecycle: RunStateLifecycle.running,
        activePhase: RunStatePhase.tags,
        tagSnapshots: const <String, RunStateTagSnapshot>{
          'v1.0.0': RunStateTagSnapshot(tag: 'v1.0.0', status: 'created', message: ''),
          'v2.0.0': RunStateTagSnapshot(tag: 'v2.0.0', status: 'created', message: ''),
        },
        totalTags: 4,
      );

      final snapshot = mapRunStateToSnapshot(sessionId: 'session-3', state: state);

      expect(snapshot.progressPercent, greaterThan(0.0));
      expect(snapshot.progressPercent, lessThan(1.0));
      expect(snapshot.progressPercent, closeTo(0.25, 0.01));
    });

    test('progressPercent is 1.0 when completionStatus is set', () {
      final RunState state = const RunState.initial().copyWith(
        lifecycle: RunStateLifecycle.running,
        completionStatus: 'success',
        totalTags: 2,
      );

      final snapshot = mapRunStateToSnapshot(sessionId: 'session-4', state: state);

      expect(snapshot.progressPercent, 1.0);
    });
  });
}
