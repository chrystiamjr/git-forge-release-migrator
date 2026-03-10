class ExistingReleaseInfo {
  const ExistingReleaseInfo({
    required this.exists,
    required this.shouldRetry,
    required this.reason,
  });

  final bool exists;
  final bool shouldRetry;
  final String reason;
}
