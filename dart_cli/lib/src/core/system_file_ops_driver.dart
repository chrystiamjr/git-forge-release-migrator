import 'dart:io';

import 'package:gfrm_dart/src/core/file_ops_driver.dart';

final class SystemFileOpsDriver implements FileOpsDriver {
  const SystemFileOpsDriver();

  @override
  ProcessResult runProcess(String executable, List<String> arguments) {
    return Process.runSync(executable, arguments);
  }

  @override
  void renameFile(File file, String newPath) {
    file.renameSync(newPath);
  }

  @override
  File copyFile(File file, String newPath) {
    return file.copySync(newPath);
  }

  @override
  void deleteFile(File file) {
    file.deleteSync();
  }
}
