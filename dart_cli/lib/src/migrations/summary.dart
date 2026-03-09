import 'dart:convert';
import 'dart:io';

import '../core/adapters/provider_adapter.dart';
import '../core/logging.dart';
import '../core/types/phase.dart';
import '../models/runtime_options.dart';
import 'selection.dart';

final class SummaryWriter {
  const SummaryWriter._();

  static String checkpointSignature(RuntimeOptions options, ProviderRef sourceRef, ProviderRef targetRef) {
    return <String>[
      options.migrationOrder,
      sourceRef.resource,
      targetRef.resource,
      options.fromTag.isEmpty ? '<start>' : options.fromTag,
      options.toTag.isEmpty ? '<end>' : options.toTag,
    ].join('|');
  }

  static String buildRetryCommand(RuntimeOptions options, File failedTagsFile) {
    final List<String> parts = <String>[
      publicCommandName,
      commandResume,
      '--tags-file',
      failedTagsFile.path,
    ];

    if (options.sessionFile.isNotEmpty) {
      parts.addAll(<String>['--session-file', options.sessionFile]);
    }

    if (options.noBanner) {
      parts.add('--no-banner');
    }

    if (options.quiet) {
      parts.add('--quiet');
    }

    if (options.jsonOutput) {
      parts.add('--json');
    }

    if (options.sessionTokenMode == 'plain') {
      parts.addAll(<String>['--session-token-mode', 'plain']);
    }

    if (options.settingsProfile.isNotEmpty) {
      parts.addAll(<String>['--settings-profile', options.settingsProfile]);
    }

    return parts.map(_quoteShell).join(' ');
  }

  static String retryCommandShell() {
    return Platform.isWindows ? 'windows' : 'posix-sh';
  }

  static Future<void> writeSummary({
    required ConsoleLogger logger,
    required RuntimeOptions options,
    required ProviderRef sourceRef,
    required ProviderRef targetRef,
    required String logPath,
    required String checkpointPath,
    required Directory workdir,
    required Set<String> failedTags,
    required TagMigrationCounts tagCounts,
    required ReleaseMigrationCounts releaseCounts,
  }) async {
    final List<String> sortedFailed = failedTags.toList(growable: true)..sort(SelectionService.semverCompare);
    final File failedTagsFile = File('${workdir.path}/failed-tags.txt');
    failedTagsFile.writeAsStringSync(sortedFailed.isEmpty ? '' : '${sortedFailed.join('\n')}\n');

    final String retryCommand = sortedFailed.isEmpty ? '' : buildRetryCommand(options, failedTagsFile);
    final Map<String, dynamic> payload = <String, dynamic>{
      'schema_version': 2,
      'command': options.commandName,
      'order':
          '${SelectionService.capitalizeProvider(options.sourceProvider)} -> ${SelectionService.capitalizeProvider(options.targetProvider)}',
      'source': sourceRef.resource,
      'target': targetRef.resource,
      'tag_range': <String, String>{
        'from': options.fromTag.isEmpty ? '<start>' : options.fromTag,
        'to': options.toTag.isEmpty ? '<end>' : options.toTag,
      },
      'dry_run': options.dryRun,
      'counts': <String, int>{
        'tags_created': tagCounts.created,
        'tags_skipped': tagCounts.skipped,
        'tags_failed': tagCounts.failed,
        'tags_would_create': tagCounts.wouldCreate,
        'releases_created': releaseCounts.created,
        'releases_updated': releaseCounts.updated,
        'releases_skipped': releaseCounts.skipped,
        'releases_failed': releaseCounts.failed,
        'releases_would_create': releaseCounts.wouldCreate,
      },
      'paths': <String, String>{
        'jsonl_log': logPath,
        'checkpoint': checkpointPath,
        'workdir': workdir.path,
        'failed_tags': failedTagsFile.path,
      },
      'failed_tags': sortedFailed,
      'retry_command': retryCommand,
      'retry_command_shell': retryCommand.isEmpty ? '' : retryCommandShell(),
    };

    final File summaryFile = File('${workdir.path}/summary.json');
    summaryFile.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(payload)}\n');

    logger.info('Migration summary');
    logger.info('  Command: ${options.commandName}');
    logger.info('  Source: ${sourceRef.resource}');
    logger.info('  Target: ${targetRef.resource}');
    logger.info(
      '  Tag range: ${options.fromTag.isEmpty ? '<start>' : options.fromTag} -> ${options.toTag.isEmpty ? '<end>' : options.toTag}',
    );
    logger.info('  Dry-run: ${options.dryRun}');
    logger.info('  Tags created: ${tagCounts.created}');
    logger.info('  Tags skipped: ${tagCounts.skipped}');
    logger.info('  Tags failed: ${tagCounts.failed}');
    logger.info('  Tags dry-run (would create): ${tagCounts.wouldCreate}');
    logger.info('  Releases created: ${releaseCounts.created}');
    logger.info('  Releases updated: ${releaseCounts.updated}');
    logger.info('  Releases skipped: ${releaseCounts.skipped}');
    logger.info('  Releases failed: ${releaseCounts.failed}');
    logger.info('  Releases dry-run (would create): ${releaseCounts.wouldCreate}');
    logger.info('  JSONL log: $logPath');
    logger.info('  Summary JSON: ${summaryFile.path}');
    logger.info('  Failed tags file: ${failedTagsFile.path}');
    logger.info('  Workdir: ${workdir.path}');

    if (retryCommand.isNotEmpty) {
      logger.info('  Retry command shell: ${retryCommandShell()}');
      logger.info('  Retry command: $retryCommand');
    }
  }

  static String _quoteShell(String value) {
    if (RegExp(r'^[A-Za-z0-9_./:-]+$').hasMatch(value)) {
      return value;
    }

    if (Platform.isWindows) {
      final String escaped = value.replaceAll('"', r'\"');
      return '"$escaped"';
    }

    return "'${value.replaceAll("'", "'\\''")}'";
  }
}
