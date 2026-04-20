final class DesktopRunFailureSummary {
  const DesktopRunFailureSummary({
    required this.code,
    required this.message,
    required this.retryable,
    required this.phase,
  });

  final String code;
  final String message;
  final bool retryable;
  final String phase;
}
