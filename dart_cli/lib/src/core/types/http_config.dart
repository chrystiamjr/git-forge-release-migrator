class HttpConfig {
  const HttpConfig({
    this.connectTimeoutMs = 10000,
    this.receiveTimeoutMs = 90000,
    this.maxRetries = 3,
    this.retryDelayMs = 750,
  });

  final int connectTimeoutMs;
  final int receiveTimeoutMs;
  final int maxRetries;
  final int retryDelayMs;

  Duration get connectTimeout => Duration(milliseconds: connectTimeoutMs);
  Duration get receiveTimeout => Duration(milliseconds: receiveTimeoutMs);
  Duration get retryDelay => Duration(milliseconds: retryDelayMs);
}
