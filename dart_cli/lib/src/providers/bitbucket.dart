import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../core/adapters/dio_adapter.dart';
import '../core/adapters/provider_adapter.dart';
import '../core/checkpoint.dart';
import '../core/exceptions/http_request_error.dart';
import '../core/http.dart';
import '../core/time.dart';
import '../core/types/canonical_release.dart';
import '../core/types/phase.dart';

class BitbucketAdapter extends ProviderAdapter {
  BitbucketAdapter({HttpClientHelper? http, Dio? dio})
      : _http = http ?? HttpClientHelper(),
        _dio = dio ?? DioAdapter().instance;

  final HttpClientHelper _http;
  final Dio _dio;

  static const String _apiBase = 'https://api.bitbucket.org/2.0';

  @override
  String get name => 'bitbucket';

  Map<String, String> _headers(String token) => <String, String>{'Authorization': 'Bearer $token'};

  String _repoApiUrl(ProviderRef ref, String suffix) {
    final String workspace = Uri.encodeComponent(ref.metadata['workspace'] ?? '');
    final String repo = Uri.encodeComponent(ref.metadata['repo'] ?? '');

    return '$_apiBase/repositories/$workspace/$repo$suffix';
  }

  Future<List<Map<String, dynamic>>> _paginatedValues(String startUrl, String token) async {
    final List<Map<String, dynamic>> values = <Map<String, dynamic>>[];
    String nextUrl = startUrl;

    while (nextUrl.isNotEmpty) {
      final dynamic payload = await _http.requestJson(
        nextUrl,
        headers: _headers(token),
        retries: 3,
        retryDelay: const Duration(seconds: 2),
      );

      if (payload is! Map) {
        break;
      }

      final dynamic pageValues = payload['values'];
      if (pageValues is List) {
        for (final dynamic item in pageValues) {
          if (item is Map) {
            values.add(Map<String, dynamic>.from(item));
          }
        }
      }

      final dynamic nextRaw = payload['next'];
      nextUrl = nextRaw == null ? '' : nextRaw.toString();
    }

    return values;
  }

  String _manifestFilename(String tag) {
    final String safeTag = tag.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    return '.gfrm-release-${safeTag.isEmpty ? 'tag' : safeTag}.json';
  }

  String _downloadUrlFromItem(Map<String, dynamic> item) {
    final dynamic linksRaw = item['links'];
    final Map<String, dynamic> links = linksRaw is Map ? Map<String, dynamic>.from(linksRaw) : <String, dynamic>{};

    final dynamic downloadRaw = links['download'];
    final Map<String, dynamic> download =
        downloadRaw is Map ? Map<String, dynamic>.from(downloadRaw) : <String, dynamic>{};
    final String href = (download['href'] ?? '').toString();
    if (href.isNotEmpty) {
      return href;
    }

    final dynamic selfRaw = links['self'];
    final Map<String, dynamic> selfLink = selfRaw is Map ? Map<String, dynamic>.from(selfRaw) : <String, dynamic>{};

    return (selfLink['href'] ?? '').toString();
  }

  String downloadUrl(Map<String, dynamic> item) => _downloadUrlFromItem(item);

  String _normalizeRepositoryUrl(String url) {
    String clean = url.trim();
    if (clean.endsWith('.git')) {
      clean = clean.substring(0, clean.length - 4);
    }

    return clean.split('?').first.split('#').first;
  }

  ({String host, String workspace, String repo, String baseUrl}) _extractSshParts(String normalizedUrl) {
    final RegExpMatch? ssh = RegExp(r'^git@([^:]+):([^/]+)/([^/]+)$').firstMatch(normalizedUrl);
    if (ssh == null) {
      return (host: '', workspace: '', repo: '', baseUrl: '');
    }

    final String host = ssh.group(1) ?? '';
    final String workspace = ssh.group(2) ?? '';
    final String repo = ssh.group(3) ?? '';
    return (host: host, workspace: workspace, repo: repo, baseUrl: 'https://$host');
  }

