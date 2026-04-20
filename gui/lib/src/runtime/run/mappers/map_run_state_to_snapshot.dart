// ignore_for_file: implementation_imports

import 'package:gfrm_dart/src/runtime_events/run_state.dart';
import 'package:gfrm_dart/src/runtime_events/run_state_release_snapshot.dart';
import 'package:gfrm_dart/src/runtime_events/run_state_tag_snapshot.dart';

import 'package:gfrm_gui/src/application/run/models/desktop_artifacts_summary.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_preflight_summary.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_count_summary.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_progress_item.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_snapshot.dart';
import 'package:gfrm_gui/src/runtime/run/mappers/map_run_state_failure_to_summary.dart';

DesktopRunSnapshot mapRunStateToSnapshot({
  required String sessionId,
  required RunState state,
  DesktopPreflightSummary? preflight,
}) {
  final List<DesktopRunProgressItem> progressItems =
      <DesktopRunProgressItem>[
        ...state.tagSnapshots.values.map(_mapRunStateTagSnapshotToProgressItem),
        ...state.releaseSnapshots.values.map(_mapRunStateReleaseSnapshotToProgressItem),
      ]..sort((DesktopRunProgressItem left, DesktopRunProgressItem right) {
        final int tagCompare = left.tag.compareTo(right.tag);
        if (tagCompare != 0) {
          return tagCompare;
        }

        return left.kind.compareTo(right.kind);
      });

  return DesktopRunSnapshot(
    sessionId: sessionId,
    runId: state.runId,
    lifecycle: state.lifecycle.value,
    activePhase: state.activePhase.value,
    preflight:
        preflight ??
        DesktopPreflightSummary(
          status: state.preflightSummary.status.isEmpty ? 'idle' : state.preflightSummary.status,
          checks: const [],
          checkCount: state.preflightSummary.checkCount,
          blockingCount: state.preflightSummary.blockingCount,
          warningCount: state.preflightSummary.warningCount,
        ),
    artifacts: DesktopArtifactsSummary(
      summaryPath: state.artifactPaths.summaryPath,
      failedTagsPath: state.artifactPaths.failedTagsPath,
      migrationLogPath: state.artifactPaths.migrationLogPath,
    ),
    tagCounts: DesktopRunCountSummary(
      created: state.tagCreatedCount,
      wouldCreate: state.tagWouldCreateCount,
      skippedExisting: state.tagSkippedExistingCount,
      failed: state.tagFailedCount,
    ),
    releaseCounts: DesktopRunCountSummary(
      created: state.releaseCreatedCount,
      wouldCreate: state.releaseWouldCreateCount,
      skippedExisting: state.releaseSkippedExistingCount,
      failed: state.releaseFailedCount,
    ),
    progressItems: progressItems,
    latestFailure: state.latestFailure == null ? null : mapRunStateFailureToSummary(state.latestFailure!),
    completionStatus: state.completionStatus,
    retryCommand: state.retryCommand,
    totalTags: state.totalTags,
    failedTags: state.failedTags,
    canCancel: false,
    canResume: state.retryCommand.trim().isNotEmpty || state.failedTags > 0 || state.lifecycle.value == 'failed',
  );
}

DesktopRunProgressItem _mapRunStateTagSnapshotToProgressItem(RunStateTagSnapshot snapshot) {
  return DesktopRunProgressItem(kind: 'tag', tag: snapshot.tag, status: snapshot.status, message: snapshot.message);
}

DesktopRunProgressItem _mapRunStateReleaseSnapshotToProgressItem(RunStateReleaseSnapshot snapshot) {
  return DesktopRunProgressItem(
    kind: 'release',
    tag: snapshot.tag,
    status: snapshot.status,
    message: snapshot.message,
    assetCount: snapshot.assetCount,
  );
}
