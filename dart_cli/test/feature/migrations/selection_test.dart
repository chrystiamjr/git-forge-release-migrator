import 'dart:io';

import 'package:gfrm_dart/src/migrations/selection.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('selection', () {
    test('capitalizeProvider uppercases first letter only', () {
      expect(capitalizeProvider('github'), 'Github');
      expect(capitalizeProvider(''), '');
    });

    test('semverCompare orders semver tags numerically', () {
      expect(semverCompare('v1.2.3', 'v1.2.3'), 0);
      expect(semverCompare('v1.2.3', 'v1.2.4'), lessThan(0));
      expect(semverCompare('v2.0.0', 'v1.9.9'), greaterThan(0));
    });

    test('semverCompare keeps semver before non-semver', () {
      expect(semverCompare('v1.0.0', 'release-1'), lessThan(0));
      expect(semverCompare('release-1', 'v1.0.0'), greaterThan(0));
    });

    test('collectSelectedTags keeps semver unique and applies inclusive range', () {
      final List<Map<String, dynamic>> releases = <Map<String, dynamic>>[
        <String, dynamic>{'tag_name': 'v1.0.0'},
        <String, dynamic>{'tag_name': 'v1.2.0'},
        <String, dynamic>{'tag_name': 'v1.2.0'},
        <String, dynamic>{'tag_name': 'v2.0.0'},
        <String, dynamic>{'tag_name': 'latest'},
      ];

      final List<String> selected = collectSelectedTags(releases, 'v1.0.0', 'v2.0.0');

      expect(selected, <String>['v1.0.0', 'v1.2.0', 'v2.0.0']);
    });

    test('releaseByTag returns matching release map', () {
      final List<Map<String, dynamic>> releases = <Map<String, dynamic>>[
        <String, dynamic>{'tag_name': 'v1.0.0', 'name': 'R1'},
        <String, dynamic>{'tag_name': 'v2.0.0', 'name': 'R2'},
      ];

      final Map<String, dynamic>? hit = releaseByTag(releases, 'v2.0.0');
      final Map<String, dynamic>? miss = releaseByTag(releases, 'v3.0.0');

      expect(hit?['name'], 'R2');
      expect(miss, isNull);
    });

    test('loadTagsFile ignores comments and blanks', () {
      final Directory temp = Directory.systemTemp.createTempSync('gfrm-dart-tags-file-');
      addTearDown(() => temp.deleteSync(recursive: true));

      final String tagsPath = p.join(temp.path, 'tags.txt');
      File(tagsPath).writeAsStringSync('# comment\n\nv1.0.0\n v2.0.0 \n');

      final Set<String> tags = loadTagsFile(tagsPath);
      expect(tags, <String>{'v1.0.0', 'v2.0.0'});
    });

    test('loadTagsFile throws for missing file', () {
      expect(() => loadTagsFile('/tmp/gfrm-missing-tags-file.txt'), throwsStateError);
    });

    test('applyTagsFilter returns only allowed tags', () {
      final Directory temp = Directory.systemTemp.createTempSync('gfrm-dart-tags-filter-');
      addTearDown(() => temp.deleteSync(recursive: true));

      final String tagsPath = p.join(temp.path, 'tags.txt');
      File(tagsPath).writeAsStringSync('v1.0.0\nv2.0.0\n');

      final List<String> filtered = applyTagsFilter(<String>['v1.0.0', 'v1.5.0', 'v2.0.0'], tagsPath);
      expect(filtered, <String>['v1.0.0', 'v2.0.0']);
    });

    test('reserveOutputName sanitizes and prevents duplicates', () {
      final Set<String> used = <String>{};

      final String first = reserveOutputName(used, 'path/to/my file.tar.gz');
      final String second = reserveOutputName(used, 'path/to/my file.tar.gz');

      expect(first, 'my_file.tar.gz');
      expect(second, 'my_file.tar-2.gz');
      expect(used.contains(first), isTrue);
      expect(used.contains(second), isTrue);
    });
  });
}
