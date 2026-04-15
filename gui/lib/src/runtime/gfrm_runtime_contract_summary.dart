// ignore_for_file: implementation_imports

import 'package:gfrm_dart/src/runtime_events/run_state.dart';
import 'package:gfrm_dart/src/runtime_events/run_state_lifecycle.dart';
import 'package:gfrm_dart/src/runtime_events/run_state_phase.dart';

final class GfrmRuntimeContractSummary {
  const GfrmRuntimeContractSummary._();

  static const RunState initialState = RunState.initial();

  static String get lifecycleLabel => initialState.lifecycle.value;

  static String get phaseLabel => initialState.activePhase.value;

  static int get lifecycleCount => RunStateLifecycle.values.length;

  static int get phaseCount => RunStatePhase.values.length;
}
