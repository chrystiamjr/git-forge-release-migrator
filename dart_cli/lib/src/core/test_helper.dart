import 'dart:io';

final class TestEnvironment {
  const TestEnvironment._();

  static bool isTestProcess() {
    final String scriptPath = Platform.script.path;
    if (scriptPath.endsWith('_test.dart') ||
        scriptPath.contains('dart_test.kernel') ||
        scriptPath.contains('/test.dart_')) {
      return true;
    }

    final String dartTestFlag = (Platform.environment['DART_TEST'] ?? '').trim().toLowerCase();
    return dartTestFlag == '1' || dartTestFlag == 'true';
  }
}
