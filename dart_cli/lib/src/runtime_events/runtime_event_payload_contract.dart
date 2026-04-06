import 'runtime_event_type.dart';

final class RuntimeEventPayloadContract {
  const RuntimeEventPayloadContract({
    required this.eventType,
    required this.requiredFields,
    this.optionalFields = const <String>[],
  });

  final RuntimeEventType eventType;
  final List<String> requiredFields;
  final List<String> optionalFields;

  List<String> get allowedFields {
    return <String>[...requiredFields, ...optionalFields];
  }

  bool accepts(Map<String, dynamic> payload) {
    return missingRequiredFields(payload).isEmpty && unexpectedFields(payload).isEmpty;
  }

  List<String> missingRequiredFields(Map<String, dynamic> payload) {
    return requiredFields.where((String field) => !payload.containsKey(field)).toList(growable: false);
  }

  List<String> unexpectedFields(Map<String, dynamic> payload) {
    final Set<String> knownFields = allowedFields.toSet();

    return payload.keys.where((String field) => !knownFields.contains(field)).toList(growable: false);
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'event_type': eventType.value,
      'required_fields': requiredFields,
      'optional_fields': optionalFields,
    };
  }
}
