/// Repository coordinates parsed from a forge URL.
///
/// The triple `(host, workspace, repo)` is all a fixture trigger needs to
/// build REST paths for the supported forges. GitLab nested groups are stored
/// in `workspace` as a slash-delimited namespace.
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
