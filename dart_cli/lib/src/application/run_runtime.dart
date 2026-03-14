import '../core/adapters/provider_adapter.dart';
import '../core/logging.dart';
import '../core/session_store.dart';
import '../models/runtime_options.dart';
import 'run_paths.dart';

final class RunRuntime {
  RunRuntime({
    required this.options,
    required this.sourceRef,
    required this.targetRef,
  });

  final RuntimeOptions options;
  final ProviderRef sourceRef;
  final ProviderRef targetRef;

  static RunRuntime initialize({
    required RuntimeOptions options,
    required ProviderAdapter sourceAdapter,
    required ProviderAdapter targetAdapter,
    required PreparedRun prepared,
    required ConsoleLogger logger,
  }) {
    final ProviderRef sourceRef = sourceAdapter.parseUrl(options.sourceUrl);
    final ProviderRef targetRef = targetAdapter.parseUrl(options.targetUrl);

    _saveSessionIfEnabled(options, logger);
    _logRuntimeHeader(options, sourceRef, targetRef, prepared, logger);

    return RunRuntime(
      options: options,
      sourceRef: sourceRef,
      targetRef: targetRef,
    );
  }
}

void _saveSessionIfEnabled(RuntimeOptions options, ConsoleLogger logger) {
  if (!options.saveSession && !options.resumeSession) {
    return;
  }

  final String sessionFile = options.effectiveSessionFile();
  SessionStore.saveSession(sessionFile, options.toSessionPayload());
  logger.info('Session saved to $sessionFile');
  if (options.sessionTokenMode == 'plain') {
    logger.warn('Session file stores tokens in plain text. Keep file permissions restricted.');
  } else {
    logger.info('Session stores token env references only. Keep those environment variables available for resume.');
  }
}

void _logRuntimeHeader(
  RuntimeOptions options,
  ProviderRef sourceRef,
  ProviderRef targetRef,
  PreparedRun prepared,
  ConsoleLogger logger,
) {
  logger.info('Dart runtime loaded');
  logger.info('  Command: ${options.commandName}');
  logger.info('  Source: ${options.sourceProvider} (${sourceRef.resource})');
  logger.info('  Target: ${options.targetProvider} (${targetRef.resource})');
  logger.info('  Order: ${options.migrationOrder}');
  logger.info(
    '  Tag range: ${options.fromTag.isEmpty ? '<start>' : options.fromTag} -> ${options.toTag.isEmpty ? '<end>' : options.toTag}',
  );
  logger.info('  Dry-run: ${options.dryRun}');
  logger.info('  Skip tags: ${options.skipTagMigration}');
  logger.info('  Download workers: ${options.downloadWorkers}');
  logger.info('  Release workers: ${options.releaseWorkers}');
  logger.info('  Session token mode: ${options.sessionTokenMode}');
  if (options.settingsProfile.isNotEmpty) {
    logger.info('  Settings profile: ${options.settingsProfile}');
  }
  logger.info('  Checkpoint file: ${options.effectiveCheckpointFile()}');
  logger.info('  Results root: ${prepared.resultsRoot.path}');
  logger.info('  Run workdir: ${prepared.runWorkdir.path}');
  if (options.tagsFile.isNotEmpty) {
    logger.info('  Tags file: ${options.tagsFile}');
  }
}
