import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/concurrency.dart';
import '../core/logging.dart';
import '../core/types/canonical_link.dart';
import '../core/types/canonical_release.dart';
import '../core/types/canonical_source.dart';
import '../core/types/phase.dart';
import '../models/migration_context.dart';
import 'selection.dart';

typedef _LinkedResults = ({bool ok, String name, String url, String outputPath});
typedef _LinkDownloadPlan = ({CanonicalLink link, String name, String outputPath});
typedef _SourceResults = ({bool ok, bool fallback, String format, String name, String url, String outputPath});
typedef _SourceDownloadPlan = ({CanonicalSource source, String name, String outputPath});

typedef DownloadedAssetResult = ({
  List<String> downloaded,
  List<Map<String, String>> missingLinks,
  List<Map<String, String>> missingSources,
  List<String> sourceFallbackFormats,
});

final class ReleaseAssetService {
  ReleaseAssetService({required this.logger});

  final ConsoleLogger logger;

  Future<File> prepareNotesFile(MigrationContext ctx, String tag, CanonicalRelease canonical) async {
    final File notesFile = File('${ctx.workdir.path}/release-$tag-notes.md');
    await notesFile.writeAsString(canonical.descriptionMarkdown);
    if (!ctx.source.requiresLegacySourceNotes(canonical)) {
      return notesFile;
    }

    final String tagUrl = ctx.source.buildTagUrl(ctx.sourceRef, tag);
    await notesFile.writeAsString(
      '\n\n### Legacy Bitbucket Source Tag\n'
      'This Bitbucket tag has no `.gfrm-release-<tag>.json` manifest (legacy source).\n'
      'Migration proceeded with available notes and traceability link.\n'
      'Source tag: [$tag]($tagUrl)\n',
      mode: FileMode.append,
    );

    return notesFile;
  }

  Future<DownloadedAssetResult> downloadAssets(
    MigrationContext ctx,
    String tag,
    CanonicalRelease canonical,
    Directory assetsDir,
  ) async {
    final List<_LinkDownloadPlan> linkPlans = _buildLinkPlans(canonical, assetsDir.path);
    final List<_SourceDownloadPlan> sourcePlans = _buildSourcePlans(tag, canonical, assetsDir.path, linkPlans);

    final List<_LinkedResults> linkResults = await Concurrency.mapWithLimit<_LinkDownloadPlan, _LinkedResults>(
      items: linkPlans,
      limit: ctx.options.downloadWorkers,
      task: (_LinkDownloadPlan plan, int _) async {
        final bool ok = await ctx.source.downloadCanonicalLink(
          DownloadLinkInput(
            providerRef: ctx.sourceRef,
            token: ctx.options.sourceToken,
            tag: tag,
            link: plan.link,
            outputPath: plan.outputPath,
          ),
        );
        return (
          ok: ok,
          name: plan.name,
          url: plan.link.url.isNotEmpty ? plan.link.url : plan.link.directUrl,
          outputPath: plan.outputPath,
        );
      },
    );

    final List<_SourceResults> sourceResults = await Concurrency.mapWithLimit<_SourceDownloadPlan, _SourceResults>(
      items: sourcePlans,
      limit: ctx.options.downloadWorkers,
      task: (_SourceDownloadPlan plan, int _) async {
        final bool ok = await ctx.source.downloadCanonicalSource(
          DownloadSourceInput(
            providerRef: ctx.sourceRef,
            token: ctx.options.sourceToken,
            tag: tag,
            source: plan.source,
            outputPath: plan.outputPath,
          ),
        );
        return (
          ok: ok,
          fallback: ctx.source.supportsSourceFallbackTagNotes(),
          format: plan.source.format,
          name: plan.name,
          url: plan.source.url,
          outputPath: plan.outputPath,
        );
      },
    );

    final List<String> downloaded = <String>[];
    final List<Map<String, String>> missingLinks = <Map<String, String>>[];
    final List<Map<String, String>> missingSources = <Map<String, String>>[];
    final List<String> sourceFallbackFormats = <String>[];

    for (final ({bool ok, String name, String url, String outputPath}) result in linkResults) {
      if (result.ok) {
        downloaded.add(result.outputPath);
      } else {
        logger.warn('[$tag] failed to download asset.link ${result.name}');
        missingLinks.add(<String, String>{'name': result.name, 'url': result.url});
      }
    }

    for (final _SourceResults result in sourceResults) {
      if (result.ok) {
        downloaded.add(result.outputPath);
        continue;
      }

      if (result.fallback) {
        sourceFallbackFormats.add(result.format);
        logger.warn('[$tag] source asset ${result.name} unavailable, using tag link fallback');
        continue;
      }

      missingSources.add(<String, String>{'name': result.name, 'url': result.url});
      logger.warn('[$tag] source asset ${result.name} unavailable and no tag fallback');
    }

    return (
      downloaded: downloaded,
      missingLinks: missingLinks,
      missingSources: missingSources,
      sourceFallbackFormats: sourceFallbackFormats,
    );
  }

  Future<void> appendSourceFallbackNotes(
    MigrationContext ctx,
    String tag,
    File notesFile,
    List<String> sourceFallbackFormats,
  ) async {
    if (sourceFallbackFormats.isEmpty) {
      return;
    }

    final List<String> dedup = sourceFallbackFormats.toSet().toList(growable: true)..sort();
    final String sourceTagUrl = ctx.source.buildTagUrl(ctx.sourceRef, tag);
    await notesFile.writeAsString(
      '\n\n### Source Archives Fallback\n'
      'Some source archives could not be downloaded during migration.\n'
      'Fallback formats: `${dedup.join(',')}`\n'
      '${SelectionService.capitalizeProvider(ctx.options.sourceProvider)} tag: [$tag]($sourceTagUrl)\n',
      mode: FileMode.append,
    );
  }

  Future<void> appendMissingAssetsNotes(
    File notesFile,
    List<Map<String, String>> missingLinks,
    List<Map<String, String>> missingSources,
  ) async {
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

    await notesFile.writeAsString(buffer.toString(), mode: FileMode.append);
  }

  List<_LinkDownloadPlan> _buildLinkPlans(CanonicalRelease canonical, String assetsPath) {
    final Set<String> usedNames = <String>{};
    final List<_LinkDownloadPlan> plans = <_LinkDownloadPlan>[];
    for (final CanonicalLink link in canonical.assets.links) {
      final String name = _assetNameForLink(link);
      final String outputName = SelectionService.reserveOutputName(usedNames, name);
      plans.add((link: link, name: name, outputPath: '$assetsPath/$outputName'));
    }
    return plans;
  }

  List<_SourceDownloadPlan> _buildSourcePlans(
    String tag,
    CanonicalRelease canonical,
    String assetsPath,
    List<_LinkDownloadPlan> linkPlans,
  ) {
    final Set<String> usedNames =
        linkPlans.map<String>((_LinkDownloadPlan plan) => p.basename(plan.outputPath)).toSet();

    final List<_SourceDownloadPlan> plans = <_SourceDownloadPlan>[];
    for (final CanonicalSource source in canonical.assets.sources) {
      final String name = _assetNameForSource(source, tag);
      final String prefix = source.format.isEmpty ? 'source' : source.format;
      final String outputName = SelectionService.reserveOutputName(usedNames, '$prefix-$name');
      plans.add((source: source, name: name, outputPath: '$assetsPath/$outputName'));
    }
    return plans;
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
}
