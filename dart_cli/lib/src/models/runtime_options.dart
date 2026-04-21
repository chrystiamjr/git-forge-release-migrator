import 'dart:io';

import '../core/time.dart';

const String defaultSourceTokenEnv = 'GFRM_SOURCE_TOKEN';
const String defaultTargetTokenEnv = 'GFRM_TARGET_TOKEN';

const String commandMigrate = 'migrate';
const String commandResume = 'resume';
const String commandDemo = 'demo';
const String commandSetup = 'setup';
const String commandSettings = 'settings';
const String publicCommandName = 'gfrm';

class RuntimeOptions {
  RuntimeOptions({
    required this.commandName,
    required this.sourceProvider,
    required this.sourceUrl,
    required this.sourceToken,
    required this.targetProvider,
    required this.targetUrl,
    required this.targetToken,
    required this.migrationOrder,
    required this.skipTagMigration,
    required this.skipReleaseMigration,
    required this.skipReleaseAssetMigration,
    required this.fromTag,
    required this.toTag,
    required this.dryRun,
    required this.nonInteractive,
    required this.workdir,
    required this.logFile,
    required this.loadSession,
    required this.saveSession,
    required this.resumeSession,
    required this.sessionFile,
    required this.sessionTokenMode,
    required this.sessionSourceTokenEnv,
    required this.sessionTargetTokenEnv,
    required this.settingsProfile,
    required this.downloadWorkers,
    required this.releaseWorkers,
    required this.checkpointFile,
    required this.tagsFile,
    required this.noBanner,
    required this.quiet,
    required this.jsonOutput,
    required this.progressBar,
    required this.demoMode,
    required this.demoReleases,
    required this.demoSleepSeconds,
  });

  final String commandName;
  final String sourceProvider;
  final String sourceUrl;
  final String sourceToken;
  final String targetProvider;
  final String targetUrl;
  final String targetToken;
  final String migrationOrder;
  final bool skipTagMigration;
  final bool skipReleaseMigration;
  final bool skipReleaseAssetMigration;
  final String fromTag;
  final String toTag;
  final bool dryRun;
  final bool nonInteractive;
  final String workdir;
  final String logFile;
  final bool loadSession;
  final bool saveSession;
  final bool resumeSession;
  final String sessionFile;
  final String sessionTokenMode;
  final String sessionSourceTokenEnv;
  final String sessionTargetTokenEnv;
  final String settingsProfile;
  final int downloadWorkers;
  final int releaseWorkers;
  final String checkpointFile;
  final String tagsFile;
  final bool noBanner;
  final bool quiet;
  final bool jsonOutput;
  final bool progressBar;
  final bool demoMode;
  final int demoReleases;
  final double demoSleepSeconds;

