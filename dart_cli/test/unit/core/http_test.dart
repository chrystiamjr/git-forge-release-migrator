import 'dart:io';

import 'package:dio/dio.dart';
import 'package:gfrm_dart/src/core/exceptions/authentication_error.dart';
import 'package:gfrm_dart/src/core/http.dart';
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
  });
}
