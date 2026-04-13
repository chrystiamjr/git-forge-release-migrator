final class RunStateArtifactPaths {
  const RunStateArtifactPaths({
    required this.pathsByType,
  });

  const RunStateArtifactPaths.initial() : pathsByType = const <String, String>{};

  final Map<String, String> pathsByType;

  String get migrationLogPath => pathsByType['migration_log'] ?? '';
  String get failedTagsPath => pathsByType['failed_tags'] ?? '';
  String get summaryPath => pathsByType['summary'] ?? '';

  RunStateArtifactPaths withPath(String artifactType, String path) {
    return RunStateArtifactPaths(
      pathsByType: <String, String>{
        ...pathsByType,
        artifactType: path,
      },
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'migration_log_path': migrationLogPath,
      'failed_tags_path': failedTagsPath,
      'summary_path': summaryPath,
      'paths_by_type': <String, dynamic>{
        for (final MapEntry<String, String> entry in pathsByType.entries) entry.key: entry.value,
      },
    };
  }
}
