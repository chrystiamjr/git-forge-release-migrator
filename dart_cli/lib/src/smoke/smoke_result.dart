import 'smoke_phase_outcome.dart';

final class SmokeResult {
  const SmokeResult({required this.exitCode, required this.phases});

  final int exitCode;
  final List<SmokePhaseOutcome> phases;
}
