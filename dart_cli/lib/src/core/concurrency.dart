final class Concurrency {
  const Concurrency._();

  static Future<List<TResult>> mapWithLimit<TItem, TResult>({
    required List<TItem> items,
    required int limit,
    required Future<TResult> Function(TItem item, int index) task,
  }) async {
    if (items.isEmpty) {
      return <TResult>[];
    }

    final int normalizedLimit = limit < 1 ? 1 : limit;
    if (normalizedLimit == 1) {
      final List<TResult> sequential = <TResult>[];
      for (int index = 0; index < items.length; index += 1) {
        sequential.add(await task(items[index], index));
      }

      return sequential;
    }

    final int workerCount = normalizedLimit > items.length ? items.length : normalizedLimit;
    final List<TResult?> results = List<TResult?>.filled(items.length, null, growable: false);
    int nextIndex = 0;

    Future<void> worker() async {
      while (true) {
        if (nextIndex >= items.length) {
          return;
        }

        final int current = nextIndex;
        nextIndex += 1;
        results[current] = await task(items[current], current);
      }
    }

    final List<Future<void>> workers = List<Future<void>>.generate(workerCount, (_) => worker(), growable: false);
    await Future.wait(workers);
    return results.cast<TResult>();
  }
}
