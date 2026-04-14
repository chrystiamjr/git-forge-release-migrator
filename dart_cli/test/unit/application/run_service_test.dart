import 'dart:convert';
import 'dart:io';

import 'package:gfrm_dart/src/application/preflight_check.dart';
import 'package:gfrm_dart/src/application/preflight_service.dart';
import 'package:gfrm_dart/src/application/run_request.dart';
import 'package:gfrm_dart/src/application/run_failure.dart';
import 'package:gfrm_dart/src/application/run_result.dart';
import 'package:gfrm_dart/src/application/run_service.dart';
import 'package:gfrm_dart/src/core/adapters/provider_adapter.dart';
import 'package:gfrm_dart/src/core/exceptions/authentication_error.dart';
import 'package:gfrm_dart/src/core/logging.dart';
import 'package:gfrm_dart/src/core/session_store.dart';
import 'package:gfrm_dart/src/core/types/canonical_release.dart';
import 'package:gfrm_dart/src/core/types/existing_release_info.dart';
import 'package:gfrm_dart/src/core/types/publish_release_input.dart';
import 'package:gfrm_dart/src/models/runtime_options.dart';
import 'package:gfrm_dart/src/providers/registry.dart';
import 'package:gfrm_dart/src/runtime_events/in_memory_runtime_event_sink.dart';
import 'package:gfrm_dart/src/runtime_events/run_state_runtime_event_sink.dart';
import 'package:gfrm_dart/src/runtime_events/runtime_event_envelope.dart';
import 'package:gfrm_dart/src/runtime_events/runtime_event_sink.dart';
import 'package:gfrm_dart/src/runtime_events/runtime_event_sink_failure_mode.dart';
import 'package:test/test.dart';

import '../../support/buffer_console_output.dart';
import '../../support/logging.dart';
import '../../support/provider_fixtures.dart';
import '../../support/runtime_options_fixture.dart';
import '../../support/temp_dir.dart';

final class _SourceAdapter extends ProviderAdapter {
  _SourceAdapter({required this.releases});

  final List<Map<String, dynamic>> releases;

  @override
  String get name => 'stub-source';

  @override
  ProviderRef parseUrl(String url) {
    if (!url.startsWith('https://github.com/')) {
      throw ArgumentError('Invalid GitHub repository URL: $url');
    }

    return ProviderRef(
      provider: 'github',
      rawUrl: url,
      baseUrl: 'https://github.com',
      host: 'github.com',
      resource: 'acme/source',
    );
  }

  @override
  CanonicalRelease toCanonicalRelease(Map<String, dynamic> payload) => CanonicalRelease.fromMap(payload);

  @override
  Future<List<Map<String, dynamic>>> listReleases(ProviderRef ref, String token) async => releases;

  @override
  Future<String> resolveCommitShaForMigration(
    ProviderRef ref,
    String token,
    String tag,
    CanonicalRelease canonical,
  ) async {
    if (canonical.commitSha.isNotEmpty) {
      return canonical.commitSha;
    }

    return 'default-sha';
  }
}

final class _TargetAdapter extends ProviderAdapter {
  _TargetAdapter({
    this.onCreateTag,
    this.onTagExists,
    this.onCommitExists,
  });

  final Future<void> Function(ProviderRef, String, String, String, CanonicalRelease)? onCreateTag;
  final Future<bool> Function(ProviderRef, String, String)? onTagExists;
  final Future<bool> Function(ProviderRef, String, String)? onCommitExists;
  final Set<String> _createdTags = <String>{};

  @override
  String get name => 'stub-target';

  @override
  ProviderRef parseUrl(String url) {
    if (!url.startsWith('https://gitlab.com/')) {
      throw ArgumentError('Invalid GitLab repository URL: $url');
    }

    return ProviderRef(
      provider: 'gitlab',
      rawUrl: url,
      baseUrl: 'https://gitlab.com',
      host: 'gitlab.com',
      resource: 'acme/target',
    );
  }

  @override
  CanonicalRelease toCanonicalRelease(Map<String, dynamic> payload) => CanonicalRelease.fromMap(payload);

  @override
  Future<List<String>> listTags(ProviderRef ref, String token) async => <String>[];

  @override
  Future<bool> tagExists(ProviderRef ref, String token, String tag) async {
    if (onTagExists != null) {
      return onTagExists!(ref, token, tag);
    }

    return _createdTags.contains(tag);
  }

  @override
  Future<bool> commitExists(ProviderRef ref, String token, String sha) async {
    if (onCommitExists != null) {
      return onCommitExists!(ref, token, sha);
    }

    return true;
  }

