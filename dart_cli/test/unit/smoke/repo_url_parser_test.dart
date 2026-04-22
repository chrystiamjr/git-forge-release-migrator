import 'package:gfrm_dart/src/smoke/repo_url_parser.dart';
import 'package:test/test.dart';

void main() {
  group('parseRepoUrl', () {
    test('parses standard GitHub URL', () {
      final coords = parseRepoUrl('https://github.com/octocat/hello-world');
      expect(coords.host, 'github.com');
      expect(coords.workspace, 'octocat');
      expect(coords.repo, 'hello-world');
    });

    test('parses GitLab URL with trailing slash', () {
      final coords = parseRepoUrl('https://gitlab.com/group/project/');
      expect(coords.host, 'gitlab.com');
      expect(coords.workspace, 'group');
      expect(coords.repo, 'project');
    });

    test('preserves GitLab nested group namespace', () {
      final coords = parseRepoUrl('https://gitlab.com/group/subgroup/project.git');
      expect(coords.host, 'gitlab.com');
      expect(coords.workspace, 'group/subgroup');
      expect(coords.repo, 'project');
    });

    test('parses Bitbucket URL', () {
      final coords = parseRepoUrl('https://bitbucket.org/workspace/repo');
      expect(coords.host, 'bitbucket.org');
      expect(coords.workspace, 'workspace');
      expect(coords.repo, 'repo');
    });

    test('strips .git suffix', () {
      final coords = parseRepoUrl('https://github.com/owner/myrepo.git');
      expect(coords.repo, 'myrepo');
    });

    test('handles query string', () {
      final coords = parseRepoUrl('https://github.com/owner/myrepo?ref=main');
      expect(coords.repo, 'myrepo');
    });

    test('throws on empty input', () {
      expect(() => parseRepoUrl(''), throwsA(isA<FormatException>()));
      expect(() => parseRepoUrl('   '), throwsA(isA<FormatException>()));
    });

    test('throws when host missing', () {
      expect(() => parseRepoUrl('not-a-url'), throwsA(isA<FormatException>()));
    });

    test('throws when path too short', () {
      expect(() => parseRepoUrl('https://github.com/'), throwsA(isA<FormatException>()));
      expect(() => parseRepoUrl('https://github.com/owner'), throwsA(isA<FormatException>()));
    });
  });
}
