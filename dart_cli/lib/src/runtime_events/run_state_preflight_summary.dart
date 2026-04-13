final class RunStatePreflightSummary {
  const RunStatePreflightSummary({
    required this.status,
    required this.checkCount,
    required this.blockingCount,
    required this.warningCount,
  });

  const RunStatePreflightSummary.initial()
      : status = '',
        checkCount = 0,
        blockingCount = 0,
        warningCount = 0;

  final String status;
  final int checkCount;
  final int blockingCount;
  final int warningCount;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'status': status,
      'check_count': checkCount,
      'blocking_count': blockingCount,
      'warning_count': warningCount,
    };
  }
}
