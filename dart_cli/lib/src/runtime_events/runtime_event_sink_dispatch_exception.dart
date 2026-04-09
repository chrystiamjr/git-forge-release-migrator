import 'runtime_event_sink_failure_mode.dart';

final class RuntimeEventSinkDispatchException implements Exception {
  const RuntimeEventSinkDispatchException({
    required this.sinkId,
    required this.failureMode,
    required this.eventType,
    required this.sequence,
    required this.cause,
    required this.stackTrace,
  });

  final String sinkId;
  final RuntimeEventSinkFailureMode failureMode;
  final String eventType;
  final int sequence;
  final Object cause;
  final StackTrace stackTrace;

  @override
  String toString() {
    return 'Runtime event sink "$sinkId" (${failureMode.name}) failed while consuming '
        '"$eventType" at sequence $sequence: $cause';
  }
}
