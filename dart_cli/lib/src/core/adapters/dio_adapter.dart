import 'package:dio/dio.dart';

class DioAdapter {
  final Dio instance;

  bool? followRedirects;

  DioAdapter({this.followRedirects})
      : instance = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 90),
          sendTimeout: const Duration(seconds: 90),
          followRedirects: followRedirects,
          validateStatus: (_) => true,
        ));
}