  @override
  Future<void> createTagForMigration(
    ProviderRef ref,
    String token,
    String tag,
    String sha,
    CanonicalRelease canonical,
  ) async {
    if (onCreateTag != null) {
      return onCreateTag!(ref, token, tag, sha, canonical);
    }

    _createdTags.add(tag);
  }

  @override
  Future<bool> releaseExists(ProviderRef ref, String token, String tag) async => false;

  @override
  Future<ExistingReleaseInfo> existingReleaseInfo(
    ProviderRef ref,
    String token,
    String tag,
    int expectedLinkAssets,
  ) async =>
      const ExistingReleaseInfo(exists: false, shouldRetry: false, reason: '');

  @override
  Future<String> publishRelease(PublishReleaseInput input) async => 'created';
}

ProviderRegistry _buildRegistry({
  required List<Map<String, dynamic>> releases,
  Future<void> Function(ProviderRef, String, String, String, CanonicalRelease)? onCreateTag,
  Future<bool> Function(ProviderRef, String, String)? onTagExists,
  Future<bool> Function(ProviderRef, String, String)? onCommitExists,
}) {
  return ProviderRegistry(<String, ProviderAdapter>{
    'github': _SourceAdapter(releases: releases),
    'gitlab': _TargetAdapter(
      onCreateTag: onCreateTag,
      onTagExists: onTagExists,
      onCommitExists: onCommitExists,
    ),
  });
}

final class _ThrowingRuntimeEventSink implements RuntimeEventSink {
  const _ThrowingRuntimeEventSink({
    required this.id,
    required this.failureMode,
  });

  @override
  final String id;

  @override
  final RuntimeEventSinkFailureMode failureMode;

  @override
  void consume(RuntimeEventEnvelope envelope) {
    throw StateError('sink failure: ${envelope.eventType}');
  }
}

