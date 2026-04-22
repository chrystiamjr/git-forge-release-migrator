import 'dart:convert';
import 'dart:io';

/// Retry-command expectation for the smoke artifact contract.
enum RetryExpectation {
  /// `summary.retry_command` must be empty or missing.
  empty,

  /// `summary.retry_command` must be present and start with `gfrm resume`.
  nonempty,

  /// Either presence or absence is acceptable.
  any,
}

/// Validation result for a single migration run directory.
final class ValidationReport {
  const ValidationReport(
      {required this.passed, this.errors = const <String>[]});

  final bool passed;
  final List<String> errors;
}

/// Asserts that a migration run directory matches the expected artifact
/// contract used by the smoke flow.
///
/// Mirrors the checks performed by the historical bash e2e runner so
/// `gfrm smoke` produces the same signal.
final class ArtifactValidator {
  const ArtifactValidator();

  ValidationReport validate({
    required Directory runDir,
    required String expectedCommand,
    required RetryExpectation retryExpectation,
  }) {
    final List<String> errors = <String>[];

    final File summaryFile = File('${runDir.path}/summary.json');
    final File failedTagsFile = File('${runDir.path}/failed-tags.txt');
    final File logFile = File('${runDir.path}/migration-log.jsonl');

    if (!summaryFile.existsSync()) {
      errors.add('summary.json missing at ${summaryFile.path}');
    }
    if (!failedTagsFile.existsSync()) {
      errors.add('failed-tags.txt missing at ${failedTagsFile.path}');
    }
    if (!logFile.existsSync()) {
      errors.add('migration-log.jsonl missing at ${logFile.path}');
    }

    if (errors.isNotEmpty) {
      return ValidationReport(passed: false, errors: errors);
    }

    Map<String, dynamic> summary;
    try {
      summary =
          jsonDecode(summaryFile.readAsStringSync()) as Map<String, dynamic>;
    } catch (exc) {
      return ValidationReport(
        passed: false,
        errors: <String>['Failed to parse summary.json: $exc'],
      );
    }

    final dynamic schemaVersion = summary['schema_version'];
    if (schemaVersion != 2 && schemaVersion != '2') {
      errors.add('summary.json schema_version must be 2, got $schemaVersion');
    }

    final String command = (summary['command'] ?? '').toString();
    if (command != expectedCommand) {
      errors.add(
          'summary.json command must be "$expectedCommand", got "$command"');
    }

    final String retryCommand = (summary['retry_command'] ?? '').toString();
    final String retryShell = (summary['retry_command_shell'] ?? '').toString();

    switch (retryExpectation) {
      case RetryExpectation.empty:
        if (retryCommand.isNotEmpty) {
          errors.add('retry_command expected empty, got "$retryCommand"');
        }
        if (retryShell.isNotEmpty) {
          errors.add('retry_command_shell expected empty, got "$retryShell"');
        }
        break;
      case RetryExpectation.nonempty:
        if (retryCommand.isEmpty) {
          errors.add(
              'retry_command expected non-empty (partial failure required)');
        }
        if (retryCommand.isNotEmpty &&
            !retryCommand.startsWith('gfrm resume')) {
          errors.add(
              'retry_command must start with "gfrm resume", got "$retryCommand"');
        }
        if (retryCommand.isNotEmpty && !retryCommand.contains('--tags-file')) {
          errors.add(
              'retry_command must include --tags-file, got "$retryCommand"');
        }
        if (retryShell.isEmpty) {
          errors.add('retry_command_shell expected non-empty');
        }
        break;
      case RetryExpectation.any:
        break;
    }

    final Map<String, dynamic> paths =
        (summary['paths'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final String summaryFailedTags = (paths['failed_tags'] ?? '').toString();
    final String summaryLog = (paths['jsonl_log'] ?? '').toString();
    final String summaryWorkdir = (paths['workdir'] ?? '').toString();

    if (summaryFailedTags != failedTagsFile.path) {
      errors.add('summary.paths.failed_tags mismatch');
    }
    if (summaryLog != logFile.path) {
      errors.add('summary.paths.jsonl_log mismatch');
    }
    if (summaryWorkdir != runDir.path) {
      errors.add('summary.paths.workdir mismatch');
    }

    return ValidationReport(passed: errors.isEmpty, errors: errors);
  }
}
