/// Validation result for a single migration run directory.
final class ValidationReport {
  const ValidationReport({
    required this.passed,
    this.errors = const <String>[],
  });

  final bool passed;
  final List<String> errors;
}
