import 'package:gfrm_dart/src/core/adapters/provider_adapter.dart';
import 'package:gfrm_dart/src/providers/github.dart';
import 'package:test/test.dart';

void main() {
  group('GitHubAdapter', () {
    test('parseUrl supports https repository URLs', () {
      final GitHubAdapter adapter = GitHubAdapter();

      final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo.git');

      expect(ref.provider, 'github');
      expect(ref.baseUrl, 'https://github.com');
      expect(ref.host, 'github.com');
      expect(ref.resource, 'acme/repo');
      expect(ref.metadata['owner'], 'acme');
      expect(ref.metadata['repo'], 'repo');
      expect(ref.metadata['repo_ref'], 'acme/repo');
    });

    test('parseUrl supports ssh enterprise URLs', () {
      final GitHubAdapter adapter = GitHubAdapter();

      final ProviderRef ref = adapter.parseUrl('git@github.enterprise.local:team/service.git');

      expect(ref.baseUrl, 'https://github.enterprise.local');
      expect(ref.host, 'github.enterprise.local');
      expect(ref.resource, 'team/service');
      expect(ref.metadata['repo_ref'], 'github.enterprise.local/team/service');
    });

    test('parseUrl rejects empty values', () {
      final GitHubAdapter adapter = GitHubAdapter();

      expect(() => adapter.parseUrl('   '), throwsArgumentError);
    });

    test('buildTagUrl points to release tag page', () {
      final GitHubAdapter adapter = GitHubAdapter();
      final ProviderRef ref = adapter.parseUrl('https://github.com/acme/repo');

      final String url = adapter.buildTagUrl(ref, 'v1.2.3');

      expect(url, 'https://github.com/acme/repo/releases/tag/v1.2.3');
    });

    test('toCanonicalRelease maps assets and source archives', () {
      final GitHubAdapter adapter = GitHubAdapter();

      final Map<String, dynamic> payload = <String, dynamic>{
        'tag_name': 'v1.2.3',
        'name': '',
        'body': 'release notes',
        'target_commitish': 'abc123',
        'zipball_url': 'https://api.github.com/zipball/v1.2.3',
        'tarball_url': 'https://api.github.com/tarball/v1.2.3',
        'assets': <Map<String, dynamic>>[
          <String, dynamic>{
            'name': 'app.zip',
            'browser_download_url': 'https://github.com/acme/repo/releases/download/v1.2.3/app.zip',
          },
        ],
      };

      final dynamic canonical = adapter.toCanonicalRelease(payload);

      expect(canonical.tagName, 'v1.2.3');
      expect(canonical.name, 'v1.2.3');
      expect(canonical.descriptionMarkdown, 'release notes');
      expect(canonical.commitSha, 'abc123');
      expect(canonical.assets.links, hasLength(1));
      expect(canonical.assets.links.first.name, 'app.zip');
      expect(canonical.assets.sources, hasLength(2));
      expect(canonical.assets.sources.first.name, 'v1.2.3-source.zip');
      expect(canonical.assets.sources.last.name, 'v1.2.3-source.tar.gz');
    });
  });
}
