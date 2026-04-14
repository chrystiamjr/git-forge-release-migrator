import 'run_state.dart';
import 'run_state_reducer.dart';
import 'runtime_event_envelope.dart';
import 'runtime_event_sink.dart';
import 'runtime_event_sink_failure_mode.dart';

final class RunStateRuntimeEventSink implements RuntimeEventSink {
  RunStateRuntimeEventSink({
    this.id = 'run-state',
    this.failureMode = RuntimeEventSinkFailureMode.optional,
    RunState initialState = const RunState.initial(),
  }) : _state = initialState;

  @override
  final String id;

  @override
  final RuntimeEventSinkFailureMode failureMode;

  RunState _state;

  RunState get state => _state;

  @override
  void consume(RuntimeEventEnvelope envelope) {
    _state = reduceRunState(_state, envelope);
  }
}
