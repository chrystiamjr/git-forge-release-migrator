import 'package:dio/dio.dart';
import 'package:gfrm_dart/src/core/http.dart';
import 'package:gfrm_dart/src/smoke/bitbucket_fixture_trigger.dart';
import 'package:gfrm_dart/src/smoke/fixture_trigger.dart';
import 'package:gfrm_dart/src/smoke/github_fixture_trigger.dart';
import 'package:gfrm_dart/src/smoke/gitlab_fixture_trigger.dart';
import 'package:test/test.dart';

void main() {
  group('fixture triggers', () {
    test('GitHub dispatches workflows on the repository default branch', () async {
      final _RecordingHttpClient http = _RecordingHttpClient(<dynamic>[
        <String, dynamic>{'default_branch': 'develop'},
        <String, dynamic>{},
        <String, dynamic>{
          'workflow_runs': <Map<String, dynamic>>[
            <String, dynamic>{'id': 42},
          ],
        },
        <String, dynamic>{'status': 'completed', 'conclusion': 'success'},
      ]);
      final GitHubFixtureTrigger trigger = GitHubFixtureTrigger(
        http: http,
        coords: const RepoCoordinates(host: 'github.com', workspace: 'owner', repo: 'repo'),
        token: 'token',
        pollInterval: const Duration(milliseconds: 1),
        pollTimeout: const Duration(seconds: 1),
        delay: (_) async {},
      );

      final FixtureRunResult result = await trigger.createFakeReleases();

      expect(result.isSuccess, isTrue);
      expect(http.jsonPayloads[1], <String, String>{'ref': 'develop'});
    });

    test('GitLab creates fixture pipelines on the project default branch', () async {
      final _RecordingHttpClient http = _RecordingHttpClient(<dynamic>[
        <String, dynamic>{'default_branch': 'trunk'},
        <String, dynamic>{'id': 7},
        <Map<String, dynamic>>[
          <String, dynamic>{'id': 9, 'name': 'create_fake_releases'},
        ],
        <String, dynamic>{},
        <String, dynamic>{'status': 'success'},
      ]);
      final GitLabFixtureTrigger trigger = GitLabFixtureTrigger(
        http: http,
        coords: const RepoCoordinates(host: 'gitlab.com', workspace: 'group/subgroup', repo: 'repo'),
        token: 'token',
        pollInterval: const Duration(milliseconds: 1),
        pollTimeout: const Duration(seconds: 1),
        delay: (_) async {},
      );

      final FixtureRunResult result = await trigger.createFakeReleases();

      expect(result.isSuccess, isTrue);
      expect(http.urls[1], contains('ref=trunk'));
      expect(http.urls[0], contains('group%2Fsubgroup%2Frepo'));
    });

    test('Bitbucket triggers custom pipelines on the repository main branch', () async {
      final _RecordingHttpClient http = _RecordingHttpClient(<dynamic>[
        <String, dynamic>{
          'mainbranch': <String, dynamic>{'name': 'master'}
        },
        <String, dynamic>{'uuid': 'pipeline-1'},
        <String, dynamic>{
          'state': <String, dynamic>{
            'name': 'COMPLETED',
            'result': <String, dynamic>{'name': 'SUCCESSFUL'},
          },
        },
      ]);
      final BitbucketFixtureTrigger trigger = BitbucketFixtureTrigger(
        http: http,
        coords: const RepoCoordinates(host: 'bitbucket.org', workspace: 'workspace', repo: 'repo'),
        token: 'token',
        pollInterval: const Duration(milliseconds: 1),
        pollTimeout: const Duration(seconds: 1),
        delay: (_) async {},
      );

      final FixtureRunResult result = await trigger.createFakeReleases();
      final Map<String, dynamic> payload = http.jsonPayloads[1] as Map<String, dynamic>;
      final Map<String, dynamic> target = payload['target'] as Map<String, dynamic>;

      expect(result.isSuccess, isTrue);
      expect(target['ref_name'], 'master');
    });
  });
}

final class _RecordingHttpClient extends HttpClientHelper {
  _RecordingHttpClient(this.responses) : super(dio: Dio());

  final List<dynamic> responses;
  final List<String> urls = <String>[];
  final List<dynamic> jsonPayloads = <dynamic>[];

  int _index = 0;

  @override
  Future<dynamic> requestJson(
    String url, {
    int retries = 3,
    dynamic jsonData,
    String method = 'GET',
    Map<String, String>? headers,
    Duration retryDelay = const Duration(seconds: 2),
  }) async {
    urls.add(url);
    jsonPayloads.add(jsonData);
    final dynamic response = responses[_index];
    _index += 1;
    return response;
  }
}
