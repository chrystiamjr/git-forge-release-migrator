import 'runtime_event_envelope.dart';
import 'runtime_event_sink.dart';

final class InMemoryRuntimeEventSink implements RuntimeEventSink {
  InMemoryRuntimeEventSink({
    this.id = 'in-memory',
  });

  @override
  final String id;

  final List<RuntimeEventEnvelope> _events = <RuntimeEventEnvelope>[];

  List<RuntimeEventEnvelope> get events => List<RuntimeEventEnvelope>.unmodifiable(_events);

  @override
  void consume(RuntimeEventEnvelope envelope) {
    _events.add(RuntimeEventEnvelope.fromMap(envelope.toMap()));
  }
}
