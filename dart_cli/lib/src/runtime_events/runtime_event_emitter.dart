import 'runtime_event_sink_dispatch_exception.dart';
import 'runtime_event_envelope.dart';
import 'runtime_event_sink.dart';
import 'runtime_event_sink_failure_mode.dart';
import 'runtime_event_type.dart';
import 'serial_runtime_event_publisher.dart';

typedef RuntimeEventSinkFailureHandler = void Function(RuntimeEventSinkDispatchException failure);

final class RuntimeEventEmitter {
  RuntimeEventEmitter({
    required this.publisher,
    List<RuntimeEventSink> sinks = const <RuntimeEventSink>[],
    RuntimeEventSinkFailureHandler? onSinkFailure,
  })  : _sinks = List<RuntimeEventSink>.unmodifiable(sinks),
        _onSinkFailure = onSinkFailure;

  RuntimeEventEmitter.noop({
    required String runId,
    RuntimeEventTimestampFactory? timestampFactory,
    int initialSequence = 0,
  })  : publisher = SerialRuntimeEventPublisher(
          runId: runId,
          timestampFactory: timestampFactory,
          initialSequence: initialSequence,
        ),
        _sinks = const <RuntimeEventSink>[],
        _onSinkFailure = null;

  final SerialRuntimeEventPublisher publisher;
  final List<RuntimeEventSink> _sinks;
  final RuntimeEventSinkFailureHandler? _onSinkFailure;

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
    _dispatch(envelope, swallowMandatoryFailures: false);
    return envelope;
  }

  RuntimeEventEnvelope emitBestEffort({
    required RuntimeEventType eventType,
    required Map<String, dynamic> payload,
  }) {
    final RuntimeEventEnvelope envelope = publisher.publish(
      eventType: eventType,
      payload: payload,
    );
    _dispatch(envelope, swallowMandatoryFailures: true);
    return envelope;
  }

  void _dispatch(
    RuntimeEventEnvelope envelope, {
    required bool swallowMandatoryFailures,
  }) {
    for (final RuntimeEventSink sink in _dispatchOrder()) {
      try {
        sink.consume(envelope);
      } catch (error, stackTrace) {
        final RuntimeEventSinkDispatchException failure = RuntimeEventSinkDispatchException(
          sinkId: sink.id,
          failureMode: sink.failureMode,
          eventType: envelope.eventType,
          sequence: envelope.sequence,
          cause: error,
          stackTrace: stackTrace,
        );
        if (!swallowMandatoryFailures && sink.failureMode == RuntimeEventSinkFailureMode.mandatory) {
          throw failure;
        }
        _onSinkFailure?.call(failure);
      }
    }
  }

  Iterable<RuntimeEventSink> _dispatchOrder() sync* {
    for (final RuntimeEventSink sink in _sinks) {
      if (sink.failureMode == RuntimeEventSinkFailureMode.mandatory) {
        yield sink;
      }
    }

    for (final RuntimeEventSink sink in _sinks) {
      if (sink.failureMode != RuntimeEventSinkFailureMode.mandatory) {
        yield sink;
      }
    }
  }
}
