import 'dart:io';

import 'package:gfrm_dart/src/core/system_file_ops_driver.dart';
import 'package:test/test.dart';

import '../../support/temp_dir.dart';

void main() {
  group('SystemFileOpsDriver', () {
    test('deleteFile removes an existing file', () {
      final Directory temp = createTempDir('gfrm-system-file-ops-');
      addTearDown(() => temp.deleteSync(recursive: true));
      final File file = File('${temp.path}/delete-me.txt')..writeAsStringSync('payload');
      final SystemFileOpsDriver driver = const SystemFileOpsDriver();

      driver.deleteFile(file);

      expect(file.existsSync(), isFalse);
    });
  });
}
