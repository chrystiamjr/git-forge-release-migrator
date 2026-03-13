import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';

import './adapters/dio_adapter.dart';
import './types/http_config.dart';
import 'exceptions/authentication_error.dart';
import 'exceptions/http_request_error.dart';

typedef DelayCallback = Future<void> Function(Duration duration);

class HttpClientHelper {
  HttpClientHelper({Dio? dio, HttpConfig? config, DelayCallback? delay})
      : _config = config ?? const HttpConfig(),
        _dio = dio ?? DioAdapter(followRedirects: true, config: config).instance,
        _delay = delay ?? _defaultDelay;

  final Dio _dio;
  final HttpConfig _config;
  final DelayCallback _delay;

  HttpConfig get config => _config;

  static Future<void> _defaultDelay(Duration duration) {
    return Future<void>.delayed(duration);
  }

  bool _isRateLimitedForbidden({
    required Headers? headers,
    required String body,
  }) {
    final String retryAfter = (headers?.value('retry-after') ?? '').trim();
    if (retryAfter.isNotEmpty) {
      return true;
    }

    final String xRateLimitRemaining = (headers?.value('x-ratelimit-remaining') ?? '').trim();
    if (xRateLimitRemaining == '0') {
      return true;
    }

    final String rateLimitRemaining = (headers?.value('ratelimit-remaining') ?? '').trim();
    if (rateLimitRemaining == '0') {
      return true;
    }

    final String lower = body.toLowerCase();
    return lower.contains('rate limit') || lower.contains('ratelimit') || lower.contains('too many requests');
  }

  int _safePreviewLength(String body) {
    return min(body.length, 300);
  }

  int _nextBackoffMillis(Duration wait) {
    final num next = (wait.inMilliseconds * 2).clamp(750, 5000);
    return next.toInt();
  }

  int? _parseRetryAfterSeconds(List<String> values) {
    if (values.isEmpty) {
      return null;
    }

    final String raw = values.first.trim();
    if (raw.isEmpty) {
      return null;
    }

    final int? asInt = int.tryParse(raw);
    if (asInt != null) {
      return asInt;
    }

    final double? asDouble = double.tryParse(raw);
    if (asDouble != null) {
      return asDouble.ceil();
    }

    return null;
  }

  Duration _waitWithRetryAfter(Duration wait, int? retryAfterSeconds) {
    if (retryAfterSeconds == null || retryAfterSeconds <= 0) {
      return wait;
    }

    final int retryAfterMillis = retryAfterSeconds * 1000;
    return Duration(milliseconds: max(wait.inMilliseconds, retryAfterMillis));
  }

  Future<dynamic> requestJson(
    String url, {
    int retries = 3,
    dynamic jsonData,
    String method = 'GET',
    Map<String, String>? headers,
    Duration retryDelay = const Duration(seconds: 2),
  }) async {
    String lastError = 'HTTP JSON request failed for $url';
    Duration wait = retryDelay;

    for (int attempt = 1; attempt <= retries; attempt += 1) {
      try {
        final Response<dynamic> response = await _dio.request<dynamic>(
          url,
          data: jsonData,
          options: Options(
            method: method,
            responseType: ResponseType.plain,
            headers: <String, dynamic>{
              ...?headers,
              if (jsonData != null) 'Content-Type': 'application/json',
            },
          ),
        );

        final int statusCode = response.statusCode ?? 0;
        final String body = (response.data ?? '').toString();

        if (statusCode >= HttpStatus.ok && statusCode < HttpStatus.multipleChoices) {
          if (body.trim().isEmpty) {
            return <String, dynamic>{};
          }

          try {
            final dynamic decoded = await _dio.transformer.transformResponse(
              RequestOptions(path: url),
              ResponseBody.fromString(
                body,
                statusCode,
                headers: <String, List<String>>{
                  Headers.contentTypeHeader: <String>[
                    response.headers.value(Headers.contentTypeHeader) ?? 'application/json',
                  ],
                },
              ),
            );
            return decoded;
          } catch (_) {
            try {
              return response.data is String ? response.data : <String, dynamic>{};
            } catch (_) {
              throw HttpRequestError('Invalid JSON from $url: ${body.substring(0, _safePreviewLength(body))}');
            }
          }
        }

        lastError = body.isEmpty ? 'HTTP $statusCode for $url' : body;

        if (statusCode == HttpStatus.unauthorized) {
          throw AuthenticationError('Authentication failed (401) for $url: $lastError');
        }

        if (statusCode == HttpStatus.forbidden &&
            !_isRateLimitedForbidden(headers: response.headers, body: lastError)) {
          throw AuthenticationError('Authorization denied (403) for $url: $lastError');
        }

        if (attempt < retries) {
          await _delay(wait);
          wait = Duration(milliseconds: _nextBackoffMillis(wait));
        }
      } on AuthenticationError {
        rethrow;
      } on DioException catch (exc) {
        final int status = exc.response?.statusCode ?? 0;
        lastError = exc.message ?? 'HTTP request failed for $url';

        if (status == HttpStatus.unauthorized) {
          throw AuthenticationError('Authentication failed (401) for $url: $lastError');
        }

        if (status == HttpStatus.forbidden &&
            !_isRateLimitedForbidden(
              headers: exc.response?.headers,
              body: (exc.response?.data ?? lastError).toString(),
            )) {
          throw AuthenticationError('Authorization denied (403) for $url: $lastError');
        }

        if (attempt < retries) {
          await _delay(wait);
          wait = Duration(milliseconds: _nextBackoffMillis(wait));
        }
      }
    }

    throw HttpRequestError(lastError);
  }

