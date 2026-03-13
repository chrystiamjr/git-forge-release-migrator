final class RunFailure {
  const RunFailure({
    required this.scope,
    required this.code,
    required this.message,
    required this.retryable,
    this.tag,
    this.phase,
  });

  static const String scopeValidation = 'validation';
  static const String scopeExecution = 'execution';
  static const String scopeArtifactFinalization = 'artifact_finalization';

  final String scope;
  final String code;
  final String message;
  final bool retryable;
  final String? tag;
  final String? phase;
}
