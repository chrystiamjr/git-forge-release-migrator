import '../models/runtime_options.dart';
import '../runtime_events/runtime_event_sink.dart';

final class RunRequest {
  const RunRequest({
    required this.options,
    this.runtimeEventSinks = const <RuntimeEventSink>[],
  });

  final RuntimeOptions options;
  final List<RuntimeEventSink> runtimeEventSinks;
}
