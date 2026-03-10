import '../core/checkpoint.dart';
import '../core/exceptions/authentication_error.dart';
import '../core/jsonl.dart';
import '../core/logging.dart';
import '../core/types/canonical_release.dart';
import '../core/types/phase.dart';
import '../models/migration_context.dart';
import 'selection.dart';

class TagPhaseRunner {
  TagPhaseRunner({required this.logger});

  final ConsoleLogger logger;

  void _appendLog(
    String logPath, {
    required String status,
    required String tag,
    required String message,
    required int assetCount,
    required int durationMs,
    required bool dryRun,
  }) {
    JsonlLogWriter.appendLog(
      logPath,
      status: status,
      tag: tag,
      message: message,
      assetCount: assetCount,
      durationMs: durationMs,
      dryRun: dryRun,
    );
  }

  void _checkpointMark(
    String checkpointPath,
    Map<String, String> checkpointState, {
    required String signature,
    required String key,
    required String tag,
    required String status,
    required String message,
  }) {
    CheckpointStore.appendCheckpoint(
      checkpointPath,
      signature: signature,
      key: key,
      tag: tag,
      status: status,
      message: message,
    );
    checkpointState[key] = status;
  }

  Future<bool> _targetTagExists(MigrationContext ctx, String tag) async {
    try {
      return await ctx.target.tagExists(ctx.targetRef, ctx.options.targetToken, tag);
    } catch (_) {
      return false;
    }
  }

  void _progress(MigrationContext ctx, int index, int total, String message) {
    final int percent = total <= 0 ? 0 : (index * 100 ~/ total);
    if (ctx.options.progressBar && total > 0) {
      const int width = 20;
      final int rawFilled = width * index ~/ total;
      final int filled = rawFilled < 0
          ? 0
          : rawFilled > width
              ? width
              : rawFilled;
      final String bar = ''.padRight(filled, '#') + ''.padRight(width - filled, '-');
      logger.info('[$index/$total - ${percent.toString().padLeft(3)}%] [$bar] $message');
      return;
    }

    logger.info('[$index/$total - ${percent.toString().padLeft(3)}%] $message');
  }

  bool _handleCheckpointSkip(
    MigrationContext ctx,
    TagMigrationCounts counts,
    String tag,
    String checkpointStatus,
  ) {
    if (!CheckpointStore.isTerminalTagStatus(checkpointStatus) || !ctx.targetTags.contains(tag)) {
      return false;
    }

    counts.skipped += 1;
    _appendLog(
      ctx.logPath,
      status: 'tag_skipped_existing',
      tag: tag,
      message: 'Checkpoint skip ($checkpointStatus)',
      assetCount: 0,
      durationMs: 0,
      dryRun: false,
    );
    logger.info('[$tag] checkpoint skip: tag already processed');
    return true;
  }

  Future<bool> _handleExistingTargetTag(
    MigrationContext ctx,
    TagMigrationCounts counts,
    String checkpointKey,
    String tag,
  ) async {
    final bool targetTagExists = ctx.targetTags.contains(tag) || await _targetTagExists(ctx, tag);
    if (!targetTagExists) {
      return false;
    }

    ctx.targetTags.add(tag);
    counts.skipped += 1;
    _appendLog(
      ctx.logPath,
      status: 'tag_skipped_existing',
      tag: tag,
      message: 'Tag already exists in ${SelectionService.capitalizeProvider(ctx.options.targetProvider)}',
      assetCount: 0,
      durationMs: 0,
      dryRun: false,
    );
    _checkpointMark(
      ctx.checkpointPath,
      ctx.checkpointState,
      signature: ctx.checkpointSignature,
      key: checkpointKey,
      tag: tag,
      status: 'tag_skipped_existing',
      message: 'Tag already exists in ${SelectionService.capitalizeProvider(ctx.options.targetProvider)}',
    );
    return true;
  }

  Future<({CanonicalRelease canonical, String commitSha})> _resolveCanonicalAndCommit(
      MigrationContext ctx, String tag) async {
    final Map<String, dynamic>? releasePayload = SelectionService.releaseByTag(ctx.releases, tag);
    final CanonicalRelease canonical = ctx.source.toCanonicalRelease(releasePayload ?? <String, dynamic>{});
    try {
      final String commitSha = await ctx.source.resolveCommitShaForMigration(
        ctx.sourceRef,
        ctx.options.sourceToken,
        tag,
        canonical,
      );
      return (canonical: canonical, commitSha: commitSha);
    } catch (_) {
      return (canonical: canonical, commitSha: '');
    }
  }

  bool _handleMissingCommit(MigrationContext ctx, TagMigrationCounts counts, String tag, String commitSha) {
    if (commitSha.isNotEmpty) {
      return false;
    }

    counts.failed += 1;
    ctx.failedTags.add(tag);
    _appendLog(
      ctx.logPath,
      status: 'tag_failed',
      tag: tag,
      message: 'Tag commit SHA not found in ${SelectionService.capitalizeProvider(ctx.options.sourceProvider)}',
      assetCount: 0,
      durationMs: 0,
      dryRun: false,
    );
    logger.warn('[$tag] tag migration failed: commit SHA not found');
    return true;
  }

