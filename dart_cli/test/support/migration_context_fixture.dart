import 'dart:io';

import 'package:gfrm_dart/src/core/adapters/provider_adapter.dart';
import 'package:gfrm_dart/src/models/migration_context.dart';
import 'package:gfrm_dart/src/runtime_events/runtime_event_emitter.dart';

import 'runtime_options_fixture.dart';

MigrationContext buildMigrationContext(
  Directory temp,
  ProviderAdapter source,
  ProviderAdapter target, {
  List<String> selectedTags = const <String>[],
  Set<String> targetTags = const <String>{},
  Set<String> targetReleaseTags = const <String>{},
  List<Map<String, dynamic>> releases = const <Map<String, dynamic>>[],
  Map<String, String> checkpointState = const <String, String>{},
  bool skipTagMigration = false,
  bool dryRun = false,
  int releaseWorkers = 1,
}) {
  final ProviderRef sourceRef = source.parseUrl('https://github.com/acme/source');
  final ProviderRef targetRef = target.parseUrl('https://gitlab.com/acme/target');

  return MigrationContext(
    sourceRef: sourceRef,
    targetRef: targetRef,
    source: source,
    target: target,
    options: buildRuntimeOptions(
      skipTagMigration: skipTagMigration,
      dryRun: dryRun,
      workdir: temp.path,
      logFile: '${temp.path}/migration.jsonl',
      releaseWorkers: releaseWorkers,
    ),
    logPath: '${temp.path}/migration.jsonl',
    workdir: temp,
    checkpointPath: '${temp.path}/checkpoint.jsonl',
    checkpointSignature: 'test-sig',
    checkpointState: Map<String, String>.from(checkpointState),
    selectedTags: List<String>.from(selectedTags),
    targetTags: Set<String>.from(targetTags),
    targetReleaseTags: Set<String>.from(targetReleaseTags),
    failedTags: <String>{},
    releases: List<Map<String, dynamic>>.from(releases),
    runtimeEventEmitter: RuntimeEventEmitter.noop(
      runId: temp.path.split(Platform.pathSeparator).last,
    ),
  );
}
