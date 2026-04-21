import 'run_state_artifact_paths.dart';
import 'run_state_failure.dart';
import 'run_state_lifecycle.dart';
import 'run_state_phase.dart';
import 'run_state_preflight_summary.dart';
import 'run_state_release_snapshot.dart';
import 'run_state_tag_snapshot.dart';

const Object _runStateUnset = Object();

final class RunState {
  const RunState({
    required this.eventSchemaVersion,
    required this.runId,
    required this.lastSequence,
    required this.lastOccurredAt,
    required this.lifecycle,
    required this.activePhase,
    required this.sourceProvider,
    required this.targetProvider,
    required this.mode,
    required this.dryRun,
    required this.skipTags,
    required this.skipReleases,
    required this.skipReleaseAssets,
    required this.settingsProfile,
    required this.preflightSummary,
    required this.tagSnapshots,
    required this.releaseSnapshots,
    required this.artifactPaths,
    required this.latestFailure,
    required this.completionStatus,
    required this.retryCommand,
    required this.totalTags,
    required this.failedTags,
  });

  const RunState.initial()
      : eventSchemaVersion = 0,
        runId = '',
        lastSequence = 0,
        lastOccurredAt = '',
        lifecycle = RunStateLifecycle.idle,
        activePhase = RunStatePhase.idle,
        sourceProvider = '',
        targetProvider = '',
        mode = '',
        dryRun = false,
        skipTags = false,
        skipReleases = false,
        skipReleaseAssets = false,
        settingsProfile = '',
        preflightSummary = const RunStatePreflightSummary.initial(),
        tagSnapshots = const <String, RunStateTagSnapshot>{},
        releaseSnapshots = const <String, RunStateReleaseSnapshot>{},
        artifactPaths = const RunStateArtifactPaths.initial(),
        latestFailure = null,
        completionStatus = '',
        retryCommand = '',
        totalTags = 0,
        failedTags = 0;

  final int eventSchemaVersion;
  final String runId;
  final int lastSequence;
  final String lastOccurredAt;
  final RunStateLifecycle lifecycle;
  final RunStatePhase activePhase;
  final String sourceProvider;
  final String targetProvider;
  final String mode;
  final bool dryRun;
  final bool skipTags;
  final bool skipReleases;
  final bool skipReleaseAssets;
  final String settingsProfile;
  final RunStatePreflightSummary preflightSummary;
  final Map<String, RunStateTagSnapshot> tagSnapshots;
  final Map<String, RunStateReleaseSnapshot> releaseSnapshots;
  final RunStateArtifactPaths artifactPaths;
  final RunStateFailure? latestFailure;
  final String completionStatus;
  final String retryCommand;
  final int totalTags;
  final int failedTags;

  int get tagCreatedCount => _countTagStatus('created');
  int get tagWouldCreateCount => _countTagStatus('would_create');
  int get tagSkippedExistingCount => _countTagStatus('skipped_existing');
  int get tagFailedCount => _countTagStatus('failed');

  int get releaseCreatedCount => _countReleaseStatus('created');
  int get releaseWouldCreateCount => _countReleaseStatus('would_create');
  int get releaseSkippedExistingCount => _countReleaseStatus('skipped_existing');
  int get releaseFailedCount => _countReleaseStatus('failed');

  RunState copyWith({
    int? eventSchemaVersion,
    String? runId,
    int? lastSequence,
    String? lastOccurredAt,
    RunStateLifecycle? lifecycle,
    RunStatePhase? activePhase,
    String? sourceProvider,
    String? targetProvider,
    String? mode,
    bool? dryRun,
    bool? skipTags,
    bool? skipReleases,
    bool? skipReleaseAssets,
    String? settingsProfile,
    RunStatePreflightSummary? preflightSummary,
    Map<String, RunStateTagSnapshot>? tagSnapshots,
    Map<String, RunStateReleaseSnapshot>? releaseSnapshots,
    RunStateArtifactPaths? artifactPaths,
    Object? latestFailure = _runStateUnset,
    String? completionStatus,
    String? retryCommand,
    int? totalTags,
    int? failedTags,
  }) {
    return RunState(
      eventSchemaVersion: eventSchemaVersion ?? this.eventSchemaVersion,
      runId: runId ?? this.runId,
      lastSequence: lastSequence ?? this.lastSequence,
      lastOccurredAt: lastOccurredAt ?? this.lastOccurredAt,
      lifecycle: lifecycle ?? this.lifecycle,
      activePhase: activePhase ?? this.activePhase,
      sourceProvider: sourceProvider ?? this.sourceProvider,
      targetProvider: targetProvider ?? this.targetProvider,
      mode: mode ?? this.mode,
      dryRun: dryRun ?? this.dryRun,
      skipTags: skipTags ?? this.skipTags,
      skipReleases: skipReleases ?? this.skipReleases,
      skipReleaseAssets: skipReleaseAssets ?? this.skipReleaseAssets,
      settingsProfile: settingsProfile ?? this.settingsProfile,
      preflightSummary: preflightSummary ?? this.preflightSummary,
      tagSnapshots: tagSnapshots ?? this.tagSnapshots,
      releaseSnapshots: releaseSnapshots ?? this.releaseSnapshots,
      artifactPaths: artifactPaths ?? this.artifactPaths,
      latestFailure: identical(latestFailure, _runStateUnset) ? this.latestFailure : latestFailure as RunStateFailure?,
      completionStatus: completionStatus ?? this.completionStatus,
      retryCommand: retryCommand ?? this.retryCommand,
      totalTags: totalTags ?? this.totalTags,
      failedTags: failedTags ?? this.failedTags,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'event_schema_version': eventSchemaVersion,
      'run_id': runId,
      'last_sequence': lastSequence,
      'last_occurred_at': lastOccurredAt,
      'lifecycle': lifecycle.value,
      'active_phase': activePhase.value,
      'source_provider': sourceProvider,
      'target_provider': targetProvider,
      'mode': mode,
      'dry_run': dryRun,
      'skip_tags': skipTags,
      'skip_releases': skipReleases,
      'skip_release_assets': skipReleaseAssets,
      'settings_profile': settingsProfile,
      'preflight': preflightSummary.toMap(),
      'tag_counts': <String, dynamic>{
        'created': tagCreatedCount,
        'would_create': tagWouldCreateCount,
        'skipped_existing': tagSkippedExistingCount,
        'failed': tagFailedCount,
      },
      'release_counts': <String, dynamic>{
        'created': releaseCreatedCount,
        'would_create': releaseWouldCreateCount,
        'skipped_existing': releaseSkippedExistingCount,
        'failed': releaseFailedCount,
      },
      'tags': <String, dynamic>{
        for (final MapEntry<String, RunStateTagSnapshot> entry in tagSnapshots.entries) entry.key: entry.value.toMap(),
      },
      'releases': <String, dynamic>{
        for (final MapEntry<String, RunStateReleaseSnapshot> entry in releaseSnapshots.entries)
          entry.key: entry.value.toMap(),
      },
      'artifacts': artifactPaths.toMap(),
      'latest_failure': latestFailure?.toMap(),
      'completion_status': completionStatus,
      'retry_command': retryCommand,
      'total_tags': totalTags,
      'failed_tags': failedTags,
    };
  }

  int _countTagStatus(String status) {
    return tagSnapshots.values.where((RunStateTagSnapshot snapshot) => snapshot.status == status).length;
  }

  int _countReleaseStatus(String status) {
    return releaseSnapshots.values.where((RunStateReleaseSnapshot snapshot) => snapshot.status == status).length;
  }
}
