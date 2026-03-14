const int runtimeEventSchemaVersion = 1;

class RuntimeEventEnvelope {
  RuntimeEventEnvelope({
    this.schemaVersion = runtimeEventSchemaVersion,
    required this.runId,
    required this.sequence,
    required this.occurredAt,
    required this.eventType,
    required this.payload,
  });

  final int schemaVersion;
  final String runId;
  final int sequence;
  final String occurredAt;
  final String eventType;
  final Map<String, dynamic> payload;

  factory RuntimeEventEnvelope.fromMap(Map<String, dynamic> raw) {
    final dynamic payloadRaw = raw['payload'];
    final Map<String, dynamic> normalizedPayload =
        payloadRaw is Map ? Map<String, dynamic>.from(payloadRaw) : <String, dynamic>{};

    return RuntimeEventEnvelope(
      schemaVersion: _toInt(raw['schema_version'], fallback: runtimeEventSchemaVersion),
      runId: (raw['run_id'] ?? '').toString(),
      sequence: _toInt(raw['sequence']),
      occurredAt: (raw['occurred_at'] ?? '').toString(),
      eventType: (raw['event_type'] ?? '').toString(),
      payload: normalizedPayload,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'schema_version': schemaVersion,
      'run_id': runId,
      'sequence': sequence,
      'occurred_at': occurredAt,
      'event_type': eventType,
      'payload': payload,
    };
  }

  static int _toInt(dynamic value, {int fallback = 0}) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse((value ?? '').toString()) ?? fallback;
  }
}
