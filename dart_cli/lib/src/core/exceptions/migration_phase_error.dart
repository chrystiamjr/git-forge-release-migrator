class MigrationPhaseError implements Exception {
  MigrationPhaseError(this.message);

  final String message;

  @override
  String toString() => message;
}
