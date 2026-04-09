import 'runtime_event_envelope.dart';
import 'runtime_event_sink_failure_mode.dart';

abstract interface class RuntimeEventSink {
  String get id;
  RuntimeEventSinkFailureMode get failureMode;

  void consume(RuntimeEventEnvelope envelope);
}
