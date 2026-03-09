import 'package:gfrm_dart/src/core/adapters/provider_adapter.dart';
import 'package:gfrm_dart/src/providers/gitlab.dart';
import 'package:test/test.dart';

void main() {
  group('GitLabAdapter', () {
    test('parseUrl supports https project with subgroup', () {
      final GitLabAdapter adapter = GitLabAdapter();

      final ProviderRef ref = adapter.parseUrl('https://gitlab.com/group/subgroup/project.git');

      expect(ref.provider, 'gitlab');
      expect(ref.baseUrl, 'https://gitlab.com');
      expect(ref.host, 'gitlab.com');
      expect(ref.resource, 'group/subgroup/project');
      expect(ref.metadata['project_path'], 'group/subgroup/project');
      expect(ref.metadata['project_encoded'], 'group%2Fsubgroup%2Fproject');
    });

    test('parseUrl supports ssh project URL', () {
      final GitLabAdapter adapter = GitLabAdapter();

      final ProviderRef ref = adapter.parseUrl('git@gitlab.example.com:team/api.git');

      expect(ref.baseUrl, 'https://gitlab.example.com');
      expect(ref.host, 'gitlab.example.com');
      expect(ref.resource, 'team/api');
      expect(ref.metadata['project_encoded'], 'team%2Fapi');
    });

    test('normalizeUrl keeps absolute and resolves relative URLs', () {
      final GitLabAdapter adapter = GitLabAdapter();
      final ProviderRef ref = adapter.parseUrl('https://gitlab.com/team/app');

      expect(
        adapter.normalizeUrl(ref, 'https://cdn.gitlab.com/file.zip'),
        'https://cdn.gitlab.com/file.zip',
      );
      expect(adapter.normalizeUrl(ref, '/team/app/uploads/abc/file.zip'),
          'https://gitlab.com/team/app/uploads/abc/file.zip');
      expect(adapter.normalizeUrl(ref, 'team/app/uploads/abc/file.zip'),
          'https://gitlab.com/team/app/uploads/abc/file.zip');
    });

    test('buildReleaseDownloadApiUrl maps release download links to API endpoint', () {
      final GitLabAdapter adapter = GitLabAdapter();
      final ProviderRef ref = adapter.parseUrl('https://gitlab.com/acme/project');

      final String url = adapter.buildReleaseDownloadApiUrl(
        ref,
        'v1.2.3',
        'https://gitlab.com/acme/project/-/releases/v1.2.3/downloads/bin/app.zip?download=1',
      );

      expect(
        url,
        'https://gitlab.com/api/v4/projects/acme%2Fproject/releases/v1.2.3/downloads/bin/app.zip',
      );
    });

    test('buildProjectUploadApiUrl maps upload links to API endpoint', () {
      final GitLabAdapter adapter = GitLabAdapter();
      final ProviderRef ref = adapter.parseUrl('https://gitlab.com/acme/project');

      final String url = adapter.buildProjectUploadApiUrl(
        ref,
        'https://gitlab.com/acme/project/uploads/secret/path/to/file.tar.gz?download=1',
      );

      expect(
        url,
        'https://gitlab.com/api/v4/projects/acme%2Fproject/uploads/secret/path%2Fto%2Ffile.tar.gz',
      );
    });

    test('addPrivateTokenQuery appends token without dropping existing params', () {
      final GitLabAdapter adapter = GitLabAdapter();

      final Uri uri = Uri.parse(adapter.addPrivateTokenQuery('https://gitlab.com/path?a=1', 'token-123'));

      expect(uri.queryParameters['a'], '1');
      expect(uri.queryParameters['private_token'], 'token-123');
    });

    test('toCanonicalRelease normalizes assets links and sources', () {
      final GitLabAdapter adapter = GitLabAdapter();

      final dynamic canonical = adapter.toCanonicalRelease(<String, dynamic>{
        'tag_name': 'v1.0.0',
        'name': 'Release v1.0.0',
        'description': 'notes',
        'commit': <String, dynamic>{'id': 'sha123'},
        'assets': <String, dynamic>{
          'links': <Map<String, dynamic>>[
            <String, dynamic>{
              'name': 'binary',
              'url': '/acme/project/-/releases/v1.0.0/downloads/bin',
              'direct_asset_url': '/acme/project/uploads/abc/bin',
              'link_type': 'other',
            },
          ],
          'sources': <Map<String, dynamic>>[
            <String, dynamic>{
              'format': 'zip',
              'url': 'https://gitlab.com/acme/project/-/archive/v1.0.0/project-v1.0.0.zip',
            },
          ],
        },
      });

      expect(canonical.tagName, 'v1.0.0');
      expect(canonical.name, 'Release v1.0.0');
      expect(canonical.descriptionMarkdown, 'notes');
      expect(canonical.commitSha, 'sha123');
      expect(canonical.assets.links, hasLength(1));
      expect(canonical.assets.links.first.directUrl, '/acme/project/uploads/abc/bin');
      expect(canonical.assets.sources, hasLength(1));
      expect(canonical.assets.sources.first.name, 'project-v1.0.0.zip');
    });

    test('supports source fallback tag notes', () {
      final GitLabAdapter adapter = GitLabAdapter();

      expect(adapter.supportsSourceFallbackTagNotes(), isTrue);
    });
  });
}
