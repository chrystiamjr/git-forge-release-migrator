import 'package:gfrm_gui/src/application/run/models/desktop_artifacts_summary.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_preflight_summary.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_count_summary.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_failure_summary.dart';
import 'package:gfrm_gui/src/application/run/models/desktop_run_progress_item.dart';

const Object _desktopRunSnapshotUnset = Object();

final class DesktopRunSnapshot {
  const DesktopRunSnapshot({
    required this.sessionId,
    required this.runId,
    required this.lifecycle,
    required this.activePhase,
    required this.preflight,
    required this.artifacts,
    required this.tagCounts,
    required this.releaseCounts,
    required this.progressItems,
    required this.latestFailure,
    required this.completionStatus,
    required this.retryCommand,
    required this.totalTags,
    required this.failedTags,
    required this.canCancel,
    required this.canResume,
    this.elapsedTime = Duration.zero,
    this.estimatedRemainingTime,
  });

  const DesktopRunSnapshot.initial({this.sessionId = ''})
    : runId = '',
      lifecycle = 'idle',
      activePhase = 'idle',
      preflight = const DesktopPreflightSummary.initial(),
      artifacts = const DesktopArtifactsSummary.initial(),
      tagCounts = const DesktopRunCountSummary.initial(),
      releaseCounts = const DesktopRunCountSummary.initial(),
      progressItems = const <DesktopRunProgressItem>[],
      latestFailure = null,
      completionStatus = '',
      retryCommand = '',
      totalTags = 0,
      failedTags = 0,
      canCancel = false,
      canResume = false,
      elapsedTime = Duration.zero,
      estimatedRemainingTime = null;

  final String sessionId;
  final String runId;
  final String lifecycle;
  final String activePhase;
  final DesktopPreflightSummary preflight;
  final DesktopArtifactsSummary artifacts;
  final DesktopRunCountSummary tagCounts;
  final DesktopRunCountSummary releaseCounts;
  final List<DesktopRunProgressItem> progressItems;
  final DesktopRunFailureSummary? latestFailure;
  final String completionStatus;
  final String retryCommand;
  final int totalTags;
  final int failedTags;
  final bool canCancel;
  final bool canResume;
  final Duration elapsedTime;
  final Duration? estimatedRemainingTime;

  double get progressPercent {
    if (lifecycle == 'completed' || completionStatus.isNotEmpty) {
      return 1.0;
    }
    if (totalTags <= 0) {
      return 0.0;
    }
    final int processedTags = tagCounts.created + tagCounts.wouldCreate + tagCounts.skippedExisting + tagCounts.failed;
    final int processedReleases =
        releaseCounts.created + releaseCounts.wouldCreate + releaseCounts.skippedExisting + releaseCounts.failed;
    final double tagProgress = processedTags / totalTags;
    final double releaseProgress = processedReleases / totalTags;
    return ((tagProgress + releaseProgress) / 2.0).clamp(0.0, 1.0);
  }

  DesktopRunSnapshot copyWith({
    String? sessionId,
    String? runId,
    String? lifecycle,
    String? activePhase,
    DesktopPreflightSummary? preflight,
    DesktopArtifactsSummary? artifacts,
    DesktopRunCountSummary? tagCounts,
    DesktopRunCountSummary? releaseCounts,
    List<DesktopRunProgressItem>? progressItems,
    Object? latestFailure = _desktopRunSnapshotUnset,
    String? completionStatus,
    String? retryCommand,
    int? totalTags,
    int? failedTags,
    bool? canCancel,
    bool? canResume,
    Duration? elapsedTime,
    Object? estimatedRemainingTime = _desktopRunSnapshotUnset,
  }) {
    return DesktopRunSnapshot(
      sessionId: sessionId ?? this.sessionId,
      runId: runId ?? this.runId,
      lifecycle: lifecycle ?? this.lifecycle,
      activePhase: activePhase ?? this.activePhase,
      preflight: preflight ?? this.preflight,
      artifacts: artifacts ?? this.artifacts,
      tagCounts: tagCounts ?? this.tagCounts,
      releaseCounts: releaseCounts ?? this.releaseCounts,
      progressItems: progressItems ?? this.progressItems,
      latestFailure: identical(latestFailure, _desktopRunSnapshotUnset)
          ? this.latestFailure
          : latestFailure as DesktopRunFailureSummary?,
      completionStatus: completionStatus ?? this.completionStatus,
      retryCommand: retryCommand ?? this.retryCommand,
      totalTags: totalTags ?? this.totalTags,
      failedTags: failedTags ?? this.failedTags,
      canCancel: canCancel ?? this.canCancel,
      canResume: canResume ?? this.canResume,
      elapsedTime: elapsedTime ?? this.elapsedTime,
      estimatedRemainingTime: identical(estimatedRemainingTime, _desktopRunSnapshotUnset)
          ? this.estimatedRemainingTime
          : estimatedRemainingTime as Duration?,
    );
  }
}
