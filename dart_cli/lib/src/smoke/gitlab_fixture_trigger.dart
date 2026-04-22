import '../core/exceptions/http_request_error.dart';
import 'fixture_trigger.dart';
import 'github_fixture_trigger.dart' show SmokeDelay;

Future<void> _defaultDelay(Duration duration) {
  return Future<void>.delayed(duration);
}

/// GitLab CI trigger for smoke fixtures.
///
/// Creates a pipeline on the project's default branch, locates the
/// `create_fake_releases` or `cleanup_tags_and_releases` manual job,
/// plays it, and polls until the job finishes.
final class GitLabFixtureTrigger extends FixtureTrigger {
  GitLabFixtureTrigger({
    required super.http,
    required super.coords,
    required super.token,
    required super.pollInterval,
    required super.pollTimeout,
    SmokeDelay? delay,
  }) : _delay = delay ?? _defaultDelay;

  static const String _createJobName = 'create_fake_releases';
  static const String _cleanupJobName = 'cleanup_tags_and_releases';

  final SmokeDelay _delay;

  @override
  String get provider => 'gitlab';

  Map<String, String> get _headers => <String, String>{
        'PRIVATE-TOKEN': token,
        'Accept': 'application/json',
      };

  String get _projectPath =>
      Uri.encodeComponent('${coords.workspace}/${coords.repo}');

  String get _apiBase => 'https://${coords.host}/api/v4';

  @override
  Future<FixtureRunResult> createFakeReleases() {
    return _runManualJob(_createJobName);
  }

  @override
  Future<FixtureRunResult> cleanupTagsAndReleases() {
    return _runManualJob(_cleanupJobName);
  }

  Future<FixtureRunResult> _runManualJob(String jobName) async {
    final String pipelineId = await _createPipeline();
    await _delay(const Duration(seconds: 3));
    final String jobId = await _findJob(pipelineId, jobName);
    await _playJob(jobId);
    return _pollJob(jobId);
  }

  Future<String> _createPipeline() async {
    final String url = '$_apiBase/projects/$_projectPath/pipeline?ref=main';
    final dynamic response = await http.requestJson(
      url,
      method: 'POST',
      headers: _headers,
    );
    final Map<String, dynamic> data =
        (response is Map<String, dynamic>) ? response : <String, dynamic>{};
    final dynamic id = data['id'];
    if (id == null) {
      throw HttpRequestError(
          'GitLab pipeline creation did not return an id: $data');
    }
    return id.toString();
  }

  Future<String> _findJob(String pipelineId, String jobName) async {
    final String url =
        '$_apiBase/projects/$_projectPath/pipelines/$pipelineId/jobs';
    final dynamic response = await http.requestJson(url, headers: _headers);
    if (response is! List<dynamic>) {
      throw HttpRequestError(
          'GitLab jobs listing returned non-list for pipeline $pipelineId');
    }

    for (final dynamic entry in response) {
      if (entry is Map<String, dynamic> && entry['name'] == jobName) {
        final dynamic id = entry['id'];
        if (id != null) {
          return id.toString();
        }
      }
    }

    throw HttpRequestError('Job "$jobName" not found in pipeline $pipelineId');
  }

  Future<void> _playJob(String jobId) async {
    final String url = '$_apiBase/projects/$_projectPath/jobs/$jobId/play';
    await http.requestJson(url, method: 'POST', headers: _headers);
  }

  Future<FixtureRunResult> _pollJob(String jobId) async {
    final String url = '$_apiBase/projects/$_projectPath/jobs/$jobId';
    final DateTime deadline = DateTime.now().add(pollTimeout);

    while (DateTime.now().isBefore(deadline)) {
      final dynamic response = await http.requestJson(url, headers: _headers);
      final Map<String, dynamic> data =
          (response is Map<String, dynamic>) ? response : <String, dynamic>{};
      final String status = (data['status'] ?? '').toString();

      if (status == 'success') {
        return FixtureRunResult(status: 'success', reference: jobId);
      }
      if (status == 'failed' || status == 'canceled') {
        return FixtureRunResult(
          status: 'failed',
          reference: jobId,
          detail: 'status=$status',
        );
      }

      await _delay(pollInterval);
    }

    return FixtureRunResult(
      status: 'failed',
      reference: jobId,
      detail: 'timeout after ${pollTimeout.inSeconds}s',
    );
  }
}
