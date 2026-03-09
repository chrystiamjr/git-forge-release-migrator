import 'dart:io';

import '../core/checkpoint.dart';
import '../core/files.dart';
import '../core/jsonl.dart';
import '../core/logging.dart';
import '../core/types/canonical_link.dart';
import '../core/types/canonical_release.dart';
import '../core/types/canonical_source.dart';
import '../core/types/phase.dart';
import '../models/migration_context.dart';
import 'selection.dart';

class ReleasePhaseRunner {
  ReleasePhaseRunner({required this.logger});

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

  String _progressMessage(int index, int total, String message, bool progressBar) {
    final int percent = total <= 0 ? 0 : (index * 100 ~/ total);
    if (!progressBar || total <= 0) {
      return '[$index/$total - ${percent.toString().padLeft(3)}%] $message';
    }

    const int width = 20;
    final int filled = width * index ~/ total;
    final String bar = '${'#' * filled}${'-' * (width - filled)}';
    return '[$index/$total - ${percent.toString().padLeft(3)}%] [$bar] $message';
  }

  File _prepareNotesFile(MigrationContext ctx, String tag, CanonicalRelease canonical) {
    final File notesFile = File('${ctx.workdir.path}/release-$tag-notes.md');
    notesFile.writeAsStringSync(canonical.descriptionMarkdown);
    if (ctx.source.requiresLegacySourceNotes(canonical)) {
      final String tagUrl = ctx.source.buildTagUrl(ctx.sourceRef, tag);
      notesFile.writeAsStringSync(
        '\n\n### Legacy Bitbucket Source Tag\n'
        'This Bitbucket tag has no `.gfrm-release-<tag>.json` manifest (legacy source).\n'
        'Migration proceeded with available notes and traceability link.\n'
        'Source tag: [$tag]($tagUrl)\n',
        mode: FileMode.append,
      );
    }
    return notesFile;
  }

  String _assetNameForLink(CanonicalLink link) {
    if (link.name.isNotEmpty) {
      return link.name;
    }

    final String candidate = link.directUrl.isNotEmpty ? link.directUrl : link.url;
    if (candidate.isEmpty) {
      return 'asset';
    }

    return candidate.split('?').first.split('/').last;
  }

  String _assetNameForSource(CanonicalSource source, String tag) {
    if (source.name.isNotEmpty) {
      return source.name;
    }

    if (source.url.isNotEmpty) {
      return source.url.split('?').first.split('/').last;
    }

    return '$tag.${source.format.isEmpty ? 'source' : source.format}';
  }

  Future<
      ({
        List<String> downloaded,
        List<Map<String, String>> missingLinks,
        List<Map<String, String>> missingSources,
        List<String> sourceFallbackFormats,
      })> _downloadAssets(
    MigrationContext ctx,
    String tag,
    CanonicalRelease canonical,
    Directory assetsDir,
  ) async {
    final List<String> downloaded = <String>[];
    final List<Map<String, String>> missingLinks = <Map<String, String>>[];
    final List<Map<String, String>> missingSources = <Map<String, String>>[];
    final List<String> sourceFallbackFormats = <String>[];
    final Set<String> usedNames = <String>{};

    for (final CanonicalLink link in canonical.assets.links) {
      final String name = _assetNameForLink(link);
      final String outputName = SelectionService.reserveOutputName(usedNames, name);
      final String outputPath = '${assetsDir.path}/$outputName';
      final bool ok = await ctx.source.downloadCanonicalLink(
        DownloadLinkInput(
          providerRef: ctx.sourceRef,
          token: ctx.options.sourceToken,
          tag: tag,
          link: link,
          outputPath: outputPath,
        ),
      );
      if (ok) {
        downloaded.add(outputPath);
      } else {
        logger.warn('[$tag] failed to download asset.link $name');
        final String url = link.url.isNotEmpty ? link.url : link.directUrl;
        missingLinks.add(<String, String>{'name': name, 'url': url});
      }
    }

    for (final CanonicalSource source in canonical.assets.sources) {
      final String name = _assetNameForSource(source, tag);
      final String prefix = source.format.isEmpty ? 'source' : source.format;
      final String outputName = SelectionService.reserveOutputName(usedNames, '$prefix-$name');
      final String outputPath = '${assetsDir.path}/$outputName';
      final bool ok = await ctx.source.downloadCanonicalSource(
        DownloadSourceInput(
          providerRef: ctx.sourceRef,
          token: ctx.options.sourceToken,
          tag: tag,
          source: source,
          outputPath: outputPath,
        ),
      );
      if (ok) {
        downloaded.add(outputPath);
        continue;
      }

      if (ctx.source.supportsSourceFallbackTagNotes()) {
        sourceFallbackFormats.add(source.format);
        logger.warn('[$tag] source asset $name unavailable, using tag link fallback');
        continue;
      }

      missingSources.add(<String, String>{'name': name, 'url': source.url});
      logger.warn('[$tag] source asset $name unavailable and no tag fallback');
    }

    return (
      downloaded: downloaded,
      missingLinks: missingLinks,
      missingSources: missingSources,
      sourceFallbackFormats: sourceFallbackFormats,
    );
  }

