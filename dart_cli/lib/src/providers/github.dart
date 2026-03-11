import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../core/adapters/dio_adapter.dart';
import '../core/adapters/provider_adapter.dart';
import '../core/checkpoint.dart';
import '../core/concurrency.dart';
import '../core/exceptions/authentication_error.dart';
import '../core/exceptions/http_request_error.dart';
import '../core/http.dart';
import '../core/types/canonical_release.dart';
import '../core/types/http_config.dart';
import '../core/types/phase.dart';
import 'provider_common.dart';

class GitHubAdapter extends ProviderAdapter {
  GitHubAdapter({HttpClientHelper? http, Dio? dio, HttpConfig? config})
      : _config = config ?? const HttpConfig(),
        _http = http ?? HttpClientHelper(config: config),
        _dio = dio ?? DioAdapter(config: config).instance;

  final HttpClientHelper _http;
  final Dio _dio;
  final HttpConfig _config;

  @override
  String get name => 'github';

  static const String _apiBase = 'https://api.github.com';
  static const int _assetUploadWorkers = 4;

  Map<String, String> _headers(String token) => <String, String>{
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      };

  String _apiPath(String path) => '$_apiBase/${path.replaceFirst(RegExp(r'^/+'), '')}';

  Future<dynamic> _apiJson(String token, String path, {String method = 'GET', dynamic body}) {
    return _http.requestJson(
      _apiPath(path),
      method: method,
      headers: _headers(token),
      jsonData: body,
      retries: _config.maxRetries,
      retryDelay: _config.retryDelay,
    );
  }

  ({String host, String path, String baseUrl}) _extractHostPath(String normalizedUrl, String originalUrl) {
    final RegExpMatch? ssh = RegExp(r'^git@([^:]+):(.+)$').firstMatch(normalizedUrl);
    if (ssh != null) {
      final String host = ssh.group(1) ?? '';
      final String path = ssh.group(2) ?? '';
      return (host: host, path: path, baseUrl: 'https://$host');
    }

    final RegExpMatch? https = RegExp(r'^https?://([^/]+)/(.+)$').firstMatch(normalizedUrl);
    if (https == null) {
      throw ArgumentError('Invalid GitHub URL: $originalUrl');
    }

    final String host = https.group(1) ?? '';
    final String path = https.group(2) ?? '';
    return (host: host, path: path, baseUrl: 'https://$host');
  }

  ({String owner, String repo, String resource, String repoRef}) _extractRepositoryParts(
    String path,
    String host,
    String originalUrl,
  ) {
    final String normalizedPath = path.replaceFirst(RegExp(r'^/+'), '').split('/-/').first;
    final List<String> parts = normalizedPath.split('/');
    if (parts.length < 2) {
      throw ArgumentError('Invalid GitHub repository path: $originalUrl');
    }

    final String owner = parts[0];
    final String repo = parts[1];
    final String resource = '$owner/$repo';
    final String repoRef = host == 'github.com' ? resource : '$host/$resource';
    return (owner: owner, repo: repo, resource: resource, repoRef: repoRef);
  }

  @override
  ProviderRef parseUrl(String url) {
    if (url.trim().isEmpty) {
      throw ArgumentError('Invalid GitHub URL: empty value');
    }

    final String normalizedUrl = ProviderCommon.normalizeRepositoryUrl(url);
    final ({String host, String path, String baseUrl}) hostPath = _extractHostPath(normalizedUrl, url);
    final ({String owner, String repo, String resource, String repoRef}) repository =
        _extractRepositoryParts(hostPath.path, hostPath.host, url);

    return ProviderRef(
      provider: name,
      rawUrl: url,
      baseUrl: hostPath.baseUrl,
      host: hostPath.host,
      resource: repository.resource,
      metadata: <String, String>{
        'owner': repository.owner,
        'repo': repository.repo,
        'repo_ref': repository.repoRef,
      },
    );
  }

