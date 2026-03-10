import 'dart:io';

import 'package:dio/dio.dart';

import '../core/adapters/dio_adapter.dart';
import '../core/adapters/provider_adapter.dart';
import '../core/concurrency.dart';
import '../core/exceptions/http_request_error.dart';
import '../core/http.dart';
import '../core/types/canonical_release.dart';
import '../core/types/phase.dart';
import 'provider_common.dart';

class GitLabAdapter extends ProviderAdapter {
  GitLabAdapter({HttpClientHelper? http, Dio? dio})
      : _http = http ?? HttpClientHelper(),
        _dio = dio ?? DioAdapter().instance;

  final HttpClientHelper _http;
  final Dio _dio;
  static const int _assetUploadWorkers = 4;

  @override
  String get name => 'gitlab';

  Map<String, String> _headers(String token) => <String, String>{'PRIVATE-TOKEN': token};

  String _projectEncoded(ProviderRef ref) {
    final String? encoded = ref.metadata['project_encoded'];
    if (encoded != null && encoded.isNotEmpty) {
      return encoded;
    }
    return Uri.encodeComponent(ref.resource);
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
      throw ArgumentError('Invalid GitLab URL: $originalUrl');
    }

    final String host = https.group(1) ?? '';
    final String path = https.group(2) ?? '';
    return (host: host, path: path, baseUrl: 'https://$host');
  }

  @override
  ProviderRef parseUrl(String url) {
    if (url.trim().isEmpty) {
      throw ArgumentError('Invalid GitLab URL: empty value');
    }

    final String normalizedUrl = ProviderCommon.normalizeRepositoryUrl(url);
    final ({String host, String path, String baseUrl}) hostPath = _extractHostPath(normalizedUrl, url);
    final String projectPath = hostPath.path.replaceFirst(RegExp(r'^/+'), '').split('/-/').first;
    if (projectPath.isEmpty) {
      throw ArgumentError('Invalid GitLab project path: $url');
    }

    return ProviderRef(
      provider: name,
      rawUrl: url,
      baseUrl: hostPath.baseUrl,
      host: hostPath.host,
      resource: projectPath,
      metadata: <String, String>{
        'project_path': projectPath,
        'project_encoded': Uri.encodeComponent(projectPath),
      },
    );
  }

  String normalizeUrl(ProviderRef ref, String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }

    final String base = ref.baseUrl.replaceAll(RegExp(r'/+$'), '');
    if (url.startsWith('/')) {
      return '$base$url';
    }

    return '$base/$url';
  }

  @override
  Future<List<Map<String, dynamic>>> listReleases(ProviderRef ref, String token) async {
    final List<Map<String, dynamic>> releases = <Map<String, dynamic>>[];

    int page = 1;
    while (true) {
      final String url = '${_buildProjectUrl(ref, forApi: true)}/releases?per_page=100&page=$page';
      final dynamic payload = await _http.requestJson(
        url,
        headers: _headers(token),
        retries: 3,
        retryDelay: const Duration(seconds: 2),
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

  @override
  Future<List<String>> listTags(ProviderRef ref, String token) async {
    final List<String> tags = <String>[];

    int page = 1;
    while (true) {
      final String url = '${_buildProjectUrl(ref, forApi: true)}/repository/tags?per_page=100&page=$page';
      final dynamic payload = await _http.requestJson(
        url,
        headers: _headers(token),
        retries: 3,
        retryDelay: const Duration(seconds: 2),
      );

      if (payload is! List || payload.isEmpty) {
        break;
      }

      for (final dynamic item in payload) {
        if (item is Map && item['name'] != null) {
          tags.add(item['name'].toString());
        }
      }

      if (payload.length < 100) {
        break;
      }

      page += 1;
    }

    return tags;
  }

  @override
  Future<bool> tagExists(ProviderRef ref, String token, String tag) async {
    final String url = '${_buildProjectUrl(ref, forApi: true)}/repository/tags/${Uri.encodeComponent(tag)}';
    return (await _http.requestStatus(url, headers: _headers(token))) == HttpStatus.ok;
  }

  @override
  Future<String> tagCommitSha(ProviderRef ref, String token, String tag) async {
    final String url = '${_buildProjectUrl(ref, forApi: true)}/repository/tags/${Uri.encodeComponent(tag)}';

    final dynamic payload = await _http.requestJson(
      url,
      headers: _headers(token),
      retries: 3,
      retryDelay: const Duration(seconds: 2),
    );

    if (payload is! Map) {
      return '';
    }

    return (payload['target'] ?? '').toString();
  }

  @override
  Future<void> createTag(ProviderRef ref, String token, String tag, String sha, {String message = ''}) async {
    final String url = '${_buildProjectUrl(ref, forApi: true)}/repository/tags';

    final FormData form = FormData.fromMap(<String, dynamic>{
      'tag_name': tag,
      'ref': sha,
      if (message.isNotEmpty) 'message': message,
    });

    final Response<dynamic> response = await _dio.post<dynamic>(
      url,
      data: form,
      options: Options(
        headers: _headers(token),
        validateStatus: (_) => true,
      ),
    );

    final int status = response.statusCode ?? 0;
    if (status < HttpStatus.ok || status >= HttpStatus.multipleChoices) {
      throw HttpRequestError('GitLab create tag failed (HTTP $status)');
    }
  }

  @override
  Future<bool> releaseExists(ProviderRef ref, String token, String tag) async {
    final String url = '${_buildProjectUrl(ref, forApi: true)}/releases/${Uri.encodeComponent(tag)}';
    return (await _http.requestStatus(url, headers: _headers(token))) == HttpStatus.ok;
  }

  @override
  Future<Map<String, dynamic>?> releaseByTag(ProviderRef ref, String token, String tag) async {
    final String url = '${_buildProjectUrl(ref, forApi: true)}/releases/${Uri.encodeComponent(tag)}';
    try {
      final dynamic payload = await _http.requestJson(
        url,
        headers: _headers(token),
        retries: 3,
        retryDelay: const Duration(seconds: 2),
      );

      if (payload is Map) {
        return Map<String, dynamic>.from(payload);
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> createOrUpdateRelease(
    ProviderRef ref,
    String token,
    String tag,
    String name,
    String description,
    List<Map<String, dynamic>> links,
  ) async {
    final bool exists = await releaseExists(ref, token, tag);

    final String method = exists ? 'PUT' : 'POST';
    final String url = exists
        ? '${_buildProjectUrl(ref, forApi: true)}/releases/${Uri.encodeComponent(tag)}'
        : '${_buildProjectUrl(ref, forApi: true)}/releases';

    final Map<String, dynamic> payload = <String, dynamic>{
      if (!exists) 'tag_name': tag,
      'name': name,
      'description': description,
      'assets': <String, List<Map<String, dynamic>>>{'links': links},
    };

    await _http.requestJson(
      url,
      method: method,
      headers: _headers(token),
      jsonData: payload,
      retries: 3,
      retryDelay: const Duration(seconds: 2),
    );
  }

  @override
  Future<String> uploadFile(ProviderRef ref, String token, String filepath) async {
    final String url = '${_buildProjectUrl(ref, forApi: true)}/uploads';

    final FormData form = FormData.fromMap(<String, dynamic>{
      'file': await MultipartFile.fromFile(filepath),
    });

    final Response<dynamic> response = await _dio.post<dynamic>(
      url,
      data: form,
      options: Options(headers: _headers(token), validateStatus: (_) => true),
    );

    final int status = response.statusCode ?? 0;
    if (status < HttpStatus.ok || status >= HttpStatus.multipleChoices) {
      throw HttpRequestError('GitLab upload failed (HTTP $status)');
    }

    final dynamic payload = response.data;
    if (payload is! Map || payload['url'] == null) {
      throw HttpRequestError('GitLab upload did not return URL');
    }

    final String rel = payload['url'].toString();
    return '${ref.baseUrl.replaceAll(RegExp(r'/+$'), '')}$rel';
  }

  String buildReleaseDownloadApiUrl(ProviderRef ref, String tag, String resolvedUrl) {
    const String marker = '/-/releases/';
    if (!resolvedUrl.contains(marker)) {
      return '';
    }

    final String expected = '/-/releases/$tag/downloads/';
    if (!resolvedUrl.contains(expected)) {
      return '';
    }

    final String assetPath = resolvedUrl.split(expected).last.split('?').first;
    if (assetPath.isEmpty) {
      return '';
    }

    return '${_buildProjectUrl(ref, forApi: true)}/releases/${Uri.encodeComponent(tag)}/downloads/$assetPath';
  }

  String buildProjectUploadApiUrl(ProviderRef ref, String resolvedUrl) {
    const String marker = '/uploads/';
    if (!resolvedUrl.contains(marker)) {
      return '';
    }

    final String after = resolvedUrl.split(marker).last.split('?').first;
    if (!after.contains('/')) {
      return '';
    }

    final List<String> parts = after.split('/');
    if (parts.length < 2 || parts.first.isEmpty || parts[1].isEmpty) {
      return '';
    }

    final String secret = parts.first;
    final String name = parts.sublist(1).join('/');
    return '${_buildProjectUrl(ref, forApi: true)}/uploads/$secret/${Uri.encodeComponent(name)}';
  }

  String buildRepositoryArchiveApiUrl(ProviderRef ref, String tag, String format) {
    return '${_buildProjectUrl(ref, forApi: true)}/repository/archive.$format?sha=${Uri.encodeComponent(tag)}';
  }

  @override
  String buildTagUrl(ProviderRef ref, String tag) {
    return '${_buildProjectUrl(ref)}/-/tags/$tag';
  }

  String addPrivateTokenQuery(String url, String token) {
    return _http.addQueryParam(url, 'private_token', token);
  }

  @override
  Future<bool> downloadWithAuth(String token, String url, String destination) {
    return _http.downloadFile(
      url,
      destination,
      headers: _headers(token),
      retries: 3,
      backoff: const Duration(milliseconds: 750),
    );
  }

  Future<bool> downloadNoAuth(String url, String destination) {
    return _http.downloadFile(
      url,
      destination,
      headers: null,
      retries: 3,
      backoff: const Duration(milliseconds: 750),
    );
  }

  List<Map<String, dynamic>> _canonicalLinksFromPayload(Map<String, dynamic> payload) {
    final Map<String, dynamic> assets = ProviderCommon.mapFrom(payload['assets']);
    final List<Map<String, dynamic>> linksPayload = ProviderCommon.mapListFrom(assets['links']);
    final List<Map<String, dynamic>> links = <Map<String, dynamic>>[];
    for (final Map<String, dynamic> item in linksPayload) {
      links.add(<String, dynamic>{
        'name': (item['name'] ?? '').toString(),
        'url': (item['url'] ?? '').toString(),
        'direct_url': (item['direct_asset_url'] ?? '').toString(),
        'type': (item['link_type'] ?? 'other').toString(),
      });
    }

    return links;
  }

  List<Map<String, dynamic>> _canonicalSourcesFromPayload(Map<String, dynamic> payload) {
    final Map<String, dynamic> assets = ProviderCommon.mapFrom(payload['assets']);
    final List<Map<String, dynamic>> sourcesPayload = ProviderCommon.mapListFrom(assets['sources']);
    final List<Map<String, dynamic>> sources = <Map<String, dynamic>>[];
    for (final Map<String, dynamic> item in sourcesPayload) {
      final String sourceUrl = (item['url'] ?? '').toString();
      final String sourceName = sourceUrl.isEmpty ? '' : sourceUrl.split('?').first.split('/').last;
      sources.add(<String, dynamic>{
        'format': (item['format'] ?? 'source').toString(),
        'url': sourceUrl,
        'name': sourceName,
      });
    }

    return sources;
  }

  @override
  CanonicalRelease toCanonicalRelease(Map<String, dynamic> payload) {
    final List<Map<String, dynamic>> links = _canonicalLinksFromPayload(payload);
    final List<Map<String, dynamic>> sources = _canonicalSourcesFromPayload(payload);
    final dynamic commitPayload = payload['commit'];
    final Map<String, dynamic> commit =
        commitPayload is Map ? Map<String, dynamic>.from(commitPayload) : <String, dynamic>{};

    return CanonicalRelease.fromMap(<String, dynamic>{
      'tag_name': (payload['tag_name'] ?? '').toString(),
      'name': (payload['name'] ?? payload['tag_name'] ?? '').toString(),
      'description_markdown': (payload['description'] ?? '').toString(),
      'commit_sha': (commit['id'] ?? '').toString(),
      'assets': <String, List<Map<String, dynamic>>>{
        'links': links,
        'sources': sources,
      },
    });
  }

  @override
  Future<ExistingReleaseInfo> existingReleaseInfo(
    ProviderRef ref,
    String token,
    String tag,
    int expectedLinkAssets,
  ) async {
    final bool exists = await releaseExists(ref, token, tag);
    if (!exists) {
      return const ExistingReleaseInfo(exists: false, shouldRetry: false, reason: '');
    }

    final Map<String, dynamic>? release = await releaseByTag(ref, token, tag);
    int linksCount = 0;
    if (release != null) {
      final dynamic assetsRaw = release['assets'];
      final Map<String, dynamic> assets = assetsRaw is Map ? Map<String, dynamic>.from(assetsRaw) : <String, dynamic>{};
      final dynamic linksRaw = assets['links'];
      linksCount = linksRaw is List ? linksRaw.length : 0;
    }

    if (linksCount < expectedLinkAssets) {
      return ExistingReleaseInfo(
        exists: true,
        shouldRetry: true,
        reason: 'existing release with incomplete links ($linksCount/$expectedLinkAssets)',
      );
    }

    return const ExistingReleaseInfo(exists: true, shouldRetry: false, reason: '');
  }

  @override
  Future<String> publishRelease(PublishReleaseInput input) async {
    final List<({String name, String url})?> uploadResults =
        await Concurrency.mapWithLimit<String, ({String name, String url})?>(
      items: input.downloadedFiles,
      limit: _assetUploadWorkers,
      task: (String filePath, int _) async {
        final String name = ProviderCommon.basename(filePath);
        try {
          final String uploadedUrl = await uploadFile(input.providerRef, input.token, filePath);
          return (name: name, url: uploadedUrl);
        } catch (_) {
          return null;
        }
      },
    );

    final List<Map<String, dynamic>> links = <Map<String, dynamic>>[];
    for (final ({String name, String url})? item in uploadResults) {
      if (item == null) {
        continue;
      }
      links.add(<String, dynamic>{'name': item.name, 'url': item.url, 'link_type': 'other'});
    }

    final String notes = await input.notesFile.readAsString();
    await createOrUpdateRelease(
      input.providerRef,
      input.token,
      input.tag,
      input.releaseName,
      notes,
      links,
    );
    return 'ok';
  }

  @override
  Future<bool> downloadCanonicalLink(DownloadLinkInput input) async {
    final String directResolved =
        input.link.directUrl.isNotEmpty ? normalizeUrl(input.providerRef, input.link.directUrl) : '';
    final String rawResolved = input.link.url.isNotEmpty ? normalizeUrl(input.providerRef, input.link.url) : '';
    final bool hasRawCandidate = rawResolved.isNotEmpty && rawResolved != directResolved;

    final String directReleaseDownloadApiUrl =
        directResolved.isEmpty ? '' : buildReleaseDownloadApiUrl(input.providerRef, input.tag, directResolved);
    final String directUploadApiUrl =
        directResolved.isEmpty ? '' : buildProjectUploadApiUrl(input.providerRef, directResolved);
    final String rawUploadApiUrl = hasRawCandidate ? buildProjectUploadApiUrl(input.providerRef, rawResolved) : '';

    final List<String> authCandidates = <String>[
      directResolved,
      directReleaseDownloadApiUrl,
      directUploadApiUrl,
      if (hasRawCandidate) rawResolved,
      rawUploadApiUrl,
    ];

    for (final String candidate in authCandidates) {
      if (candidate.isEmpty) {
        continue;
      }

      final bool downloaded = await downloadWithAuth(input.token, candidate, input.outputPath);
      if (downloaded) {
        return true;
      }
    }

    final List<String> noAuthCandidates = <String>[
      if (directResolved.isNotEmpty) addPrivateTokenQuery(directResolved, input.token),
      if (hasRawCandidate) addPrivateTokenQuery(rawResolved, input.token),
    ];
    for (final String candidate in noAuthCandidates) {
      final bool downloaded = await downloadNoAuth(candidate, input.outputPath);
      if (downloaded) {
        return true;
      }
    }

    return false;
  }

  @override
  Future<bool> downloadCanonicalSource(DownloadSourceInput input) async {
    final List<String> authCandidates = <String>[];
    if (const <String>{'zip', 'tar.gz', 'tar.bz2', 'tar'}.contains(input.source.format)) {
      authCandidates.add(buildRepositoryArchiveApiUrl(input.providerRef, input.tag, input.source.format));
    }

    final String resolved = input.source.url.isNotEmpty ? normalizeUrl(input.providerRef, input.source.url) : '';
    authCandidates.add(resolved);
    for (final String candidate in authCandidates) {
      if (candidate.isEmpty) {
        continue;
      }

      final bool downloaded = await downloadWithAuth(input.token, candidate, input.outputPath);
      if (downloaded) {
        return true;
      }
    }

    if (resolved.isEmpty) {
      return false;
    }

    final String privateUrl = addPrivateTokenQuery(resolved, input.token);
    return downloadNoAuth(privateUrl, input.outputPath);
  }

  @override
  bool supportsSourceFallbackTagNotes() {
    return true;
  }

  String _buildProjectUrl(ProviderRef ref, {bool forApi = false}) {
    if (forApi) {
      return '${ref.baseUrl.replaceAll(RegExp(r'/+$'), '')}/api/v4/projects/${_projectEncoded(ref)}';
    }

    return '${ref.baseUrl.replaceAll(RegExp(r'/+$'), '')}/${ref.resource}';
  }
}
