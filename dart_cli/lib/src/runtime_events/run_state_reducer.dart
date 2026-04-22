import 'run_state.dart';
import 'run_state_artifact_paths.dart';
import 'run_state_failure.dart';
import 'run_state_lifecycle.dart';
import 'run_state_phase.dart';
import 'run_state_preflight_summary.dart';
import 'run_state_release_snapshot.dart';
import 'run_state_tag_snapshot.dart';
import 'runtime_event_envelope.dart';
import 'runtime_event_type.dart';

RunState reduceRunState(RunState currentState, RuntimeEventEnvelope envelope) {
  final RuntimeEventType? eventType = RuntimeEventType.tryParse(envelope.eventType);
  final RunState stateWithEnvelope = currentState.copyWith(
    eventSchemaVersion: envelope.schemaVersion,
    runId: envelope.runId,
    lastSequence: envelope.sequence,
    lastOccurredAt: envelope.occurredAt,
  );

  switch (eventType) {
    case RuntimeEventType.runStarted:
      return _reduceRunStarted(stateWithEnvelope, envelope);
    case RuntimeEventType.preflightCompleted:
      return _reducePreflightCompleted(stateWithEnvelope, envelope);
    case RuntimeEventType.tagMigrated:
      return _reduceTagMigrated(stateWithEnvelope, envelope);
    case RuntimeEventType.releaseMigrated:
      return _reduceReleaseMigrated(stateWithEnvelope, envelope);
    case RuntimeEventType.artifactWritten:
      return _reduceArtifactWritten(stateWithEnvelope, envelope);
    case RuntimeEventType.runCompleted:
      return _reduceRunCompleted(stateWithEnvelope, envelope);
    case RuntimeEventType.runFailed:
      return _reduceRunFailed(stateWithEnvelope, envelope);
    case null:
      return stateWithEnvelope;
  }
}

RunState _reduceRunStarted(RunState currentState, RuntimeEventEnvelope envelope) {
  final Map<String, dynamic> payload = envelope.payload;
  return const RunState.initial().copyWith(
    eventSchemaVersion: envelope.schemaVersion,
    runId: envelope.runId,
    lastSequence: envelope.sequence,
    lastOccurredAt: envelope.occurredAt,
    lifecycle: RunStateLifecycle.running,
    activePhase: RunStatePhase.preflight,
    sourceProvider: _readString(payload, 'source_provider'),
    targetProvider: _readString(payload, 'target_provider'),
    mode: _readString(payload, 'mode'),
    dryRun: _readBool(payload, 'dry_run'),
    skipTags: _readBool(payload, 'skip_tags'),
    skipReleases: _readBool(payload, 'skip_releases'),
    skipReleaseAssets: _readBool(payload, 'skip_release_assets'),
    settingsProfile: _readString(payload, 'settings_profile'),
  );
}

RunState _reducePreflightCompleted(RunState currentState, RuntimeEventEnvelope envelope) {
  final Map<String, dynamic> payload = envelope.payload;
  return currentState.copyWith(
    activePhase: RunStatePhase.preflight,
    preflightSummary: RunStatePreflightSummary(
      status: _readString(payload, 'status'),
      checkCount: _readInt(payload, 'check_count'),
      blockingCount: _readInt(payload, 'blocking_count'),
      warningCount: _readInt(payload, 'warning_count'),
    ),
    totalTags: _readInt(payload, 'total_tags', fallback: currentState.totalTags),
  );
}

RunState _reduceTagMigrated(RunState currentState, RuntimeEventEnvelope envelope) {
  final Map<String, dynamic> payload = envelope.payload;
  final String tag = _readString(payload, 'tag');
  return currentState.copyWith(
    activePhase: RunStatePhase.tags,
    tagSnapshots: <String, RunStateTagSnapshot>{
      ...currentState.tagSnapshots,
      tag: RunStateTagSnapshot(
        tag: tag,
        status: _readString(payload, 'status'),
        message: _readString(payload, 'message'),
      ),
    },
  );
}

