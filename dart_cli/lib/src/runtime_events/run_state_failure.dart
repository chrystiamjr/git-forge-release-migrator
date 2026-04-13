final class RunStateFailure {
  const RunStateFailure({
    required this.code,
    required this.message,
    required this.retryable,
    required this.phase,
  });

  final String code;
  final String message;
  final bool retryable;
  final String phase;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'code': code,
      'message': message,
      'retryable': retryable,
      'phase': phase,
    };
  }
}
