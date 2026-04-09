import '../core/time.dart';
import 'runtime_event_envelope.dart';
import 'runtime_event_type.dart';

typedef RuntimeEventTimestampFactory = String Function();

final class SerialRuntimeEventPublisher {
  SerialRuntimeEventPublisher({
    required this.runId,
    RuntimeEventTimestampFactory? timestampFactory,
    int initialSequence = 0,
  })  : _timestampFactory = timestampFactory ?? TimeUtils.utcTimestamp,
        _lastSequence = initialSequence;

  final String runId;
  final RuntimeEventTimestampFactory _timestampFactory;

  int _lastSequence;

  int get lastSequence => _lastSequence;

  RuntimeEventEnvelope publish({
    required RuntimeEventType eventType,
    required Map<String, dynamic> payload,
  }) {
    _lastSequence += 1;

    return RuntimeEventEnvelope(
      runId: runId,
      sequence: _lastSequence,
      occurredAt: _timestampFactory(),
      eventType: eventType.value,
      payload: Map<String, dynamic>.from(payload),
    );
  }
}
