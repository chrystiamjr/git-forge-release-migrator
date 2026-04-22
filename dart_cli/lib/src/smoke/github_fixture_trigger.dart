import '../core/exceptions/http_request_error.dart';
import '../core/time.dart';
import 'fixture_trigger.dart';

typedef SmokeDelay = Future<void> Function(Duration duration);

Future<void> _defaultDelay(Duration duration) {
  return Future<void>.delayed(duration);
}

/// GitHub Actions `workflow_dispatch` trigger for smoke fixtures.
///
/// The target repo must contain the example workflow files from
/// `docs/smoke-tests/workflows/github/` installed under `.github/workflows/`
/// with the filenames `create-fake-releases.yml` and
/// `cleanup-tags-and-releases.yml`.
final class GitHubFixtureTrigger extends FixtureTrigger {
  GitHubFixtureTrigger({
    required super.http,
    required super.coords,
    required super.token,
    required super.pollInterval,
    required super.pollTimeout,
    SmokeDelay? delay,
  }) : _delay = delay ?? _defaultDelay;

  static const String _createWorkflowFile = 'create-fake-releases.yml';
  static const String _cleanupWorkflowFile = 'cleanup-tags-and-releases.yml';

  final SmokeDelay _delay;

  @override
  String get provider => 'github';

  Map<String, String> get _headers => <String, String>{
        'Authorization': 'token $token',
        'Accept': 'application/vnd.github+json',
      };

  String get _apiBase => 'https://api.${coords.host}';

  @override
  Future<FixtureRunResult> createFakeReleases() {
    return _dispatchAndWait(_createWorkflowFile);
  }

  @override
  Future<FixtureRunResult> cleanupTagsAndReleases() {
    return _dispatchAndWait(_cleanupWorkflowFile);
  }

  Future<FixtureRunResult> _dispatchAndWait(String workflowFile) async {
    final String before = TimeUtils.utcTimestamp();
    await _dispatch(workflowFile);
    final String runId = await _waitForRunId(workflowFile, before);
    return _pollRun(runId);
  }

  Future<void> _dispatch(String workflowFile) async {
    final String url = '$_apiBase/repos/${coords.workspace}/${coords.repo}/actions/workflows/$workflowFile/dispatches';
    final Map<String, String> body = <String, String>{'ref': await _defaultBranch()};
    await http.requestJson(
      url,
      method: 'POST',
      jsonData: body,
      headers: _headers,
    );
  }

  Future<String> _defaultBranch() async {
    final String url = '$_apiBase/repos/${coords.workspace}/${coords.repo}';
    final dynamic response = await http.requestJson(url, headers: _headers);
    final Map<String, dynamic> data = response is Map<String, dynamic> ? response : <String, dynamic>{};
    final String branch = (data['default_branch'] ?? '').toString().trim();
    if (branch.isEmpty) {
      throw HttpRequestError('GitHub repository metadata did not include default_branch');
    }
    return branch;
  }

  Future<String> _waitForRunId(String workflowFile, String beforeIso) async {
    final String filter = 'created=${Uri.encodeQueryComponent(">=$beforeIso")}';
    final String url =
        '$_apiBase/repos/${coords.workspace}/${coords.repo}/actions/workflows/$workflowFile/runs?per_page=1&$filter';

    final DateTime deadline = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(deadline)) {
      final dynamic response = await http.requestJson(url, headers: _headers);
      final List<dynamic> runs = (response is Map<String, dynamic>)
          ? (response['workflow_runs'] as List<dynamic>? ?? <dynamic>[])
          : <dynamic>[];
      if (runs.isNotEmpty) {
        final Map<String, dynamic> first = runs.first as Map<String, dynamic>;
        final dynamic id = first['id'];
        if (id != null) {
          return id.toString();
        }
      }
      await _delay(const Duration(seconds: 3));
    }

    throw HttpRequestError(
      'GitHub workflow dispatch ($workflowFile) did not register a run within 60s',
    );
  }

  Future<FixtureRunResult> _pollRun(String runId) async {
    final String url = '$_apiBase/repos/${coords.workspace}/${coords.repo}/actions/runs/$runId';
    final DateTime deadline = DateTime.now().add(pollTimeout);

    while (DateTime.now().isBefore(deadline)) {
      final dynamic response = await http.requestJson(url, headers: _headers);
      final Map<String, dynamic> data = (response is Map<String, dynamic>) ? response : <String, dynamic>{};
      final String status = (data['status'] ?? '').toString();
      final String conclusion = (data['conclusion'] ?? '').toString();

      if (status == 'completed') {
        if (conclusion == 'success') {
          return FixtureRunResult(status: 'success', reference: runId);
        }
        return FixtureRunResult(
          status: 'failed',
          reference: runId,
          detail: 'conclusion=$conclusion',
        );
      }

      await _delay(pollInterval);
    }

    return FixtureRunResult(
      status: 'failed',
      reference: runId,
      detail: 'timeout after ${pollTimeout.inSeconds}s',
    );
  }
}
