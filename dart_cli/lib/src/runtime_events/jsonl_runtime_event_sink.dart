import 'dart:convert';
import 'dart:io';

import 'runtime_event_envelope.dart';
import 'runtime_event_sink.dart';
import 'runtime_event_sink_failure_mode.dart';

final class JsonlRuntimeEventSink implements RuntimeEventSink {
  JsonlRuntimeEventSink({
    required this.path,
    this.id = 'jsonl',
    this.failureMode = RuntimeEventSinkFailureMode.optional,
  });

  @override
  final String id;

  @override
  final RuntimeEventSinkFailureMode failureMode;

  final String path;

  @override
  void consume(RuntimeEventEnvelope envelope) {
    final File file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('${jsonEncode(envelope.toMap())}\n', mode: FileMode.append);
  }
}