  ({String host, String workspace, String repo, String baseUrl}) _extractHttpsParts(
    String normalizedUrl,
    String originalUrl,
  ) {
    final RegExpMatch? https = RegExp(r'^https?://([^/]+)/(.+)$').firstMatch(normalizedUrl);
    if (https == null) {
      throw ArgumentError('Invalid Bitbucket URL: $originalUrl');
    }

    final String path = https.group(2) ?? '';
    final String host = https.group(1) ?? '';
    final String baseUrl = 'https://$host';
    final String projectPath = path.replaceFirst(RegExp(r'^/+'), '').split('/-/').first;
    final List<String> parts = projectPath.split('/').where((String item) => item.isNotEmpty).toList(growable: false);
    if (parts.length < 2) {
      throw ArgumentError('Invalid Bitbucket repository path: $originalUrl');
    }

    return (host: host, workspace: parts[0], repo: parts[1], baseUrl: baseUrl);
  }

  @override
  ProviderRef parseUrl(String url) {
    if (url.trim().isEmpty) {
      throw ArgumentError('Invalid Bitbucket URL: empty value');
    }

    final String normalizedUrl = _normalizeRepositoryUrl(url);
    final ({String host, String workspace, String repo, String baseUrl}) sshParts = _extractSshParts(normalizedUrl);
    final ({String host, String workspace, String repo, String baseUrl}) parts =
        sshParts.host.isNotEmpty ? sshParts : _extractHttpsParts(normalizedUrl, url);

    if (parts.host != 'bitbucket.org' || parts.workspace.isEmpty || parts.repo.isEmpty) {
      throw ArgumentError('Only Bitbucket Cloud URLs are supported in this phase');
    }

    return ProviderRef(
      provider: name,
      rawUrl: url,
      baseUrl: parts.baseUrl,
      host: parts.host,
      resource: '${parts.workspace}/${parts.repo}',
      metadata: <String, String>{
        'workspace': parts.workspace,
        'repo': parts.repo,
        'workspace_encoded': Uri.encodeComponent(parts.workspace),
        'repo_encoded': Uri.encodeComponent(parts.repo),
        'repo_ref': '${parts.workspace}/${parts.repo}',
      },
    );
  }

  @override
  String buildTagUrl(ProviderRef ref, String tag) {
    final String workspace = ref.metadata['workspace'] ?? '';
    final String repo = ref.metadata['repo'] ?? '';
    return '${ref.baseUrl.replaceAll(RegExp(r'/+$'), '')}/$workspace/$repo/src/$tag';
  }

  @override
  Future<List<String>> listTags(ProviderRef ref, String token) async {
    final List<Map<String, dynamic>> payload =
        await _paginatedValues(_repoApiUrl(ref, '/refs/tags?pagelen=100'), token);
    final List<String> tags = <String>[];
    for (final Map<String, dynamic> item in payload) {
      final String name = (item['name'] ?? '').toString().trim();
      if (name.isNotEmpty) {
        tags.add(name);
      }
    }
    return tags;
  }

  Future<List<Map<String, dynamic>>> listTagsPayload(ProviderRef ref, String token) {
    return _paginatedValues(_repoApiUrl(ref, '/refs/tags?pagelen=100'), token);
  }

  @override
  Future<bool> tagExists(ProviderRef ref, String token, String tag) async {
    final int status = await _http.requestStatus(
      _repoApiUrl(ref, '/refs/tags/${Uri.encodeComponent(tag)}'),
      headers: _headers(token),
    );
    return status == HttpStatus.ok;
  }

  @override
  Future<String> tagCommitSha(ProviderRef ref, String token, String tag) async {
    final dynamic payload = await _http.requestJson(
      _repoApiUrl(ref, '/refs/tags/${Uri.encodeComponent(tag)}'),
      headers: _headers(token),
      retries: 3,
      retryDelay: const Duration(seconds: 2),
    );

    if (payload is! Map) {
      return '';
    }
    final dynamic targetRaw = payload['target'];
    final Map<String, dynamic> target = targetRaw is Map ? Map<String, dynamic>.from(targetRaw) : <String, dynamic>{};
    return (target['hash'] ?? '').toString();
  }

