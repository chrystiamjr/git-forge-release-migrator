import '../core/http.dart';
import 'fixture_run_result.dart';
import 'repo_coordinates.dart';

export 'fixture_run_result.dart';
export 'repo_coordinates.dart';

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
