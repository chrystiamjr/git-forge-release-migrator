import 'dart:io';

import '../core/adapters/provider_adapter.dart';
import 'runtime_options.dart';

class MigrationContext {
  MigrationContext({
    required this.sourceRef,
    required this.targetRef,
    required this.source,
    required this.target,
    required this.options,
    required this.logPath,
    required this.workdir,
    required this.checkpointPath,
    required this.checkpointSignature,
    required this.checkpointState,
    required this.selectedTags,
    required this.targetTags,
    required this.targetReleaseTags,
    required this.failedTags,
    required this.releases,
  });

  final ProviderRef sourceRef;
  final ProviderRef targetRef;
  final ProviderAdapter source;
  final ProviderAdapter target;
  final RuntimeOptions options;
  final String logPath;
  final Directory workdir;
  final String checkpointPath;
  final String checkpointSignature;
  final Map<String, String> checkpointState;
  final List<String> selectedTags;
  final Set<String> targetTags;
  final Set<String> targetReleaseTags;
  final Set<String> failedTags;
  final List<Map<String, dynamic>> releases;
}