RunState _reduceReleaseMigrated(RunState currentState, RuntimeEventEnvelope envelope) {
  final Map<String, dynamic> payload = envelope.payload;
  final String tag = _readString(payload, 'tag');
  return currentState.copyWith(
    activePhase: RunStatePhase.releases,
    releaseSnapshots: <String, RunStateReleaseSnapshot>{
      ...currentState.releaseSnapshots,
      tag: RunStateReleaseSnapshot(
        tag: tag,
        status: _readString(payload, 'status'),
        assetCount: _readInt(payload, 'asset_count'),
        message: _readString(payload, 'message'),
      ),
    },
  );
}

RunState _reduceArtifactWritten(RunState currentState, RuntimeEventEnvelope envelope) {
  final Map<String, dynamic> payload = envelope.payload;
  return currentState.copyWith(
    activePhase: RunStatePhase.artifactFinalization,
    artifactPaths: currentState.artifactPaths.withPath(
      _readString(payload, 'artifact_type'),
      _readString(payload, 'path'),
    ),
  );
}

RunState _reduceRunCompleted(RunState currentState, RuntimeEventEnvelope envelope) {
  final Map<String, dynamic> payload = envelope.payload;
  RunStateArtifactPaths artifactPaths = currentState.artifactPaths;
  final String summaryPath = _readString(payload, 'summary_path');
  final String failedTagsPath = _readString(payload, 'failed_tags_path');
  if (summaryPath.isNotEmpty) {
    artifactPaths = artifactPaths.withPath('summary', summaryPath);
  }
  if (failedTagsPath.isNotEmpty) {
    artifactPaths = artifactPaths.withPath('failed_tags', failedTagsPath);
  }

  return currentState.copyWith(
    lifecycle: RunStateLifecycle.completed,
    activePhase: RunStatePhase.completed,
    artifactPaths: artifactPaths,
    completionStatus: _readString(payload, 'status'),
    retryCommand: _readString(payload, 'retry_command'),
    totalTags: _readInt(payload, 'total_tags'),
    failedTags: _readInt(payload, 'failed_tags'),
  );
}

RunState _reduceRunFailed(RunState currentState, RuntimeEventEnvelope envelope) {
  final Map<String, dynamic> payload = envelope.payload;
  final String failurePhase = _readString(payload, 'phase');
  return currentState.copyWith(
    lifecycle: RunStateLifecycle.failed,
    activePhase: _resolveFailurePhase(failurePhase, currentState.activePhase),
    latestFailure: RunStateFailure(
      code: _readString(payload, 'code'),
      message: _readString(payload, 'message'),
      retryable: _readBool(payload, 'retryable'),
      phase: failurePhase,
    ),
  );
}

RunStatePhase _resolveFailurePhase(String phase, RunStatePhase currentPhase) {
  switch (phase) {
    case 'preflight':
    case 'validation':
      return RunStatePhase.preflight;
    case 'artifact_finalization':
      return RunStatePhase.artifactFinalization;
    case 'execution':
    case 'runtime_event_sink':
      return currentPhase == RunStatePhase.tags || currentPhase == RunStatePhase.releases
          ? currentPhase
          : RunStatePhase.execution;
    default:
      return currentPhase;
  }
}

String _readString(Map<String, dynamic> payload, String key) {
  return (payload[key] ?? '').toString();
}

int _readInt(Map<String, dynamic> payload, String key, {int fallback = 0}) {
  final dynamic value = payload[key];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }

  return int.tryParse((value ?? '').toString()) ?? fallback;
}

bool _readBool(Map<String, dynamic> payload, String key) {
  final dynamic value = payload[key];
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }

  final String normalized = (value ?? '').toString().toLowerCase();
  return normalized == 'true' || normalized == '1';
}
