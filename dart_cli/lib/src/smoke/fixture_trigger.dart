import '../core/http.dart';

/// Repository coordinates parsed from a forge URL.
///
/// The triple `(host, workspace, repo)` is all a `FixtureTrigger`
/// implementation needs to build REST paths for the three supported forges.
/// For GitHub and GitLab, `workspace` is the user/org namespace. For
/// Bitbucket, `workspace` is the workspace slug and `repo` is the repo slug.
final class RepoCoordinates {
  const RepoCoordinates({
    required this.host,
    required this.workspace,
    required this.repo,
  });

  final String host;
  final String workspace;
  final String repo;

  @override
  String toString() => '$host/$workspace/$repo';
}

/// Outcome of a fixture operation — create or cleanup.
final class FixtureRunResult {
  const FixtureRunResult({
    required this.status,
    required this.reference,
    this.detail = '',
  });

  /// Human-readable status: `success` or `failed`.
  final String status;

  /// Forge-specific identifier that can be used to look up the run later
  /// (workflow run id on GitHub, pipeline id on GitLab, pipeline uuid on
  /// Bitbucket).
  final String reference;

  /// Additional diagnostic context, empty on success.
  final String detail;

  bool get isSuccess => status == 'success';
}

/// Abstract fixture orchestrator for a single forge.
///
/// Every concrete implementation is responsible for:
///   - triggering the `create-fake-releases` equivalent
///   - polling until the CI workflow/pipeline finishes
///   - triggering the `cleanup-tags-and-releases` equivalent
///   - polling until cleanup finishes
///
/// Implementations use `HttpClientHelper` so retries, backoff, and 403 /
/// 429 handling are consistent with the rest of the migrator.
abstract class FixtureTrigger {
  FixtureTrigger({
    required this.http,
    required this.coords,
    required this.token,
    required this.pollInterval,
    required this.pollTimeout,
  });

  final HttpClientHelper http;
  final RepoCoordinates coords;
  final String token;
  final Duration pollInterval;
  final Duration pollTimeout;

  /// Forge identifier (github, gitlab, bitbucket).
  String get provider;

  /// Trigger the fixture-create workflow/pipeline. Returns when CI finishes.
  Future<FixtureRunResult> createFakeReleases();

  /// Trigger the cleanup workflow/pipeline. Returns when CI finishes.
  Future<FixtureRunResult> cleanupTagsAndReleases();
}
