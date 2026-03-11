import 'dart:io';

abstract interface class FileOpsDriver {
  ProcessResult runProcess(String executable, List<String> arguments);

  void renameFile(File file, String newPath);

  File copyFile(File file, String newPath);

  void deleteFile(File file);
}
