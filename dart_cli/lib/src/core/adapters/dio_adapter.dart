import 'package:dio/dio.dart';

import '../types/http_config.dart';

class DioAdapter {
  DioAdapter({this.followRedirects, HttpConfig? config})
      : instance = Dio(BaseOptions(
          connectTimeout: Duration(milliseconds: config?.connectTimeoutMs ?? 10000),
          receiveTimeout: Duration(milliseconds: config?.receiveTimeoutMs ?? 90000),
          sendTimeout: const Duration(seconds: 90),
          followRedirects: followRedirects,
          validateStatus: (_) => true,
        ));

  final Dio instance;
  final bool? followRedirects;
}