  @override
  Future<void> createTag(ProviderRef ref, String token, String tag, String sha, {String message = ''}) async {
    final Map<String, dynamic> payload = <String, dynamic>{
      'name': tag,
      'target': <String, String>{'hash': sha},
      if (message.isNotEmpty) 'message': message,
    };

    await _http.requestJson(
      _repoApiUrl(ref, '/refs/tags'),
      method: 'POST',
      headers: _headers(token),
      jsonData: payload,
      retries: 3,
      retryDelay: const Duration(seconds: 2),
    );
  }

  Future<List<Map<String, dynamic>>> listDownloads(ProviderRef ref, String token) {
    return _paginatedValues(_repoApiUrl(ref, '/downloads?pagelen=100'), token);
  }

  Future<void> deleteDownload(ProviderRef ref, String token, String name) async {
    await _http.requestJson(
      _repoApiUrl(ref, '/downloads/${Uri.encodeComponent(name)}'),
      method: 'DELETE',
      headers: _headers(token),
      retries: 3,
      retryDelay: const Duration(seconds: 1),
    );
  }

  Future<Map<String, dynamic>> uploadDownload(ProviderRef ref, String token, String filepath) async {
    final FormData form = FormData.fromMap(<String, dynamic>{'files': await MultipartFile.fromFile(filepath)});
    final Response<dynamic> response = await _dio.post<dynamic>(
      _repoApiUrl(ref, '/downloads'),
      data: form,
      options: Options(headers: _headers(token), validateStatus: (_) => true),
    );

    final int status = response.statusCode ?? 0;
    if (status < HttpStatus.ok || status >= HttpStatus.multipleChoices) {
      throw HttpRequestError('Bitbucket downloads upload failed (HTTP $status)');
    }

    final dynamic payload = response.data;
    if (payload is! Map) {
      throw HttpRequestError('Bitbucket downloads upload returned invalid payload');
    }

    return Map<String, dynamic>.from(payload);
  }

