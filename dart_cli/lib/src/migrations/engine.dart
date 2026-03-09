import 'dart:io';

import '../core/adapters/provider_adapter.dart';
import '../core/checkpoint.dart';
import '../core/files.dart';
import '../core/logging.dart';
import '../core/types/phase.dart';
import '../models.dart';
import '../providers/registry.dart';
import 'release_phase.dart';
import 'selection.dart';
import 'summary.dart';
import 'tag_phase.dart';

class MigrationEngine {
  MigrationEngine({
    required this.registry,
    required this.logger,
  });

  final ProviderRegistry registry;
  final ConsoleLogger logger;

  Future<void> run(RuntimeOptions options, ProviderRef sourceRef, ProviderRef targetRef) async {
    registry.requireSupportedPair(options.sourceProvider, options.targetProvider);
    final ProviderAdapter source = registry.get(options.sourceProvider);
    final ProviderAdapter target = registry.get(options.targetProvider);

    final Directory workdir = ensureDir(options.effectiveWorkdir());
    final String logPath = options.logFile.isNotEmpty ? options.logFile : '${workdir.path}/migration-log.jsonl';
    File(logPath).writeAsStringSync('');

    final String checkpointPath = options.effectiveCheckpointFile();
    final String checkpointSig = checkpointSignature(options, sourceRef, targetRef);
    final Map<String, String> checkpointState = loadCheckpointState(checkpointPath, checkpointSig);
    logger.info('Checkpoint loaded: ${checkpointState.length} entries');

    logger.info('Fetching releases from ${capitalizeProvider(options.sourceProvider)}: ${sourceRef.resource}');
    final List<Map<String, dynamic>> releases = await source.listReleases(sourceRef, options.sourceToken);
    logger.info('Releases found in ${capitalizeProvider(options.sourceProvider)}: ${releases.length}');

    List<String> selectedTags = collectSelectedTags(releases, options.fromTag, options.toTag);
    selectedTags = applyTagsFilter(selectedTags, options.tagsFile);
    if (selectedTags.isEmpty) {
      throw StateError('No releases found in selected range');
    }

    if (options.fromTag.isNotEmpty || options.toTag.isNotEmpty) {
      logger.info(
        'Selected releases in range ${options.fromTag.isEmpty ? '<start>' : options.fromTag}..${options.toTag.isEmpty ? '<end>' : options.toTag}: ${selectedTags.length}',
      );
    } else {
      logger.info('Selected releases: ${selectedTags.length}');
    }

    final Set<String> targetTags = (await target.listTags(targetRef, options.targetToken)).toSet();
    final Set<String> targetReleaseTags =
        await target.listTargetReleaseTags(targetRef, options.targetToken, targetTags);
    final MigrationContext ctx = MigrationContext(
      sourceRef: sourceRef,
      targetRef: targetRef,
      source: source,
      target: target,
      options: options,
      logPath: logPath,
      workdir: workdir,
      checkpointPath: checkpointPath,
      checkpointSignature: checkpointSig,
      checkpointState: checkpointState,
      selectedTags: selectedTags,
      targetTags: targetTags,
      targetReleaseTags: targetReleaseTags,
      failedTags: <String>{},
      releases: releases,
    );

    final TagMigrationCounts tagCounts = await TagPhaseRunner(logger: logger).run(ctx);
    final ReleaseMigrationCounts releaseCounts = await ReleasePhaseRunner(logger: logger).run(ctx);
    await writeSummary(
      logger: logger,
      options: options,
      sourceRef: sourceRef,
      targetRef: targetRef,
      logPath: logPath,
      checkpointPath: checkpointPath,
      workdir: workdir,
      failedTags: ctx.failedTags,
      tagCounts: tagCounts,
      releaseCounts: releaseCounts,
    );

    if (tagCounts.failed > 0 || releaseCounts.failed > 0) {
      throw StateError('Migration finished with failures');
    }
  }
}
