import 'dart:io';

import 'package:dio/dio.dart';
import 'package:gfrm_dart/src/core/exceptions/authentication_error.dart';
import 'package:gfrm_dart/src/core/exceptions/http_request_error.dart';
import 'package:gfrm_dart/src/core/http.dart';
import 'package:gfrm_dart/src/core/types/http_config.dart';
import 'package:test/test.dart';

final class _QueueDio implements Dio {
  _QueueDio({
    List<dynamic>? requestResults,
    List<dynamic>? downloadResults,
  })  : _requestResults = requestResults ?? <dynamic>[],
        _downloadResults = downloadResults ?? <dynamic>[];

  final List<dynamic> _requestResults;
  final List<dynamic> _downloadResults;

  int requestCalls = 0;
  int downloadCalls = 0;
  Object? lastRequestData;
  Options? lastRequestOptions;
  @override
  Transformer transformer = BackgroundTransformer();

  @override
  Future<Response<T>> request<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    Options? options,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    requestCalls += 1;
    lastRequestData = data;
    lastRequestOptions = options;
    if (_requestResults.isEmpty) {
      throw StateError('No queued request result for $path');
    }

    final dynamic next = _requestResults.removeAt(0);
    if (next is DioException) {
      throw next;
    }

    if (next is Response<dynamic>) {
      return next as Response<T>;
    }

    throw StateError('Unsupported request result type: ${next.runtimeType}');
  }

  @override
  Future<Response<dynamic>> download(
    String urlPath,
    dynamic savePath, {
    ProgressCallback? onReceiveProgress,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    bool deleteOnError = true,
    FileAccessMode fileAccessMode = FileAccessMode.write,
    String lengthHeader = Headers.contentLengthHeader,
    Object? data,
    Options? options,
  }) async {
    downloadCalls += 1;
    if (_downloadResults.isEmpty) {
      throw StateError('No queued download result for $urlPath');
    }

    final dynamic next = _downloadResults.removeAt(0);
    if (next is DioException) {
      throw next;
    }

    if (next is! Response<dynamic>) {
      throw StateError('Unsupported download result type: ${next.runtimeType}');
    }

    final File file = File(savePath as String);
    final int statusCode = next.statusCode ?? 0;
    if (statusCode >= 200 && statusCode < 400) {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('ok');
    } else if (file.existsSync()) {
      file.deleteSync();
    }

    return next;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}

final class _ThrowingTransformer extends BackgroundTransformer {
  @override
  Future<dynamic> transformResponse(RequestOptions options, ResponseBody responseBody) {
    throw const FormatException('boom');
  }
}

Response<dynamic> _response(
  String path,
  int statusCode, {
  dynamic data = '',
  Map<String, List<String>> headers = const <String, List<String>>{},
}) {
  final RequestOptions requestOptions = RequestOptions(path: path);
  return Response<dynamic>(
    requestOptions: requestOptions,
    statusCode: statusCode,
    data: data,
    headers: Headers.fromMap(headers),
  );
}

DioException _dioException(
  String path,
  int statusCode, {
  dynamic data = '',
  Map<String, List<String>> headers = const <String, List<String>>{},
}) {
  final RequestOptions requestOptions = RequestOptions(path: path);
  return DioException(
    requestOptions: requestOptions,
    response: Response<dynamic>(
      requestOptions: requestOptions,
      statusCode: statusCode,
      data: data,
      headers: Headers.fromMap(headers),
    ),
    type: DioExceptionType.badResponse,
    message: 'bad response',
  );
}

