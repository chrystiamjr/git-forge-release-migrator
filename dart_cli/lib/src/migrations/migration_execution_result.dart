import '../core/types/phase.dart';

final class MigrationExecutionResult {
  const MigrationExecutionResult({
    required this.tagCounts,
    required this.releaseCounts,
  });

  final TagMigrationCounts tagCounts;
  final ReleaseMigrationCounts releaseCounts;
}
