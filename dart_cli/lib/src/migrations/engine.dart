import 'dart:io';

import '../core/adapters/provider_adapter.dart';
import '../core/checkpoint.dart';
import '../core/exceptions/migration_phase_error.dart';
import '../core/files.dart';
import '../core/logging.dart';
import '../core/types/phase.dart';
import '../models/migration_context.dart';
import '../models/runtime_options.dart';
import '../providers/registry.dart';
import 'migration_execution_result.dart';
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

  Future<MigrationContext> createContext(RuntimeOptions options, ProviderRef sourceRef, ProviderRef targetRef) async {
    registry.requireSupportedPair(options.sourceProvider, options.targetProvider);
    final ProviderAdapter source = registry.get(options.sourceProvider);
    final ProviderAdapter target = registry.get(options.targetProvider);

    final Directory workdir = FileSystemUtils.ensureDir(options.effectiveWorkdir());
    final String logPath = options.logFile.isNotEmpty ? options.logFile : '${workdir.path}/migration-log.jsonl';
    final File logFile = File(logPath);
    final Directory logParent = logFile.parent;
    if (!await logParent.exists()) {
      await logParent.create(recursive: true);
    }
    await logFile.writeAsString('');

    final String checkpointPath = options.effectiveCheckpointFile();
    final String checkpointSig = SummaryWriter.checkpointSignature(options, sourceRef, targetRef);
    final Map<String, String> checkpointState = CheckpointStore.loadCheckpointState(checkpointPath, checkpointSig);
    logger.info('Checkpoint loaded: ${checkpointState.length} entries');

    logger.info(
        'Fetching releases from ${SelectionService.capitalizeProvider(options.sourceProvider)}: ${sourceRef.resource}');
    final List<Map<String, dynamic>> releases = await source.listReleases(sourceRef, options.sourceToken);
    logger.info('Releases found in ${SelectionService.capitalizeProvider(options.sourceProvider)}: ${releases.length}');

    List<String> selectedTags = SelectionService.collectSelectedTags(releases, options.fromTag, options.toTag);
    selectedTags = SelectionService.applyTagsFilter(selectedTags, options.tagsFile);
    if (selectedTags.isEmpty) {
      throw MigrationPhaseError('No releases found in selected range');
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
    return MigrationContext(
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
  }

  Future<MigrationExecutionResult> execute(MigrationContext ctx) async {
    final TagMigrationCounts tagCounts = await TagPhaseRunner(logger: logger).run(ctx);
    final ReleaseMigrationCounts releaseCounts = await ReleasePhaseRunner(logger: logger).run(ctx);
    return MigrationExecutionResult(
      tagCounts: tagCounts,
      releaseCounts: releaseCounts,
    );
  }

  Future<void> run(RuntimeOptions options, ProviderRef sourceRef, ProviderRef targetRef) async {
    final MigrationContext ctx = await createContext(options, sourceRef, targetRef);
    final MigrationExecutionResult execution = await execute(ctx);

    await SummaryWriter.writeSummary(
      logger: logger,
      options: options,
      sourceRef: sourceRef,
      targetRef: targetRef,
      logPath: ctx.logPath,
      checkpointPath: ctx.checkpointPath,
      workdir: ctx.workdir,
      failedTags: ctx.failedTags,
      tagCounts: execution.tagCounts,
      releaseCounts: execution.releaseCounts,
    );

    if (execution.tagCounts.failed > 0 || execution.releaseCounts.failed > 0) {
      throw MigrationPhaseError('Migration finished with failures');
    }
  }
}
