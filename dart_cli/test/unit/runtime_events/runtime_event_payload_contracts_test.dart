import 'package:gfrm_dart/src/runtime_events/runtime_event_payload_contract.dart';
import 'package:gfrm_dart/src/runtime_events/runtime_event_payload_contracts.dart';
import 'package:gfrm_dart/src/runtime_events/runtime_event_type.dart';
import 'package:test/test.dart';

void main() {
  group('runtimeEventPayloadContracts', () {
    test('defines one payload contract for every canonical event type', () {
      expect(
        runtimeEventPayloadContracts.map((RuntimeEventPayloadContract contract) => contract.eventType),
        RuntimeEventType.values,
      );
    });

    test('keeps payload field names provider-agnostic and secret-free', () {
      const List<String> forbiddenFragments = <String>[
        'token',
        'secret',
        'password',
        'authorization',
      ];

      for (final RuntimeEventPayloadContract contract in runtimeEventPayloadContracts) {
        for (final String field in contract.allowedFields) {
          expect(field, isNot(contains('_provider_token')));
          for (final String fragment in forbiddenFragments) {
            expect(field.toLowerCase(), isNot(contains(fragment)));
          }
        }
      }
    });

    test('serializes representative payload contract shape', () {
      expect(findRuntimeEventPayloadContract(RuntimeEventType.artifactWritten)?.toMap(), <String, dynamic>{
        'event_type': 'artifact_written',
        'required_fields': <String>[
          'artifact_type',
          'path',
        ],
        'optional_fields': <String>[
          'schema_version',
        ],
      });
    });

    test('validates required and unexpected payload fields', () {
      final RuntimeEventPayloadContract contract = findRuntimeEventPayloadContract(RuntimeEventType.tagMigrated)!;

      expect(contract.accepts(<String, dynamic>{'tag': 'v1.0.0', 'status': 'created'}), isTrue);
      expect(contract.missingRequiredFields(<String, dynamic>{'tag': 'v1.0.0'}), <String>['status']);
      expect(
        contract.unexpectedFields(<String, dynamic>{
          'tag': 'v1.0.0',
          'status': 'created',
          'raw_token': 'secret',
        }),
        <String>['raw_token'],
      );
    });
  });
}
