enum RuntimeEventType {
  runStarted('run_started'),
  preflightCompleted('preflight_completed'),
  tagMigrated('tag_migrated'),
  releaseMigrated('release_migrated'),
  artifactWritten('artifact_written'),
  runCompleted('run_completed'),
  runFailed('run_failed');

  const RuntimeEventType(this.value);

  final String value;

  static RuntimeEventType? tryParse(String value) {
    for (final RuntimeEventType type in RuntimeEventType.values) {
      if (type.value == value) {
        return type;
      }
    }

    return null;
  }
}
