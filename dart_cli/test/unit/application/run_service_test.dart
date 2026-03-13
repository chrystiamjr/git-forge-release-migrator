import 'dart:io';

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
  ProviderRef parseUrl(String url) => ProviderRef(
        provider: 'github',
        rawUrl: url,
        baseUrl: 'https://github.com',
        host: 'github.com',
        resource: 'acme/source',
      );

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
  });

  final Future<void> Function(ProviderRef, String, String, String, CanonicalRelease)? onCreateTag;
  final Future<bool> Function(ProviderRef, String, String)? onTagExists;
  final Set<String> _createdTags = <String>{};

  @override
  String get name => 'stub-target';

  @override
  ProviderRef parseUrl(String url) => ProviderRef(
        provider: 'gitlab',
        rawUrl: url,
        baseUrl: 'https://gitlab.com',
        host: 'gitlab.com',
        resource: 'acme/target',
      );

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
}) {
  return ProviderRegistry(<String, ProviderAdapter>{
    'github': _SourceAdapter(releases: releases),
    'gitlab': _TargetAdapter(
      onCreateTag: onCreateTag,
      onTagExists: onTagExists,
    ),
  });
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
      expect(File(result.summaryPath).existsSync(), isTrue);
      expect(File(result.failedTagsPath).readAsStringSync(), isEmpty);
      expect(result.retryCommand, isEmpty);
    });

    test('returns partial failure with retry command when migration writes failed tags', () async {
      final Directory temp = createTempDir('gfrm-run-service-partial-');
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
        ),
      );

      expect(result.status, RunStatus.partialFailure);
      expect(result.exitCode, 1);
      expect(result.retryCommand, contains('gfrm resume --tags-file'));
      expect(File(result.summaryPath).existsSync(), isTrue);
      expect(File(result.failedTagsPath).readAsStringSync(), 'v1.0.0\n');
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

    test('returns validation failure with preflight message for unsupported command', () async {
      final Directory temp = createTempDir('gfrm-run-service-invalid-command-');
      final RunService service = RunService(
        logger: createSilentLogger(),
        registryFactory: (_) => throw StateError('registry should not be used for invalid command'),
      );

      final RunResult result = await service.run(
        RunRequest(
          options: buildRuntimeOptions(
            commandName: 'settings',
            workdir: '${temp.path}/results',
          ),
        ),
      );

      expect(result.status, RunStatus.validationFailure);
      expect(result.exitCode, 1);
      expect(result.preflightMessages, hasLength(1));
      expect(result.preflightMessages.single, contains('RunService supports migrate and resume only'));
      expect(result.failures.single.retryable, isFalse);
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

    test('uses default registry factory before rejecting unsupported provider pairs', () async {
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
    });
  });
}