  bool _handleDryRun(MigrationContext ctx, TagMigrationCounts counts, String tag) {
    if (!ctx.options.dryRun) {
      return false;
    }

    counts.wouldCreate += 1;
    ctx.targetTags.add(tag);
    _appendLog(
      ctx.logPath,
      status: 'tag_created',
      tag: tag,
      message: 'Dry-run: tag would be created',
      assetCount: 0,
      durationMs: 0,
      dryRun: true,
    );
    return true;
  }

  Future<void> _createTag(
    MigrationContext ctx,
    TagMigrationCounts counts,
    String checkpointKey,
    String tag,
    String commitSha,
    CanonicalRelease canonical,
  ) async {
    try {
      await ctx.target.createTagForMigration(
        ctx.targetRef,
        ctx.options.targetToken,
        tag,
        commitSha,
        canonical,
      );
      ctx.targetTags.add(tag);
      counts.created += 1;
      _appendLog(
        ctx.logPath,
        status: 'tag_created',
        tag: tag,
        message: 'Tag migrated successfully',
        assetCount: 0,
        durationMs: 0,
        dryRun: false,
      );
      _checkpointMark(
        ctx.checkpointPath,
        ctx.checkpointState,
        signature: ctx.checkpointSignature,
        key: checkpointKey,
        tag: tag,
        status: 'tag_created',
        message: 'Tag migrated successfully',
      );
    } catch (exc) {
      final String message = exc.toString().toLowerCase();
      if (exc is AuthenticationError) {
        counts.failed += 1;
        ctx.failedTags.add(tag);
        _appendLog(
          ctx.logPath,
          status: 'tag_failed',
          tag: tag,
          message: 'Tag creation failed: authentication error',
          assetCount: 0,
          durationMs: 0,
          dryRun: false,
        );
        _checkpointMark(
          ctx.checkpointPath,
          ctx.checkpointState,
          signature: ctx.checkpointSignature,
          key: checkpointKey,
          tag: tag,
          status: 'tag_failed',
          message: 'Tag creation failed: authentication error',
        );
        logger.warn('[$tag] tag creation failed: authentication error: $exc');
        return;
      }

      final bool alreadyExists =
          message.contains('409') || message.contains('already exists') || await _targetTagExists(ctx, tag);
      if (alreadyExists) {
        ctx.targetTags.add(tag);
        counts.skipped += 1;
        _checkpointMark(
          ctx.checkpointPath,
          ctx.checkpointState,
          signature: ctx.checkpointSignature,
          key: checkpointKey,
          tag: tag,
          status: 'tag_skipped_existing',
          message: 'Tag detected after create attempt',
        );
        return;
      }

      counts.failed += 1;
      ctx.failedTags.add(tag);
      _appendLog(
        ctx.logPath,
        status: 'tag_failed',
        tag: tag,
        message: 'Failed to create tag in ${SelectionService.capitalizeProvider(ctx.options.targetProvider)}: $exc',
        assetCount: 0,
        durationMs: 0,
        dryRun: false,
      );
      _checkpointMark(
        ctx.checkpointPath,
        ctx.checkpointState,
        signature: ctx.checkpointSignature,
        key: checkpointKey,
        tag: tag,
        status: 'tag_failed',
        message: 'Failed to create tag in ${SelectionService.capitalizeProvider(ctx.options.targetProvider)}: $exc',
      );
      logger.warn(
          '[$tag] failed to create tag in ${SelectionService.capitalizeProvider(ctx.options.targetProvider)}: $exc');
    }
  }

  Future<void> _migrateTag(MigrationContext ctx, TagMigrationCounts counts, int index) async {
    final String tag = ctx.selectedTags[index];
    _progress(ctx, index + 1, ctx.selectedTags.length, 'Tag $tag');
    final String checkpointKey = 'tag:$tag';
    final String checkpointStatus = ctx.checkpointState[checkpointKey] ?? '';
    if (_handleCheckpointSkip(ctx, counts, tag, checkpointStatus)) {
      return;
    }

    if (await _handleExistingTargetTag(ctx, counts, checkpointKey, tag)) {
      return;
    }

    final ({CanonicalRelease canonical, String commitSha}) resolved = await _resolveCanonicalAndCommit(ctx, tag);
    if (_handleMissingCommit(ctx, counts, tag, resolved.commitSha)) {
      return;
    }

    if (_handleDryRun(ctx, counts, tag)) {
      return;
    }

    await _createTag(ctx, counts, checkpointKey, tag, resolved.commitSha, resolved.canonical);
  }

  Future<TagMigrationCounts> run(MigrationContext ctx) async {
    final TagMigrationCounts counts = TagMigrationCounts();
    if (ctx.options.skipTagMigration) {
      logger.info('Tag migration is disabled (--skip-tags)');
      return counts;
    }

    logger.info('Starting tag migration (tags first, then releases)');
    for (int index = 0; index < ctx.selectedTags.length; index += 1) {
      await _migrateTag(ctx, counts, index);
    }

    return counts;
  }
}