  RuntimeOptions copyWith({
    String? commandName,
    String? sourceProvider,
    String? sourceUrl,
    String? sourceToken,
    String? targetProvider,
    String? targetUrl,
    String? targetToken,
    String? migrationOrder,
    bool? skipTagMigration,
    bool? skipReleaseMigration,
    bool? skipReleaseAssetMigration,
    String? fromTag,
    String? toTag,
    bool? dryRun,
    bool? nonInteractive,
    String? workdir,
    String? logFile,
    bool? loadSession,
    bool? saveSession,
    bool? resumeSession,
    String? sessionFile,
    String? sessionTokenMode,
    String? sessionSourceTokenEnv,
    String? sessionTargetTokenEnv,
    String? settingsProfile,
    int? downloadWorkers,
    int? releaseWorkers,
    String? checkpointFile,
    String? tagsFile,
    bool? noBanner,
    bool? quiet,
    bool? jsonOutput,
    bool? progressBar,
    bool? demoMode,
    int? demoReleases,
    double? demoSleepSeconds,
  }) {
    return RuntimeOptions(
      commandName: commandName ?? this.commandName,
      sourceProvider: sourceProvider ?? this.sourceProvider,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      sourceToken: sourceToken ?? this.sourceToken,
      targetProvider: targetProvider ?? this.targetProvider,
      targetUrl: targetUrl ?? this.targetUrl,
      targetToken: targetToken ?? this.targetToken,
      migrationOrder: migrationOrder ?? this.migrationOrder,
      skipTagMigration: skipTagMigration ?? this.skipTagMigration,
      skipReleaseMigration: skipReleaseMigration ?? this.skipReleaseMigration,
      skipReleaseAssetMigration: skipReleaseAssetMigration ?? this.skipReleaseAssetMigration,
      fromTag: fromTag ?? this.fromTag,
      toTag: toTag ?? this.toTag,
      dryRun: dryRun ?? this.dryRun,
      nonInteractive: nonInteractive ?? this.nonInteractive,
      workdir: workdir ?? this.workdir,
      logFile: logFile ?? this.logFile,
      loadSession: loadSession ?? this.loadSession,
      saveSession: saveSession ?? this.saveSession,
      resumeSession: resumeSession ?? this.resumeSession,
      sessionFile: sessionFile ?? this.sessionFile,
      sessionTokenMode: sessionTokenMode ?? this.sessionTokenMode,
      sessionSourceTokenEnv: sessionSourceTokenEnv ?? this.sessionSourceTokenEnv,
      sessionTargetTokenEnv: sessionTargetTokenEnv ?? this.sessionTargetTokenEnv,
      settingsProfile: settingsProfile ?? this.settingsProfile,
      downloadWorkers: downloadWorkers ?? this.downloadWorkers,
      releaseWorkers: releaseWorkers ?? this.releaseWorkers,
      checkpointFile: checkpointFile ?? this.checkpointFile,
      tagsFile: tagsFile ?? this.tagsFile,
      noBanner: noBanner ?? this.noBanner,
      quiet: quiet ?? this.quiet,
      jsonOutput: jsonOutput ?? this.jsonOutput,
      progressBar: progressBar ?? this.progressBar,
      demoMode: demoMode ?? this.demoMode,
      demoReleases: demoReleases ?? this.demoReleases,
      demoSleepSeconds: demoSleepSeconds ?? this.demoSleepSeconds,
    );
  }

  String effectiveWorkdir() {
    if (workdir.isNotEmpty) {
      return workdir;
    }

    return '${Directory.current.path}/migration-results';
  }

  String effectiveSessionFile() {
    if (sessionFile.isNotEmpty) {
      return sessionFile;
    }

    return '${Directory.current.path}/sessions/last-session.json';
  }

  String effectiveCheckpointFile() {
    if (checkpointFile.isNotEmpty) {
      return checkpointFile;
    }

    return '${effectiveWorkdir()}/checkpoints/state.jsonl';
  }

  String sessionSourceEnvName() {
    final String normalized = sessionSourceTokenEnv.trim();
    return normalized.isEmpty ? defaultSourceTokenEnv : normalized;
  }

  String sessionTargetEnvName() {
    final String normalized = sessionTargetTokenEnv.trim();
    return normalized.isEmpty ? defaultTargetTokenEnv : normalized;
  }

  Map<String, dynamic> toSessionPayload() {
    final Map<String, dynamic> payload = <String, dynamic>{
      'source_provider': sourceProvider,
      'source_url': sourceUrl,
      'target_provider': targetProvider,
      'target_url': targetUrl,
      'from_tag': fromTag,
      'to_tag': toTag,
      'skip_tag_migration': skipTagMigration,
      'skip_release_migration': skipReleaseMigration,
      'skip_release_asset_migration': skipReleaseAssetMigration,
      'download_workers': downloadWorkers,
      'release_workers': releaseWorkers,
      'saved_at': TimeUtils.utcTimestamp(),
      'session_token_mode': sessionTokenMode,
      'settings_profile': settingsProfile,
    };

    if (sessionTokenMode == 'plain') {
      payload['source_token'] = sourceToken;
      payload['target_token'] = targetToken;
      return payload;
    }

    payload['source_token_env'] = sessionSourceEnvName();
    payload['target_token_env'] = sessionTargetEnvName();
    return payload;
  }
}
