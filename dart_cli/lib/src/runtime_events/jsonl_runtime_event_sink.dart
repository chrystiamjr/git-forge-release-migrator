import 'dart:convert';
import 'dart:io';

import 'runtime_event_envelope.dart';
import 'runtime_event_sink.dart';

final class JsonlRuntimeEventSink implements RuntimeEventSink {
  JsonlRuntimeEventSink({
    required this.path,
    this.id = 'jsonl',
  });

  @override
  final String id;

  final String path;

  @override
  void consume(RuntimeEventEnvelope envelope) {
    final File file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('${jsonEncode(envelope.toMap())}\n', mode: FileMode.append);
  }
}
