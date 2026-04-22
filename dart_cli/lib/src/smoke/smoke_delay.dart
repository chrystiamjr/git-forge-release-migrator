typedef SmokeDelay = Future<void> Function(Duration duration);

Future<void> defaultSmokeDelay(Duration duration) {
  return Future<void>.delayed(duration);
}
