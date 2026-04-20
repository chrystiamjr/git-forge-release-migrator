final class DesktopRunStartRequest {
  const DesktopRunStartRequest({
    required this.sourceProvider,
    required this.sourceUrl,
    required this.sourceToken,
    required this.targetProvider,
    required this.targetUrl,
    required this.targetToken,
    this.settingsProfile = '',
    this.fromTag = '',
    this.toTag = '',
    this.skipTagMigration = false,
    this.skipReleaseMigration = false,
    this.skipReleaseAssetMigration = false,
    this.dryRun = false,
    this.workdir = '',
    this.logFile = '',
    this.downloadWorkers = 4,
    this.releaseWorkers = 1,
  });

  final String sourceProvider;
  final String sourceUrl;
  final String sourceToken;
  final String targetProvider;
  final String targetUrl;
  final String targetToken;
  final String settingsProfile;
  final String fromTag;
  final String toTag;
  final bool skipTagMigration;
  final bool skipReleaseMigration;
  final bool skipReleaseAssetMigration;
  final bool dryRun;
  final String workdir;
  final String logFile;
  final int downloadWorkers;
  final int releaseWorkers;
}
