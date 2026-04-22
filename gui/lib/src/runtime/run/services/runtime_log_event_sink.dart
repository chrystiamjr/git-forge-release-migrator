// ignore_for_file: implementation_imports

import 'package:gfrm_dart/src/runtime_events/runtime_event_envelope.dart';
import 'package:gfrm_dart/src/runtime_events/runtime_event_sink.dart';
import 'package:gfrm_dart/src/runtime_events/runtime_event_sink_failure_mode.dart';
import 'package:gfrm_dart/src/runtime_events/runtime_event_type.dart';

final class RuntimeLogEventSink implements RuntimeEventSink {
  RuntimeLogEventSink({required this.onLog});

  final void Function(String line) onLog;

  @override
  String get id => 'gui-log-stream';

  @override
  RuntimeEventSinkFailureMode get failureMode => RuntimeEventSinkFailureMode.optional;

  @override
  void consume(RuntimeEventEnvelope envelope) {
    final String? line = _format(envelope);
    if (line != null) {
      onLog(line);
    }
  }

  String? _format(RuntimeEventEnvelope envelope) {
    final String ts = envelope.occurredAt;
    final Map<String, dynamic> p = envelope.payload;
    final RuntimeEventType? type = RuntimeEventType.tryParse(envelope.eventType);

    switch (type) {
      case RuntimeEventType.runStarted:
        return '$ts [INFO] Run started (${p['source_provider']} → ${p['target_provider']})';
      case RuntimeEventType.preflightCompleted:
        return '$ts [INFO] Preflight completed: ${p['status']} (${p['check_count'] ?? 0} checks)';
      case RuntimeEventType.tagMigrated:
        return '$ts [INFO] Tag ${p['tag']}: ${p['status']}${_suffix(p)}';
      case RuntimeEventType.releaseMigrated:
        return '$ts [INFO] Release ${p['tag']}: ${p['status']}${_suffix(p)}';
      case RuntimeEventType.artifactWritten:
        return '$ts [INFO] Artifact written: ${p['artifact_type']} → ${p['path']}';
      case RuntimeEventType.runCompleted:
        return '$ts [INFO] Run completed: ${p['status']}';
      case RuntimeEventType.runFailed:
        return '$ts [ERROR] ${p['message']} (code: ${p['code']})';
      case null:
        return null;
    }
  }

  String _suffix(Map<String, dynamic> p) {
    final dynamic msg = p['message'];
    return msg != null && msg.toString().isNotEmpty ? ' — $msg' : '';
  }
}