void main() {
  group('http', () {
    test('config getter exposes the configured HttpConfig instance', () {
      const HttpConfig config = HttpConfig(connectTimeoutMs: 1500, retryDelayMs: 125);

      final HttpClientHelper helper = HttpClientHelper(config: config);

      expect(helper.config.connectTimeoutMs, 1500);
      expect(helper.config.retryDelayMs, 125);
    });

    test('addQueryParam appends key to URL without query', () {
      final HttpClientHelper helper = HttpClientHelper();

      final String result = helper.addQueryParam('https://example.com/path', 'token', 'abc123');

      expect(result, 'https://example.com/path?token=abc123');
    });

    test('addQueryParam replaces existing key and preserves others', () {
      final HttpClientHelper helper = HttpClientHelper();

      final String result = helper.addQueryParam('https://example.com/path?a=1&token=old', 'token', 'new');
      final Uri uri = Uri.parse(result);

      expect(uri.queryParameters['a'], '1');
      expect(uri.queryParameters['token'], 'new');
      expect(uri.path, '/path');
    });

    test('requestJson throws AuthenticationError on 401 response', () async {
      final _QueueDio dio = _QueueDio(
        requestResults: <dynamic>[_response('https://example.com/api', 401, data: 'unauthorized')],
      );
      final HttpClientHelper helper = HttpClientHelper(dio: dio);

      await expectLater(
        () => helper.requestJson(
          'https://example.com/api',
          retries: 1,
          retryDelay: Duration.zero,
        ),
        throwsA(isA<AuthenticationError>()),
      );
      expect(dio.requestCalls, 1);
    });

    test('requestJson retries rate-limit flavored 403 and succeeds', () async {
      final _QueueDio dio = _QueueDio(
        requestResults: <dynamic>[
          _response('https://example.com/api', 403, data: 'rate limit exceeded'),
          _response('https://example.com/api', 200, data: '{"ok":true}'),
        ],
      );
      final HttpClientHelper helper = HttpClientHelper(dio: dio);

      final dynamic result = await helper.requestJson(
        'https://example.com/api',
        retries: 2,
        retryDelay: Duration.zero,
      );

      expect((result as Map<String, dynamic>)['ok'], isTrue);
      expect(dio.requestCalls, 2);
    });

    test('requestJson retries 403 response with rate-limit header and waits before succeeding', () async {
      final _QueueDio dio = _QueueDio(
        requestResults: <dynamic>[
          _response(
            'https://example.com/api',
            403,
            data: 'temporarily blocked',
            headers: <String, List<String>>{
              'x-ratelimit-remaining': <String>['0'],
            },
          ),
          _response('https://example.com/api', 200, data: '{"ok":true}'),
        ],
      );
      final List<Duration> delays = <Duration>[];
      final HttpClientHelper helper = HttpClientHelper(
        dio: dio,
        delay: (Duration duration) async {
          delays.add(duration);
        },
      );

      final dynamic result = await helper.requestJson(
        'https://example.com/api',
        retries: 2,
        retryDelay: const Duration(milliseconds: 250),
      );

      expect((result as Map<String, dynamic>)['ok'], isTrue);
      expect(delays, <Duration>[const Duration(milliseconds: 250)]);
      expect(dio.requestCalls, 2);
    });

    test('requestJson retries 403 response with retry-after header and succeeds', () async {
      final _QueueDio dio = _QueueDio(
        requestResults: <dynamic>[
          _response(
            'https://example.com/api',
            403,
            data: 'temporarily blocked',
            headers: <String, List<String>>{
              'retry-after': <String>['1'],
            },
          ),
          _response('https://example.com/api', 200, data: '{"ok":true}'),
        ],
      );
      final List<Duration> delays = <Duration>[];
      final HttpClientHelper helper = HttpClientHelper(
        dio: dio,
        delay: (Duration duration) async {
          delays.add(duration);
        },
      );

      final dynamic result = await helper.requestJson(
        'https://example.com/api',
        retries: 2,
        retryDelay: const Duration(milliseconds: 250),
      );

      expect((result as Map<String, dynamic>)['ok'], isTrue);
      expect(delays, <Duration>[const Duration(milliseconds: 250)]);
      expect(dio.requestCalls, 2);
    });

    test('requestJson retries 403 response with ratelimit-remaining header and succeeds', () async {
      final _QueueDio dio = _QueueDio(
        requestResults: <dynamic>[
          _response(
            'https://example.com/api',
            403,
            data: 'temporarily blocked',
            headers: <String, List<String>>{
              'ratelimit-remaining': <String>['0'],
            },
          ),
          _response('https://example.com/api', 200, data: '{"ok":true}'),
        ],
      );
      final HttpClientHelper helper = HttpClientHelper(dio: dio);

      final dynamic result = await helper.requestJson(
        'https://example.com/api',
        retries: 2,
        retryDelay: Duration.zero,
      );

      expect((result as Map<String, dynamic>)['ok'], isTrue);
      expect(dio.requestCalls, 2);
    });

    test('requestJson uses injected delay before retrying retryable responses', () async {
      final _QueueDio dio = _QueueDio(
        requestResults: <dynamic>[
          _response('https://example.com/api', 500, data: 'server error'),
          _response('https://example.com/api', 200, data: '{"ok":true}'),
        ],
      );
      final List<Duration> delays = <Duration>[];
      final HttpClientHelper helper = HttpClientHelper(
        dio: dio,
        delay: (Duration duration) async {
          delays.add(duration);
        },
      );

      final dynamic result = await helper.requestJson(
        'https://example.com/api',
        retries: 2,
        retryDelay: const Duration(milliseconds: 250),
      );

      expect((result as Map<String, dynamic>)['ok'], isTrue);
      expect(dio.requestCalls, 2);
      expect(delays, <Duration>[const Duration(milliseconds: 250)]);
    });

    test('requestJson keeps request method and content type when json payload is sent', () async {
      final _QueueDio dio = _QueueDio(
        requestResults: <dynamic>[_response('https://example.com/api', 200, data: '{"ok":true}')],
      );
      final HttpClientHelper helper = HttpClientHelper(dio: dio);

      final dynamic result = await helper.requestJson(
        'https://example.com/api',
        method: 'POST',
        jsonData: <String, dynamic>{'hello': 'world'},
        retries: 1,
        retryDelay: Duration.zero,
      );

      expect((result as Map<String, dynamic>)['ok'], isTrue);
      expect(dio.lastRequestData, <String, dynamic>{'hello': 'world'});
      expect(dio.lastRequestOptions!.method, 'POST');
      expect(dio.lastRequestOptions!.headers!['Content-Type'], 'application/json');
    });

    test('requestJson throws AuthenticationError on non-rate-limit 403', () async {
      final _QueueDio dio = _QueueDio(
        requestResults: <dynamic>[_response('https://example.com/api', 403, data: 'forbidden')],
      );
      final HttpClientHelper helper = HttpClientHelper(dio: dio);

      await expectLater(
        () => helper.requestJson(
          'https://example.com/api',
          retries: 1,
          retryDelay: Duration.zero,
        ),
        throwsA(isA<AuthenticationError>()),
      );
      expect(dio.requestCalls, 1);
    });

    test('requestJson retries DioException 403 with rate-limit headers', () async {
      final _QueueDio dio = _QueueDio(
        requestResults: <dynamic>[
          _dioException(
            'https://example.com/api',
            403,
            data: 'temporarily blocked',
            headers: <String, List<String>>{
              'retry-after': <String>['1'],
            },
          ),
          _response('https://example.com/api', 200, data: '{"ok":true}'),
        ],
      );
      final HttpClientHelper helper = HttpClientHelper(dio: dio);

      final dynamic result = await helper.requestJson(
        'https://example.com/api',
        retries: 2,
        retryDelay: Duration.zero,
      );

      expect((result as Map<String, dynamic>)['ok'], isTrue);
      expect(dio.requestCalls, 2);
    });

    test('requestJson returns empty map when 2xx body is empty', () async {
      final _QueueDio dio = _QueueDio(
        requestResults: <dynamic>[_response('https://example.com/api', 204, data: '')],
      );
      final HttpClientHelper helper = HttpClientHelper(dio: dio);

      final dynamic result = await helper.requestJson(
        'https://example.com/api',
        retries: 1,
        retryDelay: Duration.zero,
      );

      expect(result, <String, dynamic>{});
    });

    test('requestJson preserves plain string body when JSON decoding fails', () async {
      final _QueueDio dio = _QueueDio(
        requestResults: <dynamic>[_response('https://example.com/api', 200, data: 'not-json')],
      );
      final HttpClientHelper helper = HttpClientHelper(dio: dio);

      final dynamic result = await helper.requestJson(
        'https://example.com/api',
        retries: 1,
        retryDelay: Duration.zero,
      );

      expect(result, 'not-json');
    });

    test('requestJson returns empty map when transformer fails and fallback body is non-string', () async {
      final _QueueDio dio = _QueueDio(
        requestResults: <dynamic>[
          _response('https://example.com/api', 200, data: <String, dynamic>{'unexpected': true}),
        ],
      )..transformer = _ThrowingTransformer();
      final HttpClientHelper helper = HttpClientHelper(dio: dio);

      final dynamic result = await helper.requestJson(
        'https://example.com/api',
        retries: 1,
        retryDelay: Duration.zero,
      );

      expect(result, <String, dynamic>{});
    });

    test('requestJson throws AuthenticationError on DioException 403 without rate-limit signals', () async {
      final _QueueDio dio = _QueueDio(
        requestResults: <dynamic>[
          _dioException('https://example.com/api', 403, data: 'forbidden'),
        ],
      );
      final HttpClientHelper helper = HttpClientHelper(dio: dio);

      await expectLater(
        () => helper.requestJson(
          'https://example.com/api',
          retries: 1,
          retryDelay: Duration.zero,
        ),
        throwsA(isA<AuthenticationError>()),
      );
    });

    test('requestJson throws AuthenticationError on DioException 401 responses', () async {
      final _QueueDio dio = _QueueDio(
        requestResults: <dynamic>[
          _dioException('https://example.com/api', 401, data: 'unauthorized'),
        ],
      );
      final HttpClientHelper helper = HttpClientHelper(dio: dio);

      await expectLater(
        () => helper.requestJson(
          'https://example.com/api',
          retries: 1,
          retryDelay: Duration.zero,
        ),
        throwsA(isA<AuthenticationError>()),
      );
    });

    test('requestJson throws HttpRequestError after retryable responses are exhausted', () async {
      final _QueueDio dio = _QueueDio(
        requestResults: <dynamic>[
          _response('https://example.com/api', 500, data: 'server error'),
          _response('https://example.com/api', 502, data: 'still broken'),
        ],
      );
      final List<Duration> delays = <Duration>[];
      final HttpClientHelper helper = HttpClientHelper(
        dio: dio,
        delay: (Duration duration) async {
          delays.add(duration);
        },
      );

      await expectLater(
        () => helper.requestJson(
          'https://example.com/api',
          retries: 2,
          retryDelay: const Duration(milliseconds: 250),
        ),
        throwsA(isA<HttpRequestError>()),
      );
      expect(delays, <Duration>[const Duration(milliseconds: 250)]);
    });

    test('requestStatus returns response status when request succeeds', () async {
      final _QueueDio dio = _QueueDio(
        requestResults: <dynamic>[_response('https://example.com/api', 202)],
      );
      final HttpClientHelper helper = HttpClientHelper(dio: dio);

      final int status = await helper.requestStatus('https://example.com/api');

      expect(status, 202);
      expect(dio.requestCalls, 1);
    });

    test('requestStatus retries once and returns zero after repeated failures', () async {
      final _QueueDio dio = _QueueDio(
        requestResults: <dynamic>[
          DioException(requestOptions: RequestOptions(path: 'https://example.com/api')),
          DioException(requestOptions: RequestOptions(path: 'https://example.com/api')),
        ],
      );
      final HttpClientHelper helper = HttpClientHelper(dio: dio);

      final int status = await helper.requestStatus('https://example.com/api');

      expect(status, 0);
      expect(dio.requestCalls, 2);
    });

    test('requestStatus uses injected delay before a successful retry', () async {
      final _QueueDio dio = _QueueDio(
        requestResults: <dynamic>[
          DioException(
            requestOptions: RequestOptions(path: 'https://example.com/status'),
            type: DioExceptionType.connectionError,
            message: 'network down',
          ),
          _response('https://example.com/status', 204),
        ],
      );
      final List<Duration> delays = <Duration>[];
      final HttpClientHelper helper = HttpClientHelper(
        dio: dio,
        delay: (Duration duration) async {
          delays.add(duration);
        },
      );

      final int status = await helper.requestStatus('https://example.com/status');

      expect(status, 204);
      expect(dio.requestCalls, 2);
      expect(delays, <Duration>[const Duration(milliseconds: 500)]);
    });

    test('requestStatus forwards custom headers on the request', () async {
      final _QueueDio dio = _QueueDio(
        requestResults: <dynamic>[_response('https://example.com/status', 204)],
      );
      final HttpClientHelper helper = HttpClientHelper(dio: dio);

      final int status = await helper.requestStatus(
        'https://example.com/status',
        headers: <String, String>{'Authorization': 'Bearer token'},
      );

      expect(status, 204);
      expect(dio.lastRequestOptions!.headers!['Authorization'], 'Bearer token');
      expect(dio.lastRequestOptions!.method, 'GET');
    });

    test('downloadFile retries rate-limit 403 and succeeds', () async {
      final Directory temp = Directory.systemTemp.createTempSync('gfrm-http-download-');
      addTearDown(() => temp.deleteSync(recursive: true));

      final _QueueDio dio = _QueueDio(
        downloadResults: <dynamic>[
          _response(
            'https://example.com/file.zip',
            403,
            headers: <String, List<String>>{
              'retry-after': <String>['1'],
            },
          ),
          _response('https://example.com/file.zip', 200),
        ],
      );
      final HttpClientHelper helper = HttpClientHelper(dio: dio);
      final String destination = '${temp.path}/file.zip';

      final bool ok = await helper.downloadFile(
        'https://example.com/file.zip',
        destination,
        retries: 2,
        backoff: Duration.zero,
      );

      expect(ok, isTrue);
      expect(File(destination).existsSync(), isTrue);
      expect(dio.downloadCalls, 2);
    });

    test('downloadFile retries on x-ratelimit-remaining response header and succeeds', () async {
      final Directory temp = Directory.systemTemp.createTempSync('gfrm-http-download-rate-limit-header-');
      addTearDown(() => temp.deleteSync(recursive: true));

      final _QueueDio dio = _QueueDio(
        downloadResults: <dynamic>[
          _response(
            'https://example.com/file.zip',
            403,
            headers: <String, List<String>>{
              'x-ratelimit-remaining': <String>['0'],
            },
          ),
          _response('https://example.com/file.zip', 200),
        ],
      );
      final List<Duration> delays = <Duration>[];
      final HttpClientHelper helper = HttpClientHelper(
        dio: dio,
        delay: (Duration duration) async {
          delays.add(duration);
        },
      );
      final String destination = '${temp.path}/file.zip';

      final bool ok = await helper.downloadFile(
        'https://example.com/file.zip',
        destination,
        retries: 2,
        backoff: const Duration(milliseconds: 250),
      );

      expect(ok, isTrue);
      expect(delays, <Duration>[const Duration(milliseconds: 250)]);
      expect(File(destination).existsSync(), isTrue);
    });

    test('downloadFile honors retry-after seconds before next retry', () async {
      final Directory temp = Directory.systemTemp.createTempSync('gfrm-http-download-retry-after-');
      addTearDown(() => temp.deleteSync(recursive: true));

      final _QueueDio dio = _QueueDio(
        downloadResults: <dynamic>[
          _response(
            'https://example.com/file.zip',
            403,
            headers: <String, List<String>>{
              'retry-after': <String>['1'],
            },
          ),
          _response('https://example.com/file.zip', 200),
        ],
      );
      final List<Duration> delays = <Duration>[];
      final HttpClientHelper helper = HttpClientHelper(
        dio: dio,
        delay: (Duration duration) async {
          delays.add(duration);
        },
      );
      final String destination = '${temp.path}/file.zip';

      final bool ok = await helper.downloadFile(
        'https://example.com/file.zip',
        destination,
        retries: 2,
        backoff: Duration.zero,
      );

      expect(ok, isTrue);
      expect(dio.downloadCalls, 2);
      expect(delays, <Duration>[const Duration(seconds: 1)]);
    });

    test('downloadFile returns false on non-rate-limit 403 without retry loop', () async {
      final Directory temp = Directory.systemTemp.createTempSync('gfrm-http-download-fail-');
      addTearDown(() => temp.deleteSync(recursive: true));

      final _QueueDio dio = _QueueDio(
        downloadResults: <dynamic>[
          _response('https://example.com/file.zip', 403),
        ],
      );
      final HttpClientHelper helper = HttpClientHelper(dio: dio);
      final String destination = '${temp.path}/file.zip';

      final bool ok = await helper.downloadFile(
        'https://example.com/file.zip',
        destination,
        retries: 3,
        backoff: Duration.zero,
      );

      expect(ok, isFalse);
      expect(dio.downloadCalls, 1);
    });

    test('downloadFile does not retry when retry-after header list is empty', () async {
      final Directory temp = Directory.systemTemp.createTempSync('gfrm-http-download-empty-retry-after-');
      addTearDown(() => temp.deleteSync(recursive: true));

      final _QueueDio dio = _QueueDio(
        downloadResults: <dynamic>[
          _response(
            'https://example.com/file.zip',
            403,
            headers: <String, List<String>>{
              'retry-after': <String>[],
            },
          ),
        ],
      );
      final HttpClientHelper helper = HttpClientHelper(dio: dio);
      final String destination = '${temp.path}/file.zip';

      final bool ok = await helper.downloadFile(
        'https://example.com/file.zip',
        destination,
        retries: 3,
        backoff: Duration.zero,
      );

      expect(ok, isFalse);
      expect(dio.downloadCalls, 1);
    });

    test('downloadFile returns false on 401 response and cleans existing file', () async {
      final Directory temp = Directory.systemTemp.createTempSync('gfrm-http-download-unauthorized-');
      addTearDown(() => temp.deleteSync(recursive: true));

      final _QueueDio dio = _QueueDio(
        downloadResults: <dynamic>[
          _response('https://example.com/file.zip', 401),
        ],
      );
      final HttpClientHelper helper = HttpClientHelper(dio: dio);
      final String destination = '${temp.path}/file.zip';
      File(destination).writeAsStringSync('stale');

      final bool ok = await helper.downloadFile(
        'https://example.com/file.zip',
        destination,
        retries: 2,
        backoff: Duration.zero,
      );

      expect(ok, isFalse);
      expect(File(destination).existsSync(), isFalse);
      expect(dio.downloadCalls, 1);
    });

    test('downloadFile retries DioException 403 with x-ratelimit-remaining and succeeds', () async {
      final Directory temp = Directory.systemTemp.createTempSync('gfrm-http-download-dio-rate-limit-');
      addTearDown(() => temp.deleteSync(recursive: true));

      final _QueueDio dio = _QueueDio(
        downloadResults: <dynamic>[
          _dioException(
            'https://example.com/file.zip',
            403,
            headers: <String, List<String>>{
              'x-ratelimit-remaining': <String>['0'],
            },
          ),
          _response('https://example.com/file.zip', 200),
        ],
      );
      final HttpClientHelper helper = HttpClientHelper(dio: dio);
      final String destination = '${temp.path}/file.zip';

      final bool ok = await helper.downloadFile(
        'https://example.com/file.zip',
        destination,
        retries: 2,
        backoff: Duration.zero,
      );

      expect(ok, isTrue);
      expect(File(destination).existsSync(), isTrue);
      expect(dio.downloadCalls, 2);
    });

    test('downloadFile retries DioException 403 with decimal retry-after and succeeds', () async {
      final Directory temp = Directory.systemTemp.createTempSync('gfrm-http-download-decimal-retry-after-');
      addTearDown(() => temp.deleteSync(recursive: true));

      final _QueueDio dio = _QueueDio(
        downloadResults: <dynamic>[
          _dioException(
            'https://example.com/file.zip',
            403,
            headers: <String, List<String>>{
              'retry-after': <String>['0.2'],
            },
          ),
          _response('https://example.com/file.zip', 200),
        ],
      );
      final List<Duration> delays = <Duration>[];
      final HttpClientHelper helper = HttpClientHelper(
        dio: dio,
        delay: (Duration duration) async {
          delays.add(duration);
        },
      );
      final String destination = '${temp.path}/file.zip';

      final bool ok = await helper.downloadFile(
        'https://example.com/file.zip',
        destination,
        retries: 2,
        backoff: Duration.zero,
      );

      expect(ok, isTrue);
      expect(dio.downloadCalls, 2);
      expect(delays, <Duration>[const Duration(seconds: 1)]);
    });

    test('downloadFile retries DioException 403 with blank retry-after and x-ratelimit header', () async {
      final Directory temp = Directory.systemTemp.createTempSync('gfrm-http-download-blank-retry-after-');
      addTearDown(() => temp.deleteSync(recursive: true));

      final _QueueDio dio = _QueueDio(
        downloadResults: <dynamic>[
          _dioException(
            'https://example.com/file.zip',
            403,
            headers: <String, List<String>>{
              'retry-after': <String>[''],
              'x-ratelimit-remaining': <String>['0'],
            },
          ),
          _response('https://example.com/file.zip', 200),
        ],
      );
      final List<Duration> delays = <Duration>[];
      final HttpClientHelper helper = HttpClientHelper(
        dio: dio,
        delay: (Duration duration) async {
          delays.add(duration);
        },
      );
      final String destination = '${temp.path}/file.zip';

      final bool ok = await helper.downloadFile(
        'https://example.com/file.zip',
        destination,
        retries: 2,
        backoff: const Duration(milliseconds: 250),
      );

      expect(ok, isTrue);
      expect(delays, <Duration>[const Duration(milliseconds: 250)]);
      expect(File(destination).existsSync(), isTrue);
    });

    test('downloadFile returns false on DioException 404 without retrying', () async {
      final Directory temp = Directory.systemTemp.createTempSync('gfrm-http-download-not-found-');
      addTearDown(() => temp.deleteSync(recursive: true));

      final _QueueDio dio = _QueueDio(
        downloadResults: <dynamic>[
          _dioException('https://example.com/file.zip', 404),
        ],
      );
      final HttpClientHelper helper = HttpClientHelper(dio: dio);
      final String destination = '${temp.path}/file.zip';

      final bool ok = await helper.downloadFile(
        'https://example.com/file.zip',
        destination,
        retries: 3,
        backoff: Duration.zero,
      );

      expect(ok, isFalse);
      expect(dio.downloadCalls, 1);
    });

    test('downloadFile returns false on DioException 403 without rate-limit signals', () async {
      final Directory temp = Directory.systemTemp.createTempSync('gfrm-http-download-dio-forbidden-');
      addTearDown(() => temp.deleteSync(recursive: true));

      final _QueueDio dio = _QueueDio(
        downloadResults: <dynamic>[
          _dioException('https://example.com/file.zip', 403),
        ],
      );
      final HttpClientHelper helper = HttpClientHelper(dio: dio);
      final String destination = '${temp.path}/file.zip';

      final bool ok = await helper.downloadFile(
        'https://example.com/file.zip',
        destination,
        retries: 2,
        backoff: Duration.zero,
      );

      expect(ok, isFalse);
      expect(dio.downloadCalls, 1);
      expect(File(destination).existsSync(), isFalse);
    });

    test('downloadFile retries retryable non-auth responses and returns false after exhaustion', () async {
      final Directory temp = Directory.systemTemp.createTempSync('gfrm-http-download-exhausted-');
      addTearDown(() => temp.deleteSync(recursive: true));

      final _QueueDio dio = _QueueDio(
        downloadResults: <dynamic>[
          _response('https://example.com/file.zip', 500),
          _response('https://example.com/file.zip', 500),
        ],
      );
      final List<Duration> delays = <Duration>[];
      final HttpClientHelper helper = HttpClientHelper(
        dio: dio,
        delay: (Duration duration) async {
          delays.add(duration);
        },
      );
      final String destination = '${temp.path}/file.zip';

      final bool ok = await helper.downloadFile(
        'https://example.com/file.zip',
        destination,
        retries: 2,
        backoff: const Duration(milliseconds: 250),
      );

      expect(ok, isFalse);
      expect(delays, <Duration>[const Duration(milliseconds: 250)]);
      expect(dio.downloadCalls, 2);
    });

    test('downloadFile retries retryable Dio exceptions and returns false after exhaustion', () async {
      final Directory temp = Directory.systemTemp.createTempSync('gfrm-http-download-dio-exhausted-');
      addTearDown(() => temp.deleteSync(recursive: true));

      final _QueueDio dio = _QueueDio(
        downloadResults: <dynamic>[
          _dioException('https://example.com/file.zip', 500),
          _dioException('https://example.com/file.zip', 500),
        ],
      );
      final List<Duration> delays = <Duration>[];
      final HttpClientHelper helper = HttpClientHelper(
        dio: dio,
        delay: (Duration duration) async {
          delays.add(duration);
        },
      );
      final String destination = '${temp.path}/file.zip';

      final bool ok = await helper.downloadFile(
        'https://example.com/file.zip',
        destination,
        retries: 2,
        backoff: const Duration(milliseconds: 250),
      );

      expect(ok, isFalse);
      expect(delays, <Duration>[const Duration(milliseconds: 250)]);
      expect(dio.downloadCalls, 2);
    });
  });
}
