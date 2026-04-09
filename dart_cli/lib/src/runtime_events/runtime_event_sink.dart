import 'runtime_event_envelope.dart';

abstract interface class RuntimeEventSink {
  String get id;

  void consume(RuntimeEventEnvelope envelope);
}
