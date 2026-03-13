enum PreflightCheckStatus {
  ok,
  warning,
  error,
}

final class PreflightCheck {
  const PreflightCheck({
    required this.status,
    required this.code,
    required this.message,
    this.hint,
    this.field,
  });

  final PreflightCheckStatus status;
  final String code;
  final String message;
  final String? hint;
  final String? field;

  bool get isBlocking => status == PreflightCheckStatus.error;
}
