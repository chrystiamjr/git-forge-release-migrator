import 'runtime_event_envelope.dart';
import 'runtime_event_sink.dart';
import 'runtime_event_type.dart';
import 'serial_runtime_event_publisher.dart';

final class RuntimeEventEmitter {
  RuntimeEventEmitter({
    required this.publisher,
    List<RuntimeEventSink> sinks = const <RuntimeEventSink>[],
  }) : _sinks = List<RuntimeEventSink>.unmodifiable(sinks);

  RuntimeEventEmitter.noop({
    required String runId,
    RuntimeEventTimestampFactory? timestampFactory,
    int initialSequence = 0,
  })  : publisher = SerialRuntimeEventPublisher(
          runId: runId,
          timestampFactory: timestampFactory,
          initialSequence: initialSequence,
        ),
        _sinks = const <RuntimeEventSink>[];

  final SerialRuntimeEventPublisher publisher;
  final List<RuntimeEventSink> _sinks;

  List<RuntimeEventSink> get sinks => _sinks;

  List<String> get sinkIds => _sinks.map((RuntimeEventSink sink) => sink.id).toList(growable: false);

  RuntimeEventEnvelope emit({
    required RuntimeEventType eventType,
    required Map<String, dynamic> payload,
  }) {
    final RuntimeEventEnvelope envelope = publisher.publish(
      eventType: eventType,
      payload: payload,
    );

    for (final RuntimeEventSink sink in _sinks) {
      sink.consume(envelope);
    }

    return envelope;
  }
}