void main() {
  group('RunService', () {
    test('returns success result and keeps summary artifacts for successful migrate flow', () async {
      final Directory temp = createTempDir('gfrm-run-service-success-');
      final RunService service = RunService(
        logger: createSilentLogger(),
        registryFactory: (_) => _buildRegistry(releases: <Map<String, dynamic>>[buildMinimalReleasePayload('v1.0.0')]),
      );

      final RunResult result = await service.run(
        RunRequest(
          options: buildRuntimeOptions(workdir: '${temp.path}/results'),
        ),
      );

      expect(result.status, RunStatus.success);
      expect(result.exitCode, 0);
      expect(
          result.preflightChecks.where((PreflightCheck check) => check.status == PreflightCheckStatus.ok), isNotEmpty);
      expect(File(result.summaryPath).existsSync(), isTrue);
      expect(File(result.failedTagsPath).readAsStringSync(), isEmpty);
      expect(result.retryCommand, isEmpty);
    });

    test('emits ordered runtime events for successful migrate flow when sinks are registered', () async {
      final Directory temp = createTempDir('gfrm-run-service-events-success-');
      final InMemoryRuntimeEventSink sink = InMemoryRuntimeEventSink();
      final RunService service = RunService(
        logger: createSilentLogger(),
        registryFactory: (_) => _buildRegistry(releases: <Map<String, dynamic>>[buildMinimalReleasePayload('v1.0.0')]),
      );

      final RunResult result = await service.run(
        RunRequest(
          options: buildRuntimeOptions(workdir: '${temp.path}/results'),
          runtimeEventSinks: <InMemoryRuntimeEventSink>[sink],
        ),
      );

      expect(result.status, RunStatus.success);
      expect(sink.events.map((event) => event.sequence), <int>[1, 2, 3, 4, 5, 6, 7, 8]);
      expect(sink.events.map((event) => event.eventType), <String>[
        'run_started',
        'preflight_completed',
        'tag_migrated',
        'release_migrated',
        'artifact_written',
        'artifact_written',
        'artifact_written',
        'run_completed',
      ]);
      expect(sink.events.last.payload['status'], 'success');
    });

    test('keeps success artifact events and final payload aligned with written files', () async {
      final Directory temp = createTempDir('gfrm-run-service-events-artifacts-success-');
      final InMemoryRuntimeEventSink sink = InMemoryRuntimeEventSink();
      final RunService service = RunService(
        logger: createSilentLogger(),
        registryFactory: (_) => _buildRegistry(releases: <Map<String, dynamic>>[buildMinimalReleasePayload('v1.0.0')]),
      );

      final RunResult result = await service.run(
        RunRequest(
          options: buildRuntimeOptions(workdir: '${temp.path}/results'),
          runtimeEventSinks: <InMemoryRuntimeEventSink>[sink],
        ),
      );

      final List<RuntimeEventEnvelope> artifactEvents = sink.events
          .where((RuntimeEventEnvelope event) => event.eventType == 'artifact_written')
          .toList(growable: false);
      final Map<String, dynamic> runCompletedPayload = sink.events.last.payload;
      final Map<String, dynamic> summary = _readSummary(result.summaryPath);

      expect(result.status, RunStatus.success);
      expect(artifactEvents.map((RuntimeEventEnvelope event) => event.payload['artifact_type']), <String>[
        'migration_log',
        'failed_tags',
        'summary',
      ]);
      expect(
        artifactEvents.map((RuntimeEventEnvelope event) => event.payload['path']),
        <String>[result.logPath, result.failedTagsPath, result.summaryPath],
      );
      expect(File(result.logPath).existsSync(), isTrue);
      expect(File(result.failedTagsPath).existsSync(), isTrue);
      expect(File(result.summaryPath).existsSync(), isTrue);
      expect(runCompletedPayload['summary_path'], result.summaryPath);
      expect(runCompletedPayload['failed_tags_path'], result.failedTagsPath);
      expect(runCompletedPayload.containsKey('retry_command'), isFalse);
      expect(summary['retry_command'], '');
      expect((summary['paths'] as Map<String, dynamic>)['jsonl_log'], result.logPath);
      expect((summary['paths'] as Map<String, dynamic>)['failed_tags'], result.failedTagsPath);
    });

    test('continues when optional runtime sink fails', () async {
      final Directory temp = createTempDir('gfrm-run-service-events-optional-sink-');
      final InMemoryRuntimeEventSink sink = InMemoryRuntimeEventSink();
      final RunService service = RunService(
        logger: createSilentLogger(),
        registryFactory: (_) => _buildRegistry(releases: <Map<String, dynamic>>[buildMinimalReleasePayload('v1.0.0')]),
      );

      final RunResult result = await service.run(
        RunRequest(
          options: buildRuntimeOptions(workdir: '${temp.path}/results'),
          runtimeEventSinks: <RuntimeEventSink>[
            const _ThrowingRuntimeEventSink(
              id: 'optional-broken',
              failureMode: RuntimeEventSinkFailureMode.optional,
            ),
            sink,
          ],
        ),
      );

      expect(result.status, RunStatus.success);
      expect(sink.events.last.eventType, 'run_completed');
    });

    test('returns partial failure with retry command when migration writes failed tags', () async {
      final Directory temp = createTempDir('gfrm-run-service-partial-');
      final InMemoryRuntimeEventSink sink = InMemoryRuntimeEventSink();
      final RunService service = RunService(
        logger: createSilentLogger(),
        registryFactory: (_) => _buildRegistry(
          releases: <Map<String, dynamic>>[buildMinimalReleasePayload('v1.0.0')],
          onCreateTag: (_, __, ___, ____, _____) async => throw Exception('network error'),
        ),
      );

      final RunResult result = await service.run(
        RunRequest(
          options: buildRuntimeOptions(workdir: '${temp.path}/results'),
          runtimeEventSinks: <InMemoryRuntimeEventSink>[sink],
        ),
      );

      expect(result.status, RunStatus.partialFailure);
      expect(result.exitCode, 1);
      expect(result.retryCommand, contains('gfrm resume --tags-file'));
      expect(File(result.summaryPath).existsSync(), isTrue);
      expect(File(result.failedTagsPath).readAsStringSync(), 'v1.0.0\n');
      expect(sink.events.last.eventType, 'run_completed');
      expect(sink.events.last.payload['status'], 'partial_failure');
      expect(sink.events.last.payload['retry_command'], contains('gfrm resume --tags-file'));
    });

    test('keeps partial-failure artifacts retry command and summary in sync', () async {
      final Directory temp = createTempDir('gfrm-run-service-partial-artifact-sync-');
      final InMemoryRuntimeEventSink sink = InMemoryRuntimeEventSink();
      final RunService service = RunService(
        logger: createSilentLogger(),
        registryFactory: (_) => _buildRegistry(
          releases: <Map<String, dynamic>>[buildMinimalReleasePayload('v1.0.0')],
          onCreateTag: (_, __, ___, ____, _____) async => throw Exception('network error'),
        ),
      );

      final RunResult result = await service.run(
        RunRequest(
          options: buildRuntimeOptions(workdir: '${temp.path}/results'),
          runtimeEventSinks: <InMemoryRuntimeEventSink>[sink],
        ),
      );

      final List<RuntimeEventEnvelope> artifactEvents = sink.events
          .where((RuntimeEventEnvelope event) => event.eventType == 'artifact_written')
          .toList(growable: false);
      final Map<String, dynamic> runCompletedPayload = sink.events.last.payload;
      final Map<String, dynamic> summary = _readSummary(result.summaryPath);

      expect(result.status, RunStatus.partialFailure);
      expect(artifactEvents.map((RuntimeEventEnvelope event) => event.payload['path']), <String>[
        result.logPath,
        result.failedTagsPath,
        result.summaryPath,
      ]);
      expect(File(result.failedTagsPath).readAsStringSync(), 'v1.0.0\n');
      expect(runCompletedPayload['summary_path'], result.summaryPath);
      expect(runCompletedPayload['failed_tags_path'], result.failedTagsPath);
      expect(runCompletedPayload['retry_command'], result.retryCommand);
      expect(summary['retry_command'], result.retryCommand);
      expect((summary['failed_tags'] as List<dynamic>).cast<String>(), <String>['v1.0.0']);
      expect((summary['paths'] as Map<String, dynamic>)['failed_tags'], result.failedTagsPath);
    });

    test('resume retries only failed tags and keeps summary retry contract stable', () async {
      final Directory temp = createTempDir('gfrm-run-service-resume-idempotent-');
      final List<String> createTagCalls = <String>[];
      final Set<String> createdTags = <String>{};
      bool failFirstTagAttempt = true;
      final ProviderRegistry registry = ProviderRegistry(<String, ProviderAdapter>{
        'github': _SourceAdapter(
          releases: <Map<String, dynamic>>[
            buildMinimalReleasePayload('v1.0.0'),
            buildMinimalReleasePayload('v1.1.0'),
          ],
        ),
        'gitlab': _TargetAdapter(
          onCreateTag: (_, __, String tag, ___, ____) async {
            createTagCalls.add(tag);
            if (tag == 'v1.0.0' && failFirstTagAttempt) {
              failFirstTagAttempt = false;
              throw Exception('network error');
            }

            createdTags.add(tag);
          },
          onTagExists: (_, __, String tag) async => createdTags.contains(tag),
        ),
      });
      final RunService service = RunService(
        logger: createSilentLogger(),
        registryFactory: (_) => registry,
      );
      final InMemoryRuntimeEventSink firstSink = InMemoryRuntimeEventSink();

      final RunResult firstResult = await service.run(
        RunRequest(
          options: buildRuntimeOptions(workdir: '${temp.path}/results'),
          runtimeEventSinks: <InMemoryRuntimeEventSink>[firstSink],
        ),
      );

      final int firstRunCallCount = createTagCalls.length;
      final InMemoryRuntimeEventSink resumeSink = InMemoryRuntimeEventSink();
      final RunResult resumeResult = await service.run(
        RunRequest(
          options: buildRuntimeOptions(
            commandName: commandResume,
            workdir: '${temp.path}/results',
            tagsFile: firstResult.failedTagsPath,
          ),
          runtimeEventSinks: <InMemoryRuntimeEventSink>[resumeSink],
        ),
      );

      final Map<String, dynamic> resumeSummary = _readSummary(resumeResult.summaryPath);

      expect(firstResult.status, RunStatus.partialFailure);
      expect(firstResult.retryCommand, contains('gfrm resume --tags-file'));
      expect(File(firstResult.failedTagsPath).readAsStringSync(), 'v1.0.0\n');
      expect(createTagCalls.take(firstRunCallCount), <String>['v1.0.0', 'v1.1.0']);
      expect(createdTags, contains('v1.1.0'));
      expect(resumeResult.status, RunStatus.success);
      expect(resumeResult.retryCommand, isEmpty);
      expect(createTagCalls.skip(firstRunCallCount), <String>['v1.0.0']);
      expect(createdTags, containsAll(<String>{'v1.0.0', 'v1.1.0'}));
      expect(File(resumeResult.failedTagsPath).readAsStringSync(), isEmpty);
      expect(resumeSummary['schema_version'], 2);
      expect(resumeSummary['command'], commandResume);
      expect(resumeSummary['retry_command'], '');
      expect((resumeSummary['failed_tags'] as List<dynamic>), isEmpty);
      expect((resumeSummary['paths'] as Map<String, dynamic>)['failed_tags'], resumeResult.failedTagsPath);
      expect(resumeSink.events.last.eventType, 'run_completed');
      expect(resumeSink.events.last.payload['status'], 'success');
      expect(resumeSink.events.last.payload['summary_path'], resumeResult.summaryPath);
      expect(resumeSink.events.last.payload.containsKey('retry_command'), isFalse);
    });

    test('reduces successful runtime stream into typed run state snapshot', () async {
      final Directory temp = createTempDir('gfrm-run-service-run-state-');
      final RunStateRuntimeEventSink sink = RunStateRuntimeEventSink();
      final RunService service = RunService(
        logger: createSilentLogger(),
        registryFactory: (_) => _buildRegistry(releases: <Map<String, dynamic>>[buildMinimalReleasePayload('v1.0.0')]),
      );

      final RunResult result = await service.run(
        RunRequest(
          options: buildRuntimeOptions(
            workdir: '${temp.path}/results',
            settingsProfile: 'desktop',
          ),
          runtimeEventSinks: <RunStateRuntimeEventSink>[sink],
        ),
      );

      expect(result.status, RunStatus.success);
      expect(sink.state.lifecycle.value, 'completed');
      expect(sink.state.activePhase.value, 'completed');
      expect(sink.state.sourceProvider, 'github');
      expect(sink.state.targetProvider, 'gitlab');
      expect(sink.state.mode, 'migrate');
      expect(sink.state.settingsProfile, 'desktop');
      expect(sink.state.tagCreatedCount, 1);
      expect(sink.state.releaseCreatedCount, 1);
      expect(sink.state.artifactPaths.summaryPath, result.summaryPath);
      expect(sink.state.artifactPaths.failedTagsPath, result.failedTagsPath);
      expect(sink.state.artifactPaths.migrationLogPath, result.logPath);
      expect(sink.state.completionStatus, 'success');
      expect(sink.state.retryCommand, isEmpty);
      expect(sink.state.totalTags, 1);
      expect(sink.state.failedTags, 0);
      expect(sink.state.latestFailure, isNull);
    });

    test('returns validation failure when no releases are selected', () async {
      final Directory temp = createTempDir('gfrm-run-service-validation-');
      final RunService service = RunService(
        logger: createSilentLogger(),
        registryFactory: (_) => _buildRegistry(releases: <Map<String, dynamic>>[]),
      );

      final RunResult result = await service.run(
        RunRequest(
          options: buildRuntimeOptions(workdir: '${temp.path}/results'),
        ),
      );

      expect(result.status, RunStatus.validationFailure);
      expect(result.exitCode, 1);
      expect(result.failures.single.scope, 'validation');
      expect(result.failures.single.message, contains(RunService.noReleasesFoundMessage));
    });

    test('returns runtime failure for authentication errors before summary generation', () async {
      final Directory temp = createTempDir('gfrm-run-service-runtime-');
      final RunService service = RunService(
        logger: createSilentLogger(),
        registryFactory: (_) => _buildRegistry(
          releases: <Map<String, dynamic>>[buildMinimalReleasePayload('v1.0.0')],
          onTagExists: (_, __, ___) async => throw AuthenticationError('401 unauthorized'),
        ),
      );

      final RunResult result = await service.run(
        RunRequest(
          options: buildRuntimeOptions(workdir: '${temp.path}/results'),
        ),
      );

      expect(result.status, RunStatus.runtimeFailure);
      expect(result.exitCode, 1);
      expect(result.failures.single.scope, 'execution');
      expect(File(result.summaryPath).existsSync(), isFalse);
    });

    test('returns runtime failure when mandatory runtime sink fails', () async {
      final Directory temp = createTempDir('gfrm-run-service-events-mandatory-sink-');
      final InMemoryRuntimeEventSink sink = InMemoryRuntimeEventSink();
      final RunService service = RunService(
        logger: createSilentLogger(),
        registryFactory: (_) => _buildRegistry(releases: <Map<String, dynamic>>[buildMinimalReleasePayload('v1.0.0')]),
      );

      final RunResult result = await service.run(
        RunRequest(
          options: buildRuntimeOptions(workdir: '${temp.path}/results'),
          runtimeEventSinks: <RuntimeEventSink>[
            sink,
            const _ThrowingRuntimeEventSink(
              id: 'mandatory-broken',
              failureMode: RuntimeEventSinkFailureMode.mandatory,
            ),
          ],
        ),
      );

      expect(result.status, RunStatus.runtimeFailure);
      expect(result.failures.single.code, 'runtime-event-sink-failed');
      expect(result.failures.single.phase, 'runtime_event_sink');
      expect(sink.events.map((RuntimeEventEnvelope event) => event.eventType), <String>['run_failed']);
      expect(File(result.summaryPath).existsSync(), isFalse);
    });

    test('fails fast with summary when target commit history is missing', () async {
      final Directory temp = createTempDir('gfrm-run-service-missing-target-history-');
      final InMemoryRuntimeEventSink sink = InMemoryRuntimeEventSink();
      final RunService service = RunService(
        logger: createSilentLogger(),
        registryFactory: (_) => _buildRegistry(
          releases: <Map<String, dynamic>>[
            buildMinimalReleasePayload('v1.0.0', commitSha: 'deadbeef'),
          ],
          onCreateTag: (_, __, ___, ____, _____) async {
            fail('tag creation should not be attempted when target commit history is missing');
          },
          onCommitExists: (_, __, ___) async => false,
        ),
      );

      final RunResult result = await service.run(
        RunRequest(
          options: buildRuntimeOptions(workdir: '${temp.path}/results'),
          runtimeEventSinks: <InMemoryRuntimeEventSink>[sink],
        ),
      );

      expect(result.status, RunStatus.validationFailure);
      expect(result.exitCode, 1);
      expect(result.failures.single.code, 'missing-target-commit-history');
      expect(result.failures.single.retryable, isTrue);
      expect(File(result.summaryPath).existsSync(), isTrue);
      expect(File(result.failedTagsPath).readAsStringSync(), 'v1.0.0\n');
      expect(result.retryCommand, contains('gfrm resume --tags-file'));
      expect(sink.events[1].eventType, 'preflight_completed');
      expect(sink.events[1].payload['status'], 'failed');
      expect(sink.events.last.eventType, 'run_failed');
      expect(sink.events.last.payload['code'], 'missing-target-commit-history');
    });

    test('keeps preflight run_failed event consistent with written artifacts when summary exists', () async {
      final Directory temp = createTempDir('gfrm-run-service-preflight-artifact-sync-');
      final InMemoryRuntimeEventSink sink = InMemoryRuntimeEventSink();
      final RunService service = RunService(
        logger: createSilentLogger(),
        registryFactory: (_) => _buildRegistry(
          releases: <Map<String, dynamic>>[
            buildMinimalReleasePayload('v1.0.0', commitSha: 'deadbeef'),
          ],
          onCreateTag: (_, __, ___, ____, _____) async {
            fail('tag creation should not be attempted when target commit history is missing');
          },
          onCommitExists: (_, __, ___) async => false,
        ),
      );

      final RunResult result = await service.run(
        RunRequest(
          options: buildRuntimeOptions(workdir: '${temp.path}/results'),
          runtimeEventSinks: <InMemoryRuntimeEventSink>[sink],
        ),
      );

      final List<RuntimeEventEnvelope> artifactEvents = sink.events
          .where((RuntimeEventEnvelope event) => event.eventType == 'artifact_written')
          .toList(growable: false);
      final Map<String, dynamic> runFailedPayload = sink.events.last.payload;
      final Map<String, dynamic> summary = _readSummary(result.summaryPath);

      expect(result.status, RunStatus.validationFailure);
      expect(artifactEvents.map((RuntimeEventEnvelope event) => event.payload['path']), <String>[
        result.logPath,
        result.failedTagsPath,
        result.summaryPath,
      ]);
      expect(File(result.summaryPath).existsSync(), isTrue);
      expect(File(result.failedTagsPath).readAsStringSync(), 'v1.0.0\n');
      expect(runFailedPayload['code'], 'missing-target-commit-history');
      expect(runFailedPayload.containsKey('summary_path'), isFalse);
      expect(runFailedPayload.containsKey('failed_tags_path'), isFalse);
      expect(runFailedPayload.containsKey('retry_command'), isFalse);
      expect(summary['retry_command'], result.retryCommand);
      expect((summary['failed_tags'] as List<dynamic>).cast<String>(), <String>['v1.0.0']);
    });

    test('returns validation failure with preflight message for unsupported command', () async {
      final Directory temp = createTempDir('gfrm-run-service-invalid-command-');
      final String resultsRootPath = '${temp.path}/results';
      final RunService service = RunService(
        logger: createSilentLogger(),
        registryFactory: (_) => throw StateError('registry should not be used for invalid command'),
      );

      final RunResult result = await service.run(
        RunRequest(
          options: buildRuntimeOptions(
            commandName: 'settings',
            workdir: resultsRootPath,
          ),
        ),
      );

      expect(result.status, RunStatus.validationFailure);
      expect(result.exitCode, 1);
      expect(result.preflightMessages, hasLength(1));
      expect(result.preflightMessages.single, contains('RunService supports migrate and resume only'));
      expect(result.preflightChecks.single.code, 'unsupported-command');
      expect(result.failures.single.retryable, isFalse);
      expect(Directory(resultsRootPath).existsSync(), isFalse);
    });

    test('returns validation failure with structured preflight checks for unsupported provider pair', () async {
      final Directory temp = createTempDir('gfrm-run-service-unsupported-pair-');
      final RunService service = RunService(
        logger: createSilentLogger(),
        registryFactory: (_) => _buildRegistry(releases: const <Map<String, dynamic>>[]),
      );

      final RunResult result = await service.run(
        RunRequest(
          options: buildRuntimeOptions(
            workdir: '${temp.path}/results',
            sourceProvider: 'github',
            targetProvider: 'github',
            migrationOrder: 'github-to-github',
          ),
        ),
      );

      expect(result.status, RunStatus.validationFailure);
      expect(result.failures.single.code, 'unsupported-provider-pair');
      expect(result.preflightChecks.any((PreflightCheck check) => check.code == 'unsupported-provider-pair'), isTrue);
      expect(Directory('${temp.path}/results').existsSync(), isFalse);
    });

    test('uses default registry factory for startup preflight without touching network', () async {
      final Directory temp = createTempDir('gfrm-run-service-default-registry-');
      final RunService service = RunService(
        logger: createSilentLogger(),
      );

      final RunResult result = await service.run(
        RunRequest(
          options: buildRuntimeOptions(
            workdir: '${temp.path}/results',
            sourceProvider: 'github',
            targetProvider: 'github',
            migrationOrder: 'github-to-github',
          ),
        ),
      );

      expect(result.status, RunStatus.validationFailure);
      expect(result.failures.single.code, 'unsupported-provider-pair');
      expect(result.preflightChecks.any((PreflightCheck check) => check.code == 'unsupported-provider-pair'), isTrue);
      expect(Directory('${temp.path}/results').existsSync(), isFalse);
    });

    test('returns validation failure with structured preflight checks for malformed repository URL', () async {
      final Directory temp = createTempDir('gfrm-run-service-bad-url-');
      final RunService service = RunService(
        logger: createSilentLogger(),
        registryFactory: (_) => _buildRegistry(releases: <Map<String, dynamic>>[buildMinimalReleasePayload('v1.0.0')]),
      );

      final RunResult result = await service.run(
        RunRequest(
          options: buildRuntimeOptions(
            workdir: '${temp.path}/results',
            sourceUrl: 'not-a-valid-url',
          ),
        ),
      );

      expect(result.status, RunStatus.validationFailure);
      expect(result.failures.single.code, 'invalid-source-url');
      expect(
          result.preflightChecks.any((PreflightCheck check) => check.field == PreflightService.fieldSourceUrl), isTrue);
      expect(Directory('${temp.path}/results').existsSync(), isFalse);
    });

    test('returns validation failure with structured preflight checks for missing token resolution', () async {
      final Directory temp = createTempDir('gfrm-run-service-missing-token-');
      final RunService service = RunService(
        logger: createSilentLogger(),
        registryFactory: (_) => _buildRegistry(releases: <Map<String, dynamic>>[buildMinimalReleasePayload('v1.0.0')]),
      );

      final RunResult result = await service.run(
        RunRequest(
          options: buildRuntimeOptions(
            workdir: '${temp.path}/results',
            sourceToken: '',
            targetToken: '',
          ),
        ),
      );

      expect(result.status, RunStatus.validationFailure);
      expect(result.preflightChecks.where((PreflightCheck check) => check.isBlocking), hasLength(2));
      expect(result.preflightChecks.any((PreflightCheck check) => check.code == 'missing-source-token'), isTrue);
      expect(result.preflightChecks.any((PreflightCheck check) => check.code == 'missing-target-token'), isTrue);
    });

    test('keeps warning-only preflight non-blocking for missing settings profile', () async {
      final Directory temp = createTempDir('gfrm-run-service-settings-warning-');
      final RunService service = RunService(
        logger: createSilentLogger(),
        registryFactory: (_) => _buildRegistry(releases: <Map<String, dynamic>>[buildMinimalReleasePayload('v1.0.0')]),
        preflightService: PreflightService(
          settingsLoader: () => <String, dynamic>{
            'profiles': <String, dynamic>{
              'default': <String, dynamic>{},
            },
          },
        ),
      );

      final RunResult result = await service.run(
        RunRequest(
          options: buildRuntimeOptions(
            workdir: '${temp.path}/results',
            settingsProfile: 'work',
          ),
        ),
      );

      expect(result.status, RunStatus.success);
      expect(result.preflightChecks.any((PreflightCheck check) => check.code == 'missing-settings-profile'), isTrue);
      expect(
          result.preflightChecks.any((PreflightCheck check) => check.status == PreflightCheckStatus.warning), isTrue);
    });

    test('saves plain session payload and emits runtime header details', () async {
      final Directory temp = createTempDir('gfrm-run-service-session-plain-');
      final BufferConsoleOutput output = BufferConsoleOutput();
      final ConsoleLogger logger = ConsoleLogger(
        quiet: false,
        jsonOutput: false,
        output: output,
        silent: false,
      );
      final String sessionPath = '${temp.path}/sessions/plain-session.json';
      final String tagsPath = '${temp.path}/selected-tags.txt';
      File(tagsPath).writeAsStringSync('v1.0.0\n');

      final RunService service = RunService(
        logger: logger,
        registryFactory: (_) => _buildRegistry(releases: <Map<String, dynamic>>[buildMinimalReleasePayload('v1.0.0')]),
      );

      final RunResult result = await service.run(
        RunRequest(
          options: buildRuntimeOptions(
            workdir: '${temp.path}/results',
            saveSession: true,
            sessionFile: sessionPath,
            sessionTokenMode: 'plain',
            settingsProfile: 'work',
            tagsFile: tagsPath,
          ),
        ),
      );

      final Map<String, dynamic> savedSession = SessionStore.loadSession(sessionPath);

      expect(result.status, RunStatus.success);
      expect(savedSession['source_token'], 'src-token');
      expect(savedSession['target_token'], 'dst-token');
      expect(output.stderrLines,
          contains('[WARN] Session file stores tokens in plain text. Keep file permissions restricted.'));
      expect(output.stdoutLines, contains('[INFO]   Settings profile: work'));
      expect(output.stdoutLines, contains('[INFO]   Tags file: $tagsPath'));
    });

    test('saves env session references when resume session is enabled', () async {
      final Directory temp = createTempDir('gfrm-run-service-session-env-');
      final BufferConsoleOutput output = BufferConsoleOutput();
      final ConsoleLogger logger = ConsoleLogger(
        quiet: false,
        jsonOutput: false,
        output: output,
        silent: false,
      );
      final String sessionPath = '${temp.path}/sessions/env-session.json';

      final RunService service = RunService(
        logger: logger,
        registryFactory: (_) => _buildRegistry(releases: <Map<String, dynamic>>[buildMinimalReleasePayload('v1.0.0')]),
      );

      final RunResult result = await service.run(
        RunRequest(
          options: buildRuntimeOptions(
            commandName: commandResume,
            workdir: '${temp.path}/results',
            resumeSession: true,
            sessionFile: sessionPath,
            sessionTokenMode: 'env',
            sessionSourceTokenEnv: 'SRC_TOKEN_ENV',
            sessionTargetTokenEnv: 'DST_TOKEN_ENV',
          ),
        ),
      );

      final Map<String, dynamic> savedSession = SessionStore.loadSession(sessionPath);

      expect(result.status, RunStatus.success);
      expect(savedSession['source_token_env'], 'SRC_TOKEN_ENV');
      expect(savedSession['target_token_env'], 'DST_TOKEN_ENV');
      expect(savedSession.containsKey('source_token'), isFalse);
      expect(
          output.stdoutLines,
          contains(
              '[INFO] Session stores token env references only. Keep those environment variables available for resume.'));
    });

    test('uses preflight to reject unsupported provider pairs before migration starts', () async {
      final Directory temp = createTempDir('gfrm-run-service-default-registry-');
      final RunService service = RunService(
        logger: createSilentLogger(),
        registryFactory: (_) => _buildRegistry(releases: const <Map<String, dynamic>>[]),
      );

      final RunResult result = await service.run(
        RunRequest(
          options: buildRuntimeOptions(
            workdir: '${temp.path}/results',
            sourceProvider: 'github',
            targetProvider: 'github',
            migrationOrder: 'github-to-github',
          ),
        ),
      );

      expect(result.status, RunStatus.validationFailure);
      expect(result.exitCode, 1);
      expect(result.failures.single.scope, RunFailure.scopeValidation);
      expect(result.failures.single.message, contains('Provider pair github->github is unsupported.'));
      expect(result.preflightChecks.any((PreflightCheck check) => check.code == 'unsupported-provider-pair'), isTrue);
    });

    test('maps argument errors from dependencies into validation failure results', () async {
      final Directory temp = createTempDir('gfrm-run-service-argument-error-');
      final RunService service = RunService(
        logger: createSilentLogger(),
        registryFactory: (_) => throw ArgumentError('bad runtime input'),
      );

      final RunResult result = await service.run(
        RunRequest(
          options: buildRuntimeOptions(workdir: '${temp.path}/results'),
        ),
      );

      expect(result.status, RunStatus.validationFailure);
      expect(result.failures.single.code, 'invalid-request');
      expect(result.failures.single.message, contains('bad runtime input'));
    });

    test('maps unexpected dependency failures into runtime failure results', () async {
      final Directory temp = createTempDir('gfrm-run-service-unexpected-error-');
      final RunService service = RunService(
        logger: createSilentLogger(),
        registryFactory: (_) => throw StateError('unexpected boom'),
      );

      final RunResult result = await service.run(
        RunRequest(
          options: buildRuntimeOptions(workdir: '${temp.path}/results'),
        ),
      );

      expect(result.status, RunStatus.runtimeFailure);
      expect(result.failures.single.code, 'runtime-failed');
      expect(result.failures.single.message, contains('unexpected boom'));
    });
  });
}

Map<String, dynamic> _readSummary(String path) {
  return jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
}
