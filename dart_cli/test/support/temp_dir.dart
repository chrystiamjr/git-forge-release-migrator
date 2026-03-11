import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

Directory createTempDir([String prefix = 'gfrm-test-']) {
  final Directory temp = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() {
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });
  return temp;
}

Future<T> runInCurrentDirectory<T>(Directory directory, FutureOr<T> Function() action) {
  Directory currentDirectory = directory;
  return IOOverrides.runZoned(
    () async => await action(),
    getCurrentDirectory: () => currentDirectory,
    setCurrentDirectory: (String path) {
      currentDirectory = Directory(path);
    },
  );
}
