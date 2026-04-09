import 'runtime_event_envelope.dart';
import 'runtime_event_sink.dart';

typedef RuntimeEventReducer<TState> = TState Function(TState currentState, RuntimeEventEnvelope envelope);

final class ReducerRuntimeEventSink<TState> implements RuntimeEventSink {
  ReducerRuntimeEventSink({
    required this.id,
    required TState initialState,
    required RuntimeEventReducer<TState> reducer,
  })  : _state = initialState,
        _reducer = reducer;

  @override
  final String id;

  final RuntimeEventReducer<TState> _reducer;
  TState _state;

  TState get state => _state;

  @override
  void consume(RuntimeEventEnvelope envelope) {
    _state = _reducer(_state, envelope);
  }
}
