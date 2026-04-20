import 'runtime_event_payload_contract.dart';
import 'runtime_event_type.dart';

const List<RuntimeEventPayloadContract> runtimeEventPayloadContracts = <RuntimeEventPayloadContract>[
  RuntimeEventPayloadContract(
    eventType: RuntimeEventType.runStarted,
    requiredFields: <String>[
      'source_provider',
      'target_provider',
      'mode',
    ],
    optionalFields: <String>[
      'dry_run',
      'skip_tags',
      'skip_releases',
      'skip_release_assets',
      'settings_profile',
    ],
  ),
  RuntimeEventPayloadContract(
    eventType: RuntimeEventType.preflightCompleted,
    requiredFields: <String>[
      'status',
    ],
    optionalFields: <String>[
      'check_count',
      'blocking_count',
      'warning_count',
    ],
  ),
  RuntimeEventPayloadContract(
    eventType: RuntimeEventType.tagMigrated,
    requiredFields: <String>[
      'tag',
      'status',
    ],
    optionalFields: <String>[
      'message',
    ],
  ),
  RuntimeEventPayloadContract(
    eventType: RuntimeEventType.releaseMigrated,
    requiredFields: <String>[
      'tag',
      'status',
    ],
    optionalFields: <String>[
      'asset_count',
      'message',
    ],
  ),
  RuntimeEventPayloadContract(
    eventType: RuntimeEventType.artifactWritten,
    requiredFields: <String>[
      'artifact_type',
      'path',
    ],
    optionalFields: <String>[
      'schema_version',
    ],
  ),
  RuntimeEventPayloadContract(
    eventType: RuntimeEventType.runCompleted,
    requiredFields: <String>[
      'status',
    ],
    optionalFields: <String>[
      'summary_path',
      'failed_tags_path',
      'retry_command',
      'total_tags',
      'failed_tags',
    ],
  ),
  RuntimeEventPayloadContract(
    eventType: RuntimeEventType.runFailed,
    requiredFields: <String>[
      'code',
      'message',
    ],
    optionalFields: <String>[
      'phase',
      'retryable',
    ],
  ),
];

RuntimeEventPayloadContract? findRuntimeEventPayloadContract(RuntimeEventType eventType) {
  for (final RuntimeEventPayloadContract contract in runtimeEventPayloadContracts) {
    if (contract.eventType == eventType) {
      return contract;
    }
  }

  return null;
}