  Future<Map<String, dynamic>> replaceDownload(
    ProviderRef ref,
    String token,
    String filepath, {
    String uploadName = '',
  }) async {
    final String targetName = uploadName.isNotEmpty ? uploadName : filepath.split('/').last;
    final Map<String, dynamic>? existing = await findDownloadByName(ref, token, targetName);
    if (existing != null) {
      await deleteDownload(ref, token, targetName);
    }
    return uploadDownload(ref, token, filepath);
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

  Future<Map<String, dynamic>?> findDownloadByName(ProviderRef ref, String token, String name) async {
    final List<Map<String, dynamic>> items = await listDownloads(ref, token);
    for (final Map<String, dynamic> item in items) {
      if ((item['name'] ?? '').toString() == name) {
        return item;
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> readReleaseManifest(ProviderRef ref, String token, String tag) async {
    final String manifestName = _manifestFilename(tag);
    final Map<String, dynamic>? item = await findDownloadByName(ref, token, manifestName);
    if (item == null) {
      return null;
    }
    final String manifestUrl = _downloadUrlFromItem(item);
    if (manifestUrl.isEmpty) {
      return null;
    }

    try {
      final dynamic payload = await _http.requestJson(manifestUrl,
          headers: _headers(token), retries: 3, retryDelay: const Duration(seconds: 1));
      if (payload is Map) {
        return Map<String, dynamic>.from(payload);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeReleaseManifest(
    ProviderRef ref,
    String token,
    String tag,
    Map<String, dynamic> manifest,
  ) async {
    final String manifestName = _manifestFilename(tag);
    final Directory tempDir = await Directory.systemTemp.createTemp('gfrm-bb-manifest-');
    try {
      final String path = '${tempDir.path}/$manifestName';
      File(path).writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(manifest)}\n');
      await replaceDownload(ref, token, path, uploadName: manifestName);
    } finally {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    }
  }

  Map<String, dynamic> buildReleaseManifest({
    required String tag,
    required String releaseName,
    required String notes,
    required List<Map<String, dynamic>> uploadedAssets,
    required List<Map<String, dynamic>> missingAssets,
  }) {
    final String notesHash = sha256.convert(utf8.encode(notes)).toString();
    return <String, dynamic>{
      'version': 1,
      'tag_name': tag,
      'release_name': releaseName.isEmpty ? tag : releaseName,
      'notes_hash': notesHash,
      'uploaded_assets': uploadedAssets,
      'missing_assets': missingAssets,
      'updated_at': TimeUtils.utcTimestamp(),
    };
  }

  bool manifestIsComplete(Map<String, dynamic>? manifest) {
    if (manifest == null) {
      return false;
    }
    final dynamic uploaded = manifest['uploaded_assets'];
    final dynamic missing = manifest['missing_assets'];
    if (uploaded is! List || missing is! List) {
      return false;
    }
    return missing.isEmpty;
  }

  @override
  Future<List<Map<String, dynamic>>> listReleases(ProviderRef ref, String token) async {
    final List<Map<String, dynamic>> tagsPayload = await listTagsPayload(ref, token);
    final List<Map<String, dynamic>> downloads = await listDownloads(ref, token);

    final Map<String, Map<String, dynamic>> downloadsByName = <String, Map<String, dynamic>>{};
    for (final Map<String, dynamic> item in downloads) {
      final String name = (item['name'] ?? '').toString().trim();
      if (name.isNotEmpty) {
        downloadsByName[name] = item;
      }
    }

    final List<Map<String, dynamic>> releases = <Map<String, dynamic>>[];

    for (final Map<String, dynamic> tagPayload in tagsPayload) {
      final String tag = (tagPayload['name'] ?? '').toString().trim();
      if (tag.isEmpty) {
        continue;
      }

      final String manifestName = _manifestFilename(tag);
      Map<String, dynamic>? manifest;
      final Map<String, dynamic>? manifestItem = downloadsByName[manifestName];
      if (manifestItem != null) {
        final String manifestUrl = _downloadUrlFromItem(manifestItem);
        if (manifestUrl.isNotEmpty) {
          try {
            final dynamic payload = await _http.requestJson(
              manifestUrl,
              headers: _headers(token),
              retries: 3,
              retryDelay: const Duration(seconds: 1),
            );

            if (payload is Map) {
              manifest = Map<String, dynamic>.from(payload);
            }
          } catch (_) {
            manifest = null;
          }
        }
      }

      final dynamic targetRaw = tagPayload['target'];
      final Map<String, dynamic> target = targetRaw is Map ? Map<String, dynamic>.from(targetRaw) : <String, dynamic>{};
      final String commitHash = (target['hash'] ?? '').toString();
      final String notes = (tagPayload['message'] ?? '').toString();

      String releaseName = tag;
      final List<Map<String, dynamic>> links = <Map<String, dynamic>>[];
      if (manifest != null) {
        releaseName = (manifest['release_name'] ?? tag).toString();
        final dynamic uploadedAssets = manifest['uploaded_assets'];
        if (uploadedAssets is List) {
          for (final dynamic item in uploadedAssets) {
            if (item is! Map) {
              continue;
            }
            final Map<String, dynamic> m = Map<String, dynamic>.from(item);
            final String name = (m['name'] ?? '').toString().trim();
            final String url = (m['url'] ?? '').toString().trim();
            if (name.isEmpty || url.isEmpty) {
              continue;
            }
            links.add(<String, dynamic>{
              'name': name,
              'url': url,
              'direct_url': url,
              'type': (m['type'] ?? 'package').toString(),
            });
          }
        }
      }

      releases.add(<String, dynamic>{
        'tag_name': tag,
        'name': releaseName,
        'description_markdown': notes,
        'commit_sha': commitHash,
        'assets': <String, List<Map<String, dynamic>>>{
          'links': links,
          'sources': <Map<String, dynamic>>[],
        },
        'provider_metadata': <String, Object>{
          'manifest_found': manifest != null,
          'legacy_no_manifest': manifest == null,
          'manifest': manifest ?? <String, dynamic>{},
        },
      });
    }

    return releases;
  }

  @override
  Future<Map<String, dynamic>?> releaseByTag(ProviderRef ref, String token, String tag) async {
    final List<Map<String, dynamic>> releases = await listReleases(ref, token);
    for (final Map<String, dynamic> release in releases) {
      if ((release['tag_name'] ?? '').toString() == tag) {
        return release;
      }
    }
    return null;
  }

  @override
  Future<bool> releaseExists(ProviderRef ref, String token, String tag) async {
    return tagExists(ref, token, tag);
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
    // Bitbucket release model is synthetic in this project: tag + downloads + manifest.
    final String existingSha = await tagCommitSha(ref, token, tag);
    if (existingSha.isEmpty) {
      throw HttpRequestError('Cannot update synthetic release for missing tag $tag');
    }

    await createTag(ref, token, tag, existingSha, message: description);

    final List<Map<String, dynamic>> uploaded = <Map<String, dynamic>>[];
    for (final Map<String, dynamic> item in links) {
      final String name = (item['name'] ?? '').toString();
      final String url = (item['url'] ?? '').toString();

      if (name.isNotEmpty && url.isNotEmpty) {
        uploaded.add(<String, dynamic>{'name': name, 'url': url, 'type': (item['type'] ?? 'other').toString()});
      }
    }

    final Map<String, dynamic> manifest = buildReleaseManifest(
      tag: tag,
      releaseName: name,
      notes: description,
      uploadedAssets: uploaded,
      missingAssets: const <Map<String, dynamic>>[],
    );

    await writeReleaseManifest(ref, token, tag, manifest);
  }

  @override
  Future<String> uploadFile(ProviderRef ref, String token, String filepath) async {
    final Map<String, dynamic> payload = await replaceDownload(ref, token, filepath);
    final String url = _downloadUrlFromItem(payload);

    if (url.isEmpty) {
      throw HttpRequestError('Bitbucket upload did not return a downloadable URL');
    }

    return url;
  }

  CanonicalRelease _canonicalLegacyPayload(Map<String, dynamic> payload, String tagName) {
    final dynamic targetRaw = payload['target'];
    final Map<String, dynamic> target = targetRaw is Map ? Map<String, dynamic>.from(targetRaw) : <String, dynamic>{};
    return CanonicalRelease.fromMap(<String, dynamic>{
      'tag_name': tagName,
      'name': (payload['name'] ?? tagName).toString(),
      'description_markdown': (payload['message'] ?? '').toString(),
      'commit_sha': (target['hash'] ?? '').toString(),
      'assets': <String, List<Map<String, dynamic>>>{
        'links': <Map<String, dynamic>>[],
        'sources': <Map<String, dynamic>>[],
      },
      'provider_metadata': <String, Object>{
        'manifest_found': false,
        'legacy_no_manifest': true,
        'manifest': <String, dynamic>{},
      },
    });
  }

  CanonicalRelease _canonicalNormalizedPayload(Map<String, dynamic> payload, String tagName) {
    final dynamic assetsRaw = payload['assets'];
    final Map<String, dynamic> assets = assetsRaw is Map ? Map<String, dynamic>.from(assetsRaw) : <String, dynamic>{};

    final dynamic linksRaw = assets['links'];
    final List<Map<String, dynamic>> links = linksRaw is List
        ? linksRaw
            .whereType<Map<String, dynamic>>()
            .map((Map<String, dynamic> item) => Map<String, dynamic>.from(item))
            .toList(growable: false)
        : <Map<String, dynamic>>[];

    final dynamic sourcesRaw = assets['sources'];
    final List<Map<String, dynamic>> sources = sourcesRaw is List
        ? sourcesRaw
            .whereType<Map<String, dynamic>>()
            .map((Map<String, dynamic> item) => Map<String, dynamic>.from(item))
            .toList(growable: false)
        : <Map<String, dynamic>>[];

    final dynamic metadataRaw = payload['provider_metadata'];
    final Map<String, dynamic> metadata =
        metadataRaw is Map ? Map<String, dynamic>.from(metadataRaw) : <String, dynamic>{};

    return CanonicalRelease.fromMap(<String, dynamic>{
      'tag_name': tagName,
      'name': (payload['name'] ?? tagName).toString(),
      'description_markdown': (payload['description_markdown'] ?? '').toString(),
      'commit_sha': (payload['commit_sha'] ?? '').toString(),
      'assets': <String, List<Map<String, dynamic>>>{
        'links': links,
        'sources': sources,
      },
      'provider_metadata': metadata,
    });
  }

  @override
  CanonicalRelease toCanonicalRelease(Map<String, dynamic> payload) {
    final String tagName = (payload['tag_name'] ?? '').toString();
    if (payload.containsKey('description_markdown')) {
      return _canonicalNormalizedPayload(payload, tagName);
    }

    return _canonicalLegacyPayload(payload, tagName);
  }

  @override
  Future<Set<String>> listTargetReleaseTags(ProviderRef ref, String token, Set<String> fallbackTags) async {
    return fallbackTags;
  }

  @override
  Future<void> createTagForMigration(
    ProviderRef ref,
    String token,
    String tag,
    String sha,
    CanonicalRelease canonical,
  ) {
    return createTag(ref, token, tag, sha, message: canonical.descriptionMarkdown);
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

    final bool tagExistsValue = await tagExists(ref, token, tag);
    if (!tagExistsValue) {
      return false;
    }

    final Map<String, dynamic>? manifest = await readReleaseManifest(ref, token, tag);
    return manifestIsComplete(manifest);
  }

  @override
  Future<ExistingReleaseInfo> existingReleaseInfo(
    ProviderRef ref,
    String token,
    String tag,
    int expectedLinkAssets,
  ) async {
    final bool tagExistsValue = await tagExists(ref, token, tag);
    if (!tagExistsValue) {
      return const ExistingReleaseInfo(exists: false, shouldRetry: false, reason: '');
    }

    final Map<String, dynamic>? manifest = await readReleaseManifest(ref, token, tag);
    if (manifestIsComplete(manifest)) {
      return const ExistingReleaseInfo(exists: true, shouldRetry: false, reason: '');
    }

    return const ExistingReleaseInfo(
      exists: true,
      shouldRetry: true,
      reason: 'existing synthetic release with missing manifest/assets',
    );
  }

  @override
  Future<String> publishRelease(PublishReleaseInput input) async {
    final List<Map<String, dynamic>> uploaded = <Map<String, dynamic>>[];
    final List<Map<String, dynamic>> missing = <Map<String, dynamic>>[];
    for (final String filePath in input.downloadedFiles) {
      final String name = filePath.split('/').last;

      try {
        final String uploadedUrl = await uploadFile(input.providerRef, input.token, filePath);
        uploaded.add(<String, dynamic>{'name': name, 'url': uploadedUrl, 'type': 'other'});
      } catch (_) {
        missing.add(<String, dynamic>{'name': name, 'url': ''});
      }
    }

    if (input.expectedAssets > 0 && uploaded.isEmpty) {
      return 'failed';
    }

    final Map<String, dynamic> manifest = buildReleaseManifest(
      tag: input.tag,
      releaseName: input.releaseName,
      notes: input.notesFile.readAsStringSync(),
      uploadedAssets: uploaded,
      missingAssets: missing,
    );

    await writeReleaseManifest(input.providerRef, input.token, input.tag, manifest);
    return 'ok';
  }

  @override
  Future<bool> downloadCanonicalLink(DownloadLinkInput input) async {
    final String resolved = input.link.directUrl.isNotEmpty ? input.link.directUrl : input.link.url;
    if (resolved.isEmpty) {
      return false;
    }

    return downloadWithAuth(input.token, resolved, input.outputPath);
  }

  @override
  Future<bool> downloadCanonicalSource(DownloadSourceInput input) async {
    if (input.source.url.isEmpty) {
      return false;
    }

    return downloadWithAuth(input.token, input.source.url, input.outputPath);
  }
}