  void _appendSourceFallbackNotes(
    MigrationContext ctx,
    String tag,
    File notesFile,
    List<String> sourceFallbackFormats,
  ) {
    if (sourceFallbackFormats.isEmpty) {
      return;
    }

    final List<String> dedup = sourceFallbackFormats.toSet().toList(growable: true)..sort();
    final String sourceTagUrl = ctx.source.buildTagUrl(ctx.sourceRef, tag);
    notesFile.writeAsStringSync(
      '\n\n### Source Archives Fallback\n'
      'Some source archives could not be downloaded during migration.\n'
      'Fallback formats: `${dedup.join(',')}`\n'
      '${SelectionService.capitalizeProvider(ctx.options.sourceProvider)} tag: [$tag]($sourceTagUrl)\n',
      mode: FileMode.append,
    );
  }

  void _appendMissingAssetsNotes(
    File notesFile,
    List<Map<String, String>> missingLinks,
    List<Map<String, String>> missingSources,
  ) {
    if (missingLinks.isEmpty && missingSources.isEmpty) {
      return;
    }

    final StringBuffer buffer = StringBuffer();
    buffer.writeln('\n\n### Missing Assets During Migration');
    buffer.writeln('Some assets could not be downloaded and were not uploaded to this release.');

    if (missingLinks.isNotEmpty) {
      buffer.writeln('\n- Missing link assets:');
      for (final Map<String, String> item in missingLinks) {
        final String name = item['name'] ?? 'asset';
        final String url = item['url'] ?? '';
        buffer.writeln(url.isEmpty ? '  - $name' : '  - $name: $url');
      }
    }

    if (missingSources.isNotEmpty) {
      buffer.writeln('\n- Missing source assets:');
      for (final Map<String, String> item in missingSources) {
        final String name = item['name'] ?? 'source';
        final String url = item['url'] ?? '';
        buffer.writeln(url.isEmpty ? '  - $name' : '  - $name: $url');
      }
    }

    notesFile.writeAsStringSync(buffer.toString(), mode: FileMode.append);
  }

  Future<String> _publishRelease(
    MigrationContext ctx,
    String tag,
    String releaseName,
    File notesFile,
    List<String> downloaded,
    int expectedAssets,
    ExistingReleaseInfo existingInfo,
  ) async {
    try {
      return ctx.target.publishRelease(
        PublishReleaseInput(
          providerRef: ctx.targetRef,
          token: ctx.options.targetToken,
          tag: tag,
          releaseName: releaseName,
          notesFile: notesFile,
          downloadedFiles: downloaded,
          expectedAssets: expectedAssets,
          existingInfo: existingInfo,
        ),
      );
    } catch (_) {
      return 'failed';
    }
  }

  bool _handleAlreadyProcessed(
    MigrationContext ctx,
    String tag,
    String checkpointStatus,
    bool alreadyProcessed,
  ) {
    if (!alreadyProcessed) {
      return false;
    }

    _appendLog(
      ctx.logPath,
      status: 'skipped_existing',
      tag: tag,
      message: 'Checkpoint skip ($checkpointStatus)',
      assetCount: 0,
      durationMs: 0,
      dryRun: false,
    );
    logger.info('[$tag] checkpoint skip: release already processed');
    return true;
  }

