/// Phase outcome shown in the final smoke summary line.
final class SmokePhaseOutcome {
  const SmokePhaseOutcome({
    required this.name,
    required this.succeeded,
    this.detail = '',
  });

  final String name;
  final bool succeeded;
  final String detail;
}
