final class MissingTargetCommit {
  const MissingTargetCommit({
    required this.tag,
    required this.commitSha,
  });

  final String tag;
  final String commitSha;
}
