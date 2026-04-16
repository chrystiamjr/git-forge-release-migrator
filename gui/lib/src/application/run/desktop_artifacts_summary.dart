final class DesktopArtifactsSummary {
  const DesktopArtifactsSummary({
    required this.summaryPath,
    required this.failedTagsPath,
    required this.migrationLogPath,
  });

  const DesktopArtifactsSummary.initial() : summaryPath = '', failedTagsPath = '', migrationLogPath = '';

  final String summaryPath;
  final String failedTagsPath;
  final String migrationLogPath;

  bool get hasArtifacts => summaryPath.isNotEmpty || failedTagsPath.isNotEmpty || migrationLogPath.isNotEmpty;

  DesktopArtifactsSummary copyWith({String? summaryPath, String? failedTagsPath, String? migrationLogPath}) {
    return DesktopArtifactsSummary(
      summaryPath: summaryPath ?? this.summaryPath,
      failedTagsPath: failedTagsPath ?? this.failedTagsPath,
      migrationLogPath: migrationLogPath ?? this.migrationLogPath,
    );
  }
}
