import '../core/logging.dart';
import 'runtime_event_envelope.dart';
import 'runtime_event_sink.dart';
import 'runtime_event_sink_failure_mode.dart';

typedef RuntimeEventConsoleFormatter = String Function(RuntimeEventEnvelope envelope);

final class ConsoleRuntimeEventSink implements RuntimeEventSink {
  ConsoleRuntimeEventSink({
    required this.logger,
    RuntimeEventConsoleFormatter? formatter,
    this.id = 'console',
    this.failureMode = RuntimeEventSinkFailureMode.optional,
  }) : _formatter = formatter ?? _defaultFormatter;

  @override
  final String id;

  @override
  final RuntimeEventSinkFailureMode failureMode;

  final ConsoleLogger logger;
  final RuntimeEventConsoleFormatter _formatter;

  @override
  void consume(RuntimeEventEnvelope envelope) {
    logger.info(_formatter(envelope));
  }

  static String _defaultFormatter(RuntimeEventEnvelope envelope) {
    return '[runtime-event #${envelope.sequence}] ${envelope.eventType}';
  }
}
