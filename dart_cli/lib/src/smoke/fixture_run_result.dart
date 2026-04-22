/// Outcome of a fixture operation: create or cleanup.
final class FixtureRunResult {
  const FixtureRunResult({
    required this.status,
    required this.reference,
    this.detail = '',
  });

  /// Human-readable status: `success` or `failed`.
  final String status;

  /// Forge-specific identifier that can be used to look up the run later.
  final String reference;

  /// Additional diagnostic context, empty on success.
  final String detail;

  bool get isSuccess => status == 'success';
}
