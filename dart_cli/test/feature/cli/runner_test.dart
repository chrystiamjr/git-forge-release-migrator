import 'dart:convert';
import 'dart:io';

import 'package:gfrm_dart/gfrm_dart.dart';
import 'package:gfrm_dart/src/models/runtime_options.dart';
import '../../support/temp_dir.dart';
import 'package:test/test.dart';

File _findSingleFile(Directory root, String name) {
  final List<File> matches = root
      .listSync(recursive: true)
      .whereType<File>()
      .where((File file) => file.path.endsWith('/$name'))
      .toList(growable: false);
  expect(matches, hasLength(1));
  return matches.single;
}

void main() {
  group('CliRunner', () {
    test('demo command writes summary and notes using tags file input', () async {
      final Directory temp = createTempDir('gfrm-demo-run-');
      final Directory resultsRoot = Directory('${temp.path}/results');
      final File tagsFile = File('${temp.path}/tags.txt')..writeAsStringSync('# comment\nv1.0.0\n\nv1.1.0\nv1.2.0\n');

      final int exitCode = await CliRunner.run(<String>[
        commandDemo,
        '--source-provider',
        'github',
        '--source-url',
        'https://github.com/acme/source',
        '--source-token',
        'src-token',
        '--target-provider',
        'gitlab',
        '--target-url',
        'https://gitlab.com/acme/target',
        '--target-token',
        'dst-token',
        '--workdir',
        resultsRoot.path,
        '--tags-file',
        tagsFile.path,
        '--demo-releases',
        '2',
        '--demo-sleep-seconds',
        '0',
        '--no-banner',
      ]);

      expect(exitCode, 0);

      final File summaryFile = _findSingleFile(resultsRoot, 'summary.json');
      final Map<String, dynamic> summary = jsonDecode(summaryFile.readAsStringSync()) as Map<String, dynamic>;
      expect(summary['command'], commandDemo);
      expect((summary['counts'] as Map<String, dynamic>)['releases_created'], 2);

      final Directory runDir = summaryFile.parent;
      expect(File('${runDir.path}/release-v1.0.0-notes.md').existsSync(), isTrue);
      expect(File('${runDir.path}/release-v1.1.0-notes.md').existsSync(), isTrue);
      expect(File('${runDir.path}/failed-tags.txt').readAsStringSync(), isEmpty);
    });

    test('demo command falls back to generated tags when tags file has no entries', () async {
      final Directory temp = createTempDir('gfrm-demo-fallback-');
      final Directory resultsRoot = Directory('${temp.path}/results');
      final File tagsFile = File('${temp.path}/empty-tags.txt')..writeAsStringSync('# only comments\n\n');

      final int exitCode = await CliRunner.run(<String>[
        commandDemo,
        '--source-provider',
        'github',
        '--source-url',
        'https://github.com/acme/source',
        '--source-token',
        'src-token',
        '--target-provider',
        'gitlab',
        '--target-url',
        'https://gitlab.com/acme/target',
        '--target-token',
        'dst-token',
        '--workdir',
        resultsRoot.path,
        '--tags-file',
        tagsFile.path,
        '--demo-releases',
        '3',
        '--demo-sleep-seconds',
        '0',
        '--no-banner',
      ]);

      expect(exitCode, 0);

      final File summaryFile = _findSingleFile(resultsRoot, 'summary.json');
      final Map<String, dynamic> summary = jsonDecode(summaryFile.readAsStringSync()) as Map<String, dynamic>;
      expect((summary['counts'] as Map<String, dynamic>)['releases_created'], 3);
      expect(File('${summaryFile.parent.path}/release-v3.2.1-notes.md').existsSync(), isTrue);
    });

    test('settings command without action returns help successfully', () async {
      final int exitCode = await CliRunner.run(<String>[commandSettings]);
      expect(exitCode, 0);
    });

    test('invalid migrate invocation returns non-zero', () async {
      final int exitCode = await CliRunner.run(<String>[commandMigrate]);
      expect(exitCode, 1);
    });
  });
}