  Future<
      ({
        CanonicalRelease canonical,
        File notesFile,
        String releaseName,
        int expectedAssets,
        ExistingReleaseInfo existingInfo,
      })?> _loadReleaseData(MigrationContext ctx, String tag) async {
    final Map<String, dynamic>? releasePayload = SelectionService.releaseByTag(ctx.releases, tag);
    if (releasePayload == null) {
      _appendLog(
        ctx.logPath,
        status: 'failed',
        tag: tag,
        message: 'Release missing from ${SelectionService.capitalizeProvider(ctx.options.sourceProvider)} payload',
        assetCount: 0,
        durationMs: 0,
        dryRun: false,
      );
      logger.warn('[$tag] failed: release missing in payload');
      return null;
    }

    final CanonicalRelease canonical = ctx.source.toCanonicalRelease(releasePayload);
    final File notesFile = _prepareNotesFile(ctx, tag, canonical);
    final int expectedLinkAssets = canonical.assets.links.length;
    final int expectedAssets = expectedLinkAssets + canonical.assets.sources.length;
    final ExistingReleaseInfo existingInfo = await ctx.target.existingReleaseInfo(
      ctx.targetRef,
      ctx.options.targetToken,
      tag,
      expectedLinkAssets,
    );
    return (
      canonical: canonical,
      notesFile: notesFile,
      releaseName: canonical.name,
      expectedAssets: expectedAssets,
      existingInfo: existingInfo,
    );
  }

  bool _handleExistingComplete(
    MigrationContext ctx,
    String checkpointKey,
    String tag,
    int expectedAssets,
    ExistingReleaseInfo existingInfo,
  ) {
    if (!existingInfo.exists || existingInfo.shouldRetry) {
      return false;
    }

    _appendLog(
      ctx.logPath,
      status: 'skipped_existing',
      tag: tag,
      message: 'Release already exists and is complete',
      assetCount: expectedAssets,
      durationMs: 0,
      dryRun: false,
    );
    _checkpointMark(
      ctx.checkpointPath,
      ctx.checkpointState,
      signature: ctx.checkpointSignature,
      key: checkpointKey,
      tag: tag,
      status: 'skipped_existing',
      message: 'Release already exists and is complete',
    );
    logger.info('[$tag] skip: release already exists and is complete');
    return true;
  }

  Future<bool> _ensureTargetTagReady(MigrationContext ctx, String tag) async {
    final bool tagReady =
        ctx.targetTags.contains(tag) || await ctx.target.tagExists(ctx.targetRef, ctx.options.targetToken, tag);
    if (tagReady) {
      return true;
    }

    _appendLog(
      ctx.logPath,
      status: 'failed',
      tag: tag,
      message:
          'Tag missing in ${SelectionService.capitalizeProvider(ctx.options.targetProvider)} after tag migration step',
      assetCount: 0,
      durationMs: 0,
      dryRun: false,
    );
    logger
        .warn('[$tag] failed: tag not available in ${SelectionService.capitalizeProvider(ctx.options.targetProvider)}');
    return false;
  }

  String _handleDryRun(
    MigrationContext ctx,
    String tag,
    int expectedAssets,
    ExistingReleaseInfo existingInfo,
  ) {
    if (!ctx.options.dryRun) {
      return '';
    }

    _appendLog(
      ctx.logPath,
      status: existingInfo.exists ? 'updated' : 'created',
      tag: tag,
      message: existingInfo.exists
          ? 'Dry-run: release would be resumed (${existingInfo.reason})'
          : 'Dry-run: release would be created',
      assetCount: expectedAssets,
      durationMs: 0,
      dryRun: true,
    );
    return 'would_create';
  }