  Future<int> requestStatus(String url, {Map<String, String>? headers}) async {
    for (int attempt = 1; attempt <= 2; attempt += 1) {
      try {
        final Response<dynamic> response = await _dio.request<dynamic>(
          url,
          options: Options(
            method: 'GET',
            headers: headers,
            validateStatus: (_) => true,
            responseType: ResponseType.stream,
          ),
        );
        return response.statusCode ?? 0;
      } catch (_) {
        if (attempt < 2) {
          await _delay(const Duration(milliseconds: 500));
        }
      }
    }
    return 0;
  }

  Future<bool> downloadFile(
    String url,
    String destination, {
    Map<String, String>? headers,
    int retries = 3,
    Duration backoff = const Duration(milliseconds: 750),
  }) async {
    final File file = File(destination);
    file.parent.createSync(recursive: true);

    Duration wait = backoff;
    for (int attempt = 1; attempt <= retries; attempt += 1) {
      Duration nextWait = wait;
      try {
        if (file.existsSync()) file.deleteSync();

        final Response<dynamic> response = await _dio.download(
          url,
          destination,
          deleteOnError: true,
          options: Options(
            headers: headers,
            validateStatus: (_) => true,
            followRedirects: true,
            receiveTimeout: const Duration(seconds: 180),
          ),
        );

        final int status = response.statusCode ?? 0;
        if (status >= HttpStatus.ok && status < 400 && file.existsSync()) {
          return true;
        }

        if (status == HttpStatus.unauthorized || status == HttpStatus.notFound) {
          if (file.existsSync()) file.deleteSync();

          return false;
        }

        if (status == HttpStatus.forbidden) {
          final List<String> retryAfterValues = response.headers.map['retry-after'] ?? const <String>[];
          final bool hasRetryAfter = retryAfterValues.isNotEmpty;
          final bool hasRateLimit = hasRetryAfter || (response.headers.value('x-ratelimit-remaining') == '0');
          if (!hasRateLimit) {
            if (file.existsSync()) file.deleteSync();

            return false;
          }

          final int? retryAfterSeconds = _parseRetryAfterSeconds(retryAfterValues);
          nextWait = _waitWithRetryAfter(wait, retryAfterSeconds);
        }

        if (attempt < retries) {
          await _delay(nextWait);
          wait = Duration(milliseconds: _nextBackoffMillis(nextWait));
        }
      } on DioException catch (exc) {
        if (file.existsSync()) file.deleteSync();

        final int status = exc.response?.statusCode ?? 0;
        if (status == HttpStatus.unauthorized || status == HttpStatus.notFound) {
          return false;
        }

        if (status == HttpStatus.forbidden) {
          final Map<String, List<String>> headersMap = exc.response?.headers.map ?? const <String, List<String>>{};
          final List<String> retryAfterValues = headersMap['retry-after'] ?? const <String>[];
          final bool hasRetryAfter = retryAfterValues.isNotEmpty;
          final List<String> rateLimitValues = headersMap['x-ratelimit-remaining'] ?? const <String>[];
          final String rateLimitRemaining = rateLimitValues.isEmpty ? '' : rateLimitValues.first;
          final bool hasRateLimit = hasRetryAfter || rateLimitRemaining == '0';

          if (!hasRateLimit) {
            return false;
          }

          final int? retryAfterSeconds = _parseRetryAfterSeconds(retryAfterValues);
          nextWait = _waitWithRetryAfter(wait, retryAfterSeconds);
        }

        if (attempt < retries) {
          await _delay(nextWait);
          wait = Duration(milliseconds: _nextBackoffMillis(nextWait));
        }
      }
    }

    return false;
  }

  String addQueryParam(String url, String key, String value) {
    final Uri uri = Uri.parse(url);
    final Map<String, String> query = <String, String>{...uri.queryParameters, key: value};

    return uri.replace(queryParameters: query).toString();
  }
}
