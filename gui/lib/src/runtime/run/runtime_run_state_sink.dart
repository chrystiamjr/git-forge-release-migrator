// ignore_for_file: implementation_imports

import 'package:gfrm_dart/src/runtime_events/run_state.dart';
import 'package:gfrm_dart/src/runtime_events/run_state_runtime_event_sink.dart';
import 'package:gfrm_dart/src/runtime_events/runtime_event_envelope.dart';
import 'package:gfrm_dart/src/runtime_events/runtime_event_sink.dart';
import 'package:gfrm_dart/src/runtime_events/runtime_event_sink_failure_mode.dart';

final class RuntimeRunStateSink implements RuntimeEventSink {
  RuntimeRunStateSink({required this.onState});

  final void Function(RunState state) onState;
  final RunStateRuntimeEventSink _delegate = RunStateRuntimeEventSink();

  @override
  String get id => 'gui-run-state-stream';

  @override
  RuntimeEventSinkFailureMode get failureMode => RuntimeEventSinkFailureMode.optional;

  @override
  void consume(RuntimeEventEnvelope envelope) {
    _delegate.consume(envelope);
    onState(_delegate.state);
  }
}
