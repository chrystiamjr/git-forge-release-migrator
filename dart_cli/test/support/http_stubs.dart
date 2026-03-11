import 'package:dio/dio.dart';
import 'package:gfrm_dart/src/core/http.dart';

const Object _missingJsonResponse = Object();

final class ScriptedHttpClientHelper extends HttpClientHelper {
  ScriptedHttpClientHelper({
    Object? jsonResponse = _missingJsonResponse,
    this.jsonResponses = const <dynamic>[],
    int? statusCode,
    this.statusResponses = const <int>[],
    bool? downloadResult,
    this.downloadResponses = const <bool>[],
    this.onDownload,
  })  : _jsonSeed = jsonResponse,
        _statusSeed = statusCode,
        _downloadSeed = downloadResult,
        super(dio: Dio());

  final Object? _jsonSeed;
  final int? _statusSeed;
  final bool? _downloadSeed;
  final List<dynamic> jsonResponses;
  final List<int> statusResponses;
  final List<bool> downloadResponses;
  final Future<void> Function(String destination)? onDownload;

  int _jsonIndex = 0;
  int _statusIndex = 0;
  int _downloadIndex = 0;

  @override
  Future<dynamic> requestJson(
    String url, {
    int retries = 3,
    dynamic jsonData,
    String method = 'GET',
    Map<String, String>? headers,
    Duration retryDelay = const Duration(seconds: 2),
  }) async {
    if (_jsonIndex >= jsonResponses.length) {
      if (_jsonIndex == 0 && !identical(_jsonSeed, _missingJsonResponse)) {
        _jsonIndex += 1;
        return _unwrap(_jsonSeed);
      }
      return <String, dynamic>{};
    }

    final dynamic next = jsonResponses[_jsonIndex];
    _jsonIndex += 1;
    return _unwrap(next);
  }

  dynamic _unwrap(dynamic next) {
    if (next is Exception) {
      throw next;
    }
    if (next is Error) {
      throw next;
    }
    return next;
  }

  @override
  Future<int> requestStatus(String url, {Map<String, String>? headers}) async {
    if (_statusIndex >= statusResponses.length) {
      if (_statusIndex == 0 && _statusSeed != null) {
        _statusIndex += 1;
        return _statusSeed;
      }
      return 0;
    }

    final int next = statusResponses[_statusIndex];
    _statusIndex += 1;
    return next;
  }

  @override
  Future<bool> downloadFile(
    String url,
    String destination, {
    Map<String, String>? headers,
    int retries = 3,
    Duration backoff = const Duration(milliseconds: 750),
  }) async {
    if (onDownload != null) {
      await onDownload!(destination);
    }

    if (_downloadIndex >= downloadResponses.length) {
      if (_downloadIndex == 0 && _downloadSeed != null) {
        _downloadIndex += 1;
        return _downloadSeed;
      }
      return true;
    }

    final bool next = downloadResponses[_downloadIndex];
    _downloadIndex += 1;
    return next;
  }
}
