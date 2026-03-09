import 'dart:convert';
import 'dart:io';

import 'package:gfrm_dart/src/core/adapters/provider_adapter.dart';
import 'package:gfrm_dart/src/core/logging.dart';
import 'package:gfrm_dart/src/core/types/phase.dart';
import 'package:gfrm_dart/src/migrations/summary.dart';
import 'package:gfrm_dart/src/models/runtime_options.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

RuntimeOptions buildRuntimeOptionsForSummary({
  String fromTag = '',
  String toTag = '',
  String sessionFile = '',
  bool noBanner = false,
  bool quiet = false,
  bool jsonOutput = false,
  String sessionTokenMode = 'env',
}) {
  return RuntimeOptions(
    commandName: commandResume,
    sourceProvider: 'github',
    sourceUrl: 'https://github.com/acme/source',
    sourceToken: 'src-token',
    targetProvider: 'gitlab',
    targetUrl: 'https://gitlab.com/acme/target',
    targetToken: 'dst-token',
    migrationOrder: 'github-to-gitlab',
    skipTagMigration: false,
    fromTag: fromTag,
    toTag: toTag,
    dryRun: false,
    nonInteractive: true,
    workdir: '',
    logFile: '',
    loadSession: true,
    saveSession: false,
    resumeSession: true,
    sessionFile: sessionFile,
    sessionTokenMode: sessionTokenMode,
    sessionSourceTokenEnv: 'SRC_ENV',
    sessionTargetTokenEnv: 'DST_ENV',
    settingsProfile: 'default',
    downloadWorkers: 4,
    releaseWorkers: 1,
    checkpointFile: '',
    tagsFile: '',
    noBanner: noBanner,
    quiet: quiet,
    jsonOutput: jsonOutput,
    progressBar: false,
    demoMode: false,
    demoReleases: 5,
    demoSleepSeconds: 1.0,
  );
}

ProviderRef buildProviderRef(String provider, String resource) {
  return ProviderRef(
    provider: provider,
    rawUrl: 'https://example.com/$resource',
    baseUrl: 'https://example.com',
    host: 'example.com',
    resource: resource,
  );
}

void main() {
  group('summary', () {
    test('checkpointSignature includes placeholders when range is empty', () {
      final RuntimeOptions options = buildRuntimeOptionsForSummary(fromTag: '', toTag: '');
      final ProviderRef source = buildProviderRef('github', 'acme/source');
      final ProviderRef target = buildProviderRef('gitlab', 'acme/target');

      final String signature = SummaryWriter.checkpointSignature(options, source, target);

      expect(signature, 'github-to-gitlab|acme/source|acme/target|<start>|<end>');
    });

    test('buildRetryCommand keeps command flags and shell quoting', () {
      final RuntimeOptions options = buildRuntimeOptionsForSummary(
        sessionFile: '/tmp/my session.json',
        noBanner: true,
        quiet: true,
        jsonOutput: true,
        sessionTokenMode: 'plain',
      );
      final File failedTags = File('/tmp/failed tags.txt');

      final String command = SummaryWriter.buildRetryCommand(options, failedTags);

      expect(command, startsWith('gfrm resume --tags-file '));
      if (Platform.isWindows) {
        expect(command, contains('"/tmp/failed tags.txt"'));
        expect(command, contains('--session-file "/tmp/my session.json"'));
      } else {
        expect(command, contains("'/tmp/failed tags.txt'"));
        expect(command, contains("--session-file '/tmp/my session.json'"));
      }
      expect(command, contains('--no-banner'));
      expect(command, contains('--quiet'));
      expect(command, contains('--json'));
      expect(command, contains('--session-token-mode plain'));
      expect(command, contains('--settings-profile default'));
    });

    test('writeSummary persists summary and failed-tags artifacts', () async {
      final Directory temp = Directory.systemTemp.createTempSync('gfrm-dart-summary-');
      addTearDown(() => temp.deleteSync(recursive: true));

      final RuntimeOptions options = buildRuntimeOptionsForSummary(fromTag: 'v1.0.0', toTag: 'v2.0.0');
      final ProviderRef source = buildProviderRef('github', 'acme/source');
      final ProviderRef target = buildProviderRef('gitlab', 'acme/target');
      final ConsoleLogger logger = ConsoleLogger(quiet: true, jsonOutput: false);

      final TagMigrationCounts tagCounts = TagMigrationCounts()
        ..created = 2
        ..skipped = 1
        ..failed = 1
        ..wouldCreate = 0;
      final ReleaseMigrationCounts releaseCounts = ReleaseMigrationCounts()
        ..created = 1
        ..updated = 1
        ..skipped = 2
        ..failed = 1
        ..wouldCreate = 0;

      final String logPath = p.join(temp.path, 'migration-log.jsonl');
      final String checkpointPath = p.join(temp.path, 'checkpoints', 'state.jsonl');

      await SummaryWriter.writeSummary(
        logger: logger,
        options: options,
        sourceRef: source,
        targetRef: target,
        logPath: logPath,
        checkpointPath: checkpointPath,
        workdir: temp,
        failedTags: <String>{'v2.0.0', 'v1.0.0'},
        tagCounts: tagCounts,
        releaseCounts: releaseCounts,
      );

      final File failedTagsFile = File(p.join(temp.path, 'failed-tags.txt'));
      final File summaryFile = File(p.join(temp.path, 'summary.json'));

      expect(failedTagsFile.existsSync(), isTrue);
      expect(summaryFile.existsSync(), isTrue);
      expect(failedTagsFile.readAsStringSync(), 'v1.0.0\nv2.0.0\n');

      final Map<String, dynamic> summary = jsonDecode(summaryFile.readAsStringSync()) as Map<String, dynamic>;
      expect(summary['schema_version'], 2);
      expect(summary['command'], commandResume);
      expect(summary['source'], 'acme/source');
      expect(summary['target'], 'acme/target');
      expect((summary['tag_range'] as Map<String, dynamic>)['from'], 'v1.0.0');
      expect((summary['tag_range'] as Map<String, dynamic>)['to'], 'v2.0.0');
      expect((summary['counts'] as Map<String, dynamic>)['tags_created'], 2);
      expect((summary['counts'] as Map<String, dynamic>)['releases_updated'], 1);
      expect((summary['failed_tags'] as List<dynamic>).cast<String>(), <String>['v1.0.0', 'v2.0.0']);
      expect((summary['paths'] as Map<String, dynamic>)['failed_tags'], failedTagsFile.path);
      expect((summary['retry_command'] ?? '').toString(), isNotEmpty);
      expect(summary['retry_command_shell'], Platform.isWindows ? 'windows' : 'posix-sh');
    });
  });
}
