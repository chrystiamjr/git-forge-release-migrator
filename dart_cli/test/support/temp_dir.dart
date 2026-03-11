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

String withCurrentDirectory(Directory directory) {
  final String previous = Directory.current.path;
  Directory.current = directory.path;
  addTearDown(() => Directory.current = previous);
  return previous;
}