  @override
  Future<List<Map<String, dynamic>>> listReleases(ProviderRef ref, String token) async {
    final List<Map<String, dynamic>> releases = <Map<String, dynamic>>[];
    int page = 1;

    while (true) {
      final dynamic payload = await _apiJson(
        token,
        'repos/${ref.resource}/releases?per_page=100&page=$page',
      );

      if (payload is! List || payload.isEmpty) {
        break;
      }

      for (final dynamic item in payload) {
        if (item is Map) {
          releases.add(Map<String, dynamic>.from(item));
        }
      }

      if (payload.length < 100) {
        break;
      }

      page += 1;
    }

    return releases;
  }

  Future<List<String>> listReleaseTags(ProviderRef ref, String token) async {
    final List<Map<String, dynamic>> releases = await listReleases(ref, token);
    return releases
        .map((Map<String, dynamic> item) => (item['tag_name'] ?? '').toString())
        .where((String tag) => tag.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<List<String>> listTags(ProviderRef ref, String token) async {
    final dynamic payload = await _apiJson(token, 'repos/${ref.resource}/git/matching-refs/tags/');
    if (payload is! List) {
      return <String>[];
    }

    final List<String> tags = <String>[];
    for (final dynamic item in payload) {
      if (item is! Map) {
        continue;
      }

      final String raw = (item['ref'] ?? '').toString();
      if (raw.startsWith('refs/tags/')) {
        tags.add(raw.replaceFirst('refs/tags/', ''));
      }
    }

    return tags;
  }

  @override
  Future<Map<String, dynamic>?> releaseByTag(ProviderRef ref, String token, String tag) async {
    try {
      final dynamic payload = await _apiJson(token, 'repos/${ref.resource}/releases/tags/$tag');
      if (payload is Map) {
        return Map<String, dynamic>.from(payload);
      }

      return null;
    } on AuthenticationError {
      rethrow;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> tagExists(ProviderRef ref, String token, String tag) async {
    try {
      await _apiJson(token, 'repos/${ref.resource}/git/ref/tags/$tag');
      return true;
    } on AuthenticationError {
      rethrow;
    } catch (_) {
      return false;
    }
  }

  Future<void> createTagRef(ProviderRef ref, String token, String tag, String sha) async {
    await _apiJson(
      token,
      'repos/${ref.resource}/git/refs',
      method: 'POST',
      body: <String, String>{
        'ref': 'refs/tags/$tag',
        'sha': sha,
      },
    );
  }

  @override
  Future<void> createTag(ProviderRef ref, String token, String tag, String sha, {String message = ''}) {
    return createTagRef(ref, token, tag, sha);
  }

  @override
  Future<String> tagCommitSha(ProviderRef ref, String token, String tag) => commitShaForRef(ref, token, tag);

  Future<String> commitShaForRef(ProviderRef ref, String token, String refName) async {
    final dynamic payload = await _apiJson(token, 'repos/${ref.resource}/commits/$refName');
    if (payload is! Map || payload['sha'] == null) {
      throw HttpRequestError('Commit SHA not found for ref $refName in GitHub');
    }

    return payload['sha'].toString();
  }

  @override
  Future<bool> releaseExists(ProviderRef ref, String token, String tag) async {
    return (await releaseByTag(ref, token, tag)) != null;
  }

  Future<void> releaseCreate(
    ProviderRef ref,
    String token,
    String tag,
    String title,
    String notesFile,
  ) async {
    final String body = await _readNotesFile(notesFile);
    await _apiJson(
      token,
      'repos/${ref.resource}/releases',
      method: 'POST',
      body: <String, Object>{
        'tag_name': tag,
        'name': title,
        'body': body,
        'draft': false,
        'prerelease': false,
      },
    );
  }

  Future<void> releaseEdit(
    ProviderRef ref,
    String token,
    String tag,
    String title,
    String notesFile,
  ) async {
    final Map<String, dynamic>? current = await releaseByTag(ref, token, tag);
    if (current == null) {
      throw HttpRequestError('GitHub release not found for tag $tag');
    }

    final String releaseId = (current['id'] ?? '').toString();
    if (releaseId.isEmpty) {
      throw HttpRequestError('GitHub release id missing for tag $tag');
    }

    final String body = await _readNotesFile(notesFile);
    await _apiJson(
      token,
      'repos/${ref.resource}/releases/$releaseId',
      method: 'PATCH',
      body: <String, String>{
        'name': title,
        'body': body,
      },
    );
  }

  Future<void> releaseUpload(ProviderRef ref, String token, String tag, List<String> assets) async {
    if (assets.isEmpty) {
      return;
    }

    final Map<String, dynamic>? release = await releaseByTag(ref, token, tag);
    if (release == null) {
      throw HttpRequestError('GitHub release not found for upload tag $tag');
    }

    final String uploadTemplate = (release['upload_url'] ?? '').toString();
    if (uploadTemplate.isEmpty) {
      throw HttpRequestError('GitHub upload_url missing for tag $tag');
    }

    final String uploadBase = uploadTemplate.split('{').first;

    await Concurrency.mapWithLimit<String, void>(
      items: assets,
      limit: _assetUploadWorkers,
      task: (String assetPath, int _) async {
        final File file = File(assetPath);
        if (!file.existsSync()) {
          return;
        }

        final String name = ProviderCommon.basename(assetPath).isEmpty ? 'asset' : ProviderCommon.basename(assetPath);
        final Uri uri = Uri.parse(uploadBase).replace(queryParameters: <String, dynamic>{'name': name});
        final Uint8List bytes = await file.readAsBytes();

        final Response<dynamic> response = await _dio.post<dynamic>(
          uri.toString(),
          data: bytes,
          options: Options(
            headers: <String, dynamic>{
              'Authorization': 'Bearer $token',
              'Accept': 'application/vnd.github+json',
              'Content-Type': 'application/octet-stream',
            },
            validateStatus: (_) => true,
            sendTimeout: const Duration(seconds: 120),
            receiveTimeout: const Duration(seconds: 120),
          ),
        );

        final int status = response.statusCode ?? 0;
        if (status < HttpStatus.ok || status >= HttpStatus.multipleChoices) {
          throw HttpRequestError('GitHub upload failed for $name (HTTP $status)');
        }
      },
    );
  }

  Future<bool> downloadWithToken(String token, String url, String destination) {
    return _http.downloadFile(
      url,
      destination,
      retries: _config.maxRetries,
      backoff: _config.retryDelay,
      headers: <String, String>{
        'Authorization': 'Bearer $token',
        'Accept': 'application/octet-stream',
      },
    );
  }

  @override
  Future<bool> downloadWithAuth(String token, String url, String destination) {
    return downloadWithToken(token, url, destination);
  }

  @override
  String buildTagUrl(ProviderRef ref, String tag) {
    return '${ref.baseUrl.replaceAll(RegExp(r'/+$'), '')}/${ref.resource}/releases/tag/$tag';
  }

  List<Map<String, dynamic>> _extractRawAssetMaps(Map<String, dynamic> payload) {
    return ProviderCommon.mapListFrom(payload['assets']);
  }

  List<Map<String, dynamic>> _canonicalLinksFromPayload(Map<String, dynamic> payload) {
    final List<Map<String, dynamic>> rawAssets = _extractRawAssetMaps(payload);
    final List<Map<String, dynamic>> links = <Map<String, dynamic>>[];
    for (final Map<String, dynamic> asset in rawAssets) {
      final String browserUrl = (asset['browser_download_url'] ?? '').toString();
      links.add(<String, dynamic>{
        'name': (asset['name'] ?? '').toString(),
        'url': browserUrl,
        'direct_url': browserUrl,
        'type': 'package',
      });
    }

    return links;
  }

  List<Map<String, dynamic>> _canonicalSourcesFromPayload(Map<String, dynamic> payload, String tagName) {
    final List<Map<String, dynamic>> sources = <Map<String, dynamic>>[];
    final String zipUrl = (payload['zipball_url'] ?? '').toString();
    final String tarUrl = (payload['tarball_url'] ?? '').toString();
    final String baseName = tagName.isEmpty ? 'release' : tagName;
    if (zipUrl.isNotEmpty) {
      sources.add(<String, dynamic>{
        'format': 'zip',
        'url': zipUrl,
        'name': '$baseName-source.zip',
      });
    }

    if (tarUrl.isNotEmpty) {
      sources.add(<String, dynamic>{
        'format': 'tar.gz',
        'url': tarUrl,
        'name': '$baseName-source.tar.gz',
      });
    }

    return sources;
  }

  @override
  CanonicalRelease toCanonicalRelease(Map<String, dynamic> payload) {
    final String tagName = (payload['tag_name'] ?? '').toString();
    final List<Map<String, dynamic>> links = _canonicalLinksFromPayload(payload);
    final List<Map<String, dynamic>> sources = _canonicalSourcesFromPayload(payload, tagName);
    return CanonicalRelease.fromMap(<String, dynamic>{
      'tag_name': tagName,
      'name': (payload['name'] ?? tagName).toString(),
      'description_markdown': (payload['body'] ?? '').toString(),
      'commit_sha': (payload['target_commitish'] ?? '').toString(),
      'assets': <String, List<Map<String, dynamic>>>{
        'links': links,
        'sources': sources,
      },
    });
  }

  @override
  Future<Set<String>> listTargetReleaseTags(ProviderRef ref, String token, Set<String> fallbackTags) async {
    return (await listReleaseTags(ref, token)).toSet();
  }

  @override
  Future<void> createTagForMigration(
    ProviderRef ref,
    String token,
    String tag,
    String sha,
    CanonicalRelease canonical,
  ) {
    return createTagRef(ref, token, tag, sha);
  }

  @override
  Future<String> resolveCommitShaForMigration(
    ProviderRef ref,
    String token,
    String tag,
    CanonicalRelease canonical,
  ) async {
    if (canonical.commitSha.isNotEmpty) {
      return canonical.commitSha;
    }

    return commitShaForRef(ref, token, tag);
  }

  @override
  Future<bool> isReleaseAlreadyProcessed(
    ProviderRef ref,
    String token,
    String tag,
    String checkpointStatus,
    Set<String> targetReleaseTags,
  ) async {
    if (!CheckpointStore.isTerminalReleaseStatus(checkpointStatus)) {
      return false;
    }

    return targetReleaseTags.contains(tag);
  }

  @override
  Future<ExistingReleaseInfo> existingReleaseInfo(
    ProviderRef ref,
    String token,
    String tag,
    int expectedLinkAssets,
  ) async {
    final Map<String, dynamic>? release = await releaseByTag(ref, token, tag);
    if (release == null) {
      return const ExistingReleaseInfo(exists: false, shouldRetry: false, reason: '');
    }

    final bool draft = release['draft'] == true;
    final dynamic assetsRaw = release['assets'];
    final List<dynamic> assets = assetsRaw is List ? assetsRaw : <dynamic>[];
    final int assetsCount = assets.length;

    if (draft) {
      return const ExistingReleaseInfo(exists: true, shouldRetry: true, reason: 'existing draft release');
    }

    if (assetsCount < expectedLinkAssets) {
      return ExistingReleaseInfo(
        exists: true,
        shouldRetry: true,
        reason: 'existing release with incomplete required assets ($assetsCount/$expectedLinkAssets)',
      );
    }

    return const ExistingReleaseInfo(exists: true, shouldRetry: false, reason: '');
  }

  @override
  Future<String> publishRelease(PublishReleaseInput input) async {
    if (!input.existingInfo.exists) {
      await releaseCreate(input.providerRef, input.token, input.tag, input.releaseName, input.notesFile.path);
    }

    await releaseUpload(input.providerRef, input.token, input.tag, input.downloadedFiles);
    await releaseEdit(input.providerRef, input.token, input.tag, input.releaseName, input.notesFile.path);
    return 'ok';
  }

  Future<String> _readNotesFile(String notesFile) async {
    final File file = File(notesFile);
    if (!file.existsSync()) {
      return '';
    }

    return file.readAsString();
  }

  @override
  Future<bool> downloadCanonicalLink(DownloadLinkInput input) async {
    final String resolved = input.link.directUrl.isNotEmpty ? input.link.directUrl : input.link.url;
    if (resolved.isEmpty) {
      return false;
    }

    return downloadWithToken(input.token, resolved, input.outputPath);
  }

  @override
  Future<bool> downloadCanonicalSource(DownloadSourceInput input) async {
    if (input.source.url.isEmpty) {
      return false;
    }

    return downloadWithToken(input.token, input.source.url, input.outputPath);
  }

  @override
  bool supportsSourceFallbackTagNotes() {
    return true;
  }
}
