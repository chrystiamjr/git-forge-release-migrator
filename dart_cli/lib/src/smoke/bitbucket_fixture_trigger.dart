import '../core/exceptions/http_request_error.dart';
import 'fixture_trigger.dart';
import 'smoke_delay.dart';

/// Bitbucket Cloud Pipelines trigger for smoke fixtures.
///
/// Triggers the `create_fake_releases` or `cleanup_tags_and_releases`
/// custom pipeline defined in the target repository's
/// `bitbucket-pipelines.yml`, then polls the resulting pipeline to
/// completion.
///
/// REST reference:
/// https://developer.atlassian.com/cloud/bitbucket/rest/api-group-pipelines/
final class BitbucketFixtureTrigger extends FixtureTrigger {
  BitbucketFixtureTrigger({
    required super.http,
    required super.coords,
    required super.token,
    required super.pollInterval,
    required super.pollTimeout,
    SmokeDelay? delay,
  }) : _delay = delay ?? defaultSmokeDelay;

  static const String _createPipelineName = 'create_fake_releases';
  static const String _cleanupPipelineName = 'cleanup_tags_and_releases';

  final SmokeDelay _delay;

  @override
  String get provider => 'bitbucket';

  Map<String, String> get _headers => <String, String>{
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      };

  String get _apiBase => 'https://api.${coords.host}/2.0/repositories/${coords.workspace}/${coords.repo}';

  @override
  Future<FixtureRunResult> createFakeReleases() {
    return _runCustomPipeline(_createPipelineName);
  }

  @override
  Future<FixtureRunResult> cleanupTagsAndReleases() {
    return _runCustomPipeline(_cleanupPipelineName);
  }

  Future<FixtureRunResult> _runCustomPipeline(String name) async {
    final String pipelineUuid = await _triggerPipeline(name);
    return _pollPipeline(pipelineUuid);
  }

  Future<String> _triggerPipeline(String name) async {
    final String url = '$_apiBase/pipelines/';
    final String defaultBranch = await _defaultBranch();
    final Map<String, dynamic> body = <String, dynamic>{
      'target': <String, dynamic>{
        'ref_type': 'branch',
        'type': 'pipeline_ref_target',
        'ref_name': defaultBranch,
        'selector': <String, String>{
          'type': 'custom',
          'pattern': name,
        },
      },
    };

    final dynamic response = await http.requestJson(
      url,
      method: 'POST',
      jsonData: body,
      headers: _headers,
    );
    final Map<String, dynamic> data = (response is Map<String, dynamic>) ? response : <String, dynamic>{};
    final dynamic uuid = data['uuid'];
    if (uuid == null) {
      throw HttpRequestError('Bitbucket pipeline trigger did not return uuid: $data');
    }
    return uuid.toString();
  }

  Future<String> _defaultBranch() async {
    final dynamic response = await http.requestJson(_apiBase, headers: _headers);
    final Map<String, dynamic> data = response is Map<String, dynamic> ? response : <String, dynamic>{};
    final Map<String, dynamic> mainBranch = (data['mainbranch'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final String branch = (mainBranch['name'] ?? '').toString().trim();
    if (branch.isEmpty) {
      throw HttpRequestError('Bitbucket repository metadata did not include mainbranch.name');
    }
    return branch;
  }

  Future<FixtureRunResult> _pollPipeline(String pipelineUuid) async {
    final String url = '$_apiBase/pipelines/$pipelineUuid';
    final DateTime deadline = DateTime.now().add(pollTimeout);

    while (DateTime.now().isBefore(deadline)) {
      final dynamic response = await http.requestJson(url, headers: _headers);
      final Map<String, dynamic> data = (response is Map<String, dynamic>) ? response : <String, dynamic>{};
      final Map<String, dynamic> state = (data['state'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      final String name = (state['name'] ?? '').toString();
      final Map<String, dynamic> result = (state['result'] as Map<String, dynamic>?) ?? <String, dynamic>{};
      final String resultName = (result['name'] ?? '').toString();

      if (name == 'COMPLETED') {
        if (resultName == 'SUCCESSFUL') {
          return FixtureRunResult(status: 'success', reference: pipelineUuid);
        }
        return FixtureRunResult(
          status: 'failed',
          reference: pipelineUuid,
          detail: 'result=$resultName',
        );
      }

      await _delay(pollInterval);
    }

    return FixtureRunResult(
      status: 'failed',
      reference: pipelineUuid,
      detail: 'timeout after ${pollTimeout.inSeconds}s',
    );
  }
}
