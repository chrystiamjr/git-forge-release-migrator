class HttpRequestError implements Exception {
  HttpRequestError(this.message);

  final String message;

  @override
  String toString() => message;
}