  Future<String> _downloadAndPublish(
    MigrationContext ctx,
    String checkpointKey,
    String tag,
    String releaseName,
    File notesFile,
    CanonicalRelease canonical,
    int expectedAssets,
    ExistingReleaseInfo existingInfo,
    DateTime start,
  ) async {
    final Directory releaseDir = FileSystemUtils.ensureDir('${ctx.workdir.path}/release-$tag');
    final Directory assetsDir = FileSystemUtils.ensureDir('${releaseDir.path}/assets');
    final ({
      List<String> downloaded,
      List<Map<String, String>> missingLinks,
      List<Map<String, String>> missingSources,
      List<String> sourceFallbackFormats,
    }) assetsResult = await _downloadAssets(ctx, tag, canonical, assetsDir);
    _appendSourceFallbackNotes(ctx, tag, notesFile, assetsResult.sourceFallbackFormats);
    _appendMissingAssetsNotes(notesFile, assetsResult.missingLinks, assetsResult.missingSources);
    if (expectedAssets > 0 && assetsResult.downloaded.isEmpty) {
      _appendLog(
        ctx.logPath,
        status: 'failed',
        tag: tag,
        message: 'No release assets were downloaded',
        assetCount: 0,
        durationMs: 0,
        dryRun: false,
      );
      logger.warn('[$tag] failed: no assets downloaded');
      FileSystemUtils.cleanupDir(releaseDir.path);
      return 'failed';
    }

    final String publishStatus = await _publishRelease(
      ctx,
      tag,
      releaseName,
      notesFile,
      assetsResult.downloaded,
      expectedAssets,
      existingInfo,
    );
    final int durationMs = DateTime.now().difference(start).inMilliseconds;
    if (publishStatus == 'failed') {
      FileSystemUtils.cleanupDir(releaseDir.path);
      _appendLog(
        ctx.logPath,
        status: 'failed',
        tag: tag,
        message:
            'Release publish operation failed on ${SelectionService.capitalizeProvider(ctx.options.targetProvider)}',
        assetCount: assetsResult.downloaded.length,
        durationMs: 0,
        dryRun: false,
      );
      return 'failed';
    }

    final String finalStatus = existingInfo.exists ? 'updated' : 'created';
    final String finalMessage =
        existingInfo.exists ? 'Release resumed/updated successfully' : 'Release created successfully';
    _appendLog(
      ctx.logPath,
      status: finalStatus,
      tag: tag,
      message: finalMessage,
      assetCount: assetsResult.downloaded.length,
      durationMs: durationMs,
      dryRun: false,
    );
    _checkpointMark(
      ctx.checkpointPath,
      ctx.checkpointState,
      signature: ctx.checkpointSignature,
      key: checkpointKey,
      tag: tag,
      status: finalStatus,
      message: finalMessage,
    );
    logger.info(
        '[$tag] ${existingInfo.exists ? 'resumed/updated' : 'created'} with ${assetsResult.downloaded.length} asset(s)');
    FileSystemUtils.cleanupDir(releaseDir.path);
    return finalStatus;
  }

  Future<String> _processTag(MigrationContext ctx, int index, String tag) async {
    final DateTime start = DateTime.now();
    final String progress = _progressMessage(index, ctx.selectedTags.length, 'Release $tag', ctx.options.progressBar);
    final bool spinnerStarted = ctx.options.releaseWorkers == 1 ? logger.startSpinner(progress) : false;
    if (!spinnerStarted) {
      logger.info(progress);
    }

    try {
      final String checkpointKey = 'release:$tag';
      final String checkpointStatus = ctx.checkpointState[checkpointKey] ?? '';
      final bool alreadyProcessed = await ctx.target.isReleaseAlreadyProcessed(
        ctx.targetRef,
        ctx.options.targetToken,
        tag,
        checkpointStatus,
        ctx.targetReleaseTags,
      );
      if (_handleAlreadyProcessed(ctx, tag, checkpointStatus, alreadyProcessed)) {
        return 'skipped';
      }

      final ({
        CanonicalRelease canonical,
        File notesFile,
        String releaseName,
        int expectedAssets,
        ExistingReleaseInfo existingInfo,
      })? releaseData = await _loadReleaseData(ctx, tag);
      if (releaseData == null) {
        return 'failed';
      }

      if (_handleExistingComplete(
        ctx,
        checkpointKey,
        tag,
        releaseData.expectedAssets,
        releaseData.existingInfo,
      )) {
        return 'skipped';
      }

      final bool tagReady = await _ensureTargetTagReady(ctx, tag);
      if (!tagReady) {
        return 'failed';
      }

      final String dryRunStatus = _handleDryRun(
        ctx,
        tag,
        releaseData.expectedAssets,
        releaseData.existingInfo,
      );
      if (dryRunStatus.isNotEmpty) {
        return dryRunStatus;
      }

      return _downloadAndPublish(
        ctx,
        checkpointKey,
        tag,
        releaseData.releaseName,
        releaseData.notesFile,
        releaseData.canonical,
        releaseData.expectedAssets,
        releaseData.existingInfo,
        start,
      );
    } finally {
      if (spinnerStarted) {
        logger.stopSpinner();
      }
    }
  }

  Future<ReleaseMigrationCounts> run(MigrationContext ctx) async {
    final ReleaseMigrationCounts counts = ReleaseMigrationCounts();
    for (int index = 0; index < ctx.selectedTags.length; index += 1) {
      final String tag = ctx.selectedTags[index];
      final String status = await _processTag(ctx, index + 1, tag);
      if (status == 'created') {
        counts.created += 1;
      } else if (status == 'updated') {
        counts.updated += 1;
      } else if (status == 'skipped') {
        counts.skipped += 1;
      } else if (status == 'would_create') {
        counts.wouldCreate += 1;
      } else {
        counts.failed += 1;
        ctx.failedTags.add(tag);
      }
    }
    return counts;
  }
}
