import 'repo_coordinates.dart';

/// Parses a forge URL into `RepoCoordinates`.
///
/// Accepted shapes:
///   `https://github.com/<owner>/<repo>`
///   `https://gitlab.com/<group>/<project>`
///   `https://gitlab.com/<group>/<subgroup>/<project>`
///   `https://bitbucket.org/<workspace>/<repo>`
///
/// Trailing `.git`, trailing slashes, and query strings are stripped.
/// Throws `FormatException` when the URL is not a valid forge URL.
RepoCoordinates parseRepoUrl(String url) {
  final String trimmed = url.trim();
  if (trimmed.isEmpty) {
    throw const FormatException('Empty forge URL');
  }

  Uri uri;
  try {
    uri = Uri.parse(trimmed);
  } catch (_) {
    throw FormatException('Invalid forge URL: $trimmed');
  }

  if (uri.host.isEmpty) {
    throw FormatException('Forge URL must include a host: $trimmed');
  }

  final List<String> segments = uri.pathSegments.where((String s) => s.isNotEmpty).toList();
  if (segments.length < 2) {
    throw FormatException('Forge URL must include <namespace>/<repo>: $trimmed');
  }

  final String workspace = segments.sublist(0, segments.length - 1).join('/');
  String repo = segments.last;
  if (repo.endsWith('.git')) {
    repo = repo.substring(0, repo.length - 4);
  }

  return RepoCoordinates(host: uri.host, workspace: workspace, repo: repo);
}
