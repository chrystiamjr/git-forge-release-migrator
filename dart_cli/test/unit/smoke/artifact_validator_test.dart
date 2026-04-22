import 'dart:convert';
import 'dart:io';

import 'package:gfrm_dart/src/smoke/artifact_validator.dart';
import 'package:test/test.dart';

Directory _tempDir() {
  return Directory.systemTemp.createTempSync('gfrm_smoke_validator_');
}

void _writeSummary(Directory runDir, Map<String, Object?> summary) {
  File('${runDir.path}/summary.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(summary));
  File('${runDir.path}/failed-tags.txt').writeAsStringSync('');
  File('${runDir.path}/migration-log.jsonl').writeAsStringSync('');
}

Map<String, Object?> _baseSummary(Directory runDir) {
  return <String, Object?>{
    'schema_version': 2,
    'command': 'migrate',
    'retry_command': '',
    'retry_command_shell': '',
    'paths': <String, String>{
      'failed_tags': '${runDir.path}/failed-tags.txt',
      'jsonl_log': '${runDir.path}/migration-log.jsonl',
      'workdir': runDir.path,
    },
  };
}

void main() {
  const ArtifactValidator validator = ArtifactValidator();

  group('ArtifactValidator', () {
    test('passes a clean migrate summary with empty retry expectation', () {
      final Directory runDir = _tempDir();
      _writeSummary(runDir, _baseSummary(runDir));

      final ValidationReport report = validator.validate(
        runDir: runDir,
        expectedCommand: 'migrate',
        retryExpectation: RetryExpectation.empty,
      );

      expect(report.passed, isTrue, reason: report.errors.join('; '));
      runDir.deleteSync(recursive: true);
    });

    test('fails when schema_version is not 2', () {
      final Directory runDir = _tempDir();
      final Map<String, Object?> summary = _baseSummary(runDir);
      summary['schema_version'] = 1;
      _writeSummary(runDir, summary);

      final ValidationReport report = validator.validate(
        runDir: runDir,
        expectedCommand: 'migrate',
        retryExpectation: RetryExpectation.empty,
      );

      expect(report.passed, isFalse);
      expect(report.errors.any((String e) => e.contains('schema_version')), isTrue);
      runDir.deleteSync(recursive: true);
    });

    test('fails when command does not match', () {
      final Directory runDir = _tempDir();
      _writeSummary(runDir, _baseSummary(runDir));

      final ValidationReport report = validator.validate(
        runDir: runDir,
        expectedCommand: 'resume',
        retryExpectation: RetryExpectation.any,
      );

      expect(report.passed, isFalse);
      expect(report.errors.any((String e) => e.contains('command')), isTrue);
      runDir.deleteSync(recursive: true);
    });

    test('fails when retry_command is non-empty and empty was expected', () {
      final Directory runDir = _tempDir();
      final Map<String, Object?> summary = _baseSummary(runDir);
      summary['retry_command'] = 'gfrm resume --tags-file x.txt';
      _writeSummary(runDir, summary);

      final ValidationReport report = validator.validate(
        runDir: runDir,
        expectedCommand: 'migrate',
        retryExpectation: RetryExpectation.empty,
      );

      expect(report.passed, isFalse);
      expect(report.errors.any((String e) => e.contains('retry_command expected empty')), isTrue);
      runDir.deleteSync(recursive: true);
    });

    test('passes when retry_command is present and nonempty was expected', () {
      final Directory runDir = _tempDir();
      final Map<String, Object?> summary = _baseSummary(runDir);
      summary['retry_command'] = 'gfrm resume --tags-file x.txt';
      summary['retry_command_shell'] = '/bin/bash';
      _writeSummary(runDir, summary);

      final ValidationReport report = validator.validate(
        runDir: runDir,
        expectedCommand: 'migrate',
        retryExpectation: RetryExpectation.nonempty,
      );

      expect(report.passed, isTrue, reason: report.errors.join('; '));
      runDir.deleteSync(recursive: true);
    });

    test('fails when nonempty retry_command does not start with gfrm resume', () {
      final Directory runDir = _tempDir();
      final Map<String, Object?> summary = _baseSummary(runDir);
      summary['retry_command'] = 'gfrm migrate --session x.json';
      summary['retry_command_shell'] = '/bin/bash';
      _writeSummary(runDir, summary);

      final ValidationReport report = validator.validate(
        runDir: runDir,
        expectedCommand: 'migrate',
        retryExpectation: RetryExpectation.nonempty,
      );

      expect(report.passed, isFalse);
      expect(report.errors.any((String e) => e.contains('must start with "gfrm resume"')), isTrue);
      runDir.deleteSync(recursive: true);
    });

    test('fails when summary.json is missing', () {
      final Directory runDir = _tempDir();
      File('${runDir.path}/failed-tags.txt').writeAsStringSync('');
      File('${runDir.path}/migration-log.jsonl').writeAsStringSync('');

      final ValidationReport report = validator.validate(
        runDir: runDir,
        expectedCommand: 'migrate',
        retryExpectation: RetryExpectation.any,
      );

      expect(report.passed, isFalse);
      expect(report.errors.any((String e) => e.contains('summary.json missing')), isTrue);
      runDir.deleteSync(recursive: true);
    });

    test('fails when paths do not match the run directory', () {
      final Directory runDir = _tempDir();
      final Map<String, Object?> summary = _baseSummary(runDir);
      (summary['paths']! as Map<String, String>)['workdir'] = '/tmp/somewhere-else';
      _writeSummary(runDir, summary);

      final ValidationReport report = validator.validate(
        runDir: runDir,
        expectedCommand: 'migrate',
        retryExpectation: RetryExpectation.empty,
      );

      expect(report.passed, isFalse);
      expect(report.errors.any((String e) => e.contains('workdir mismatch')), isTrue);
      runDir.deleteSync(recursive: true);
    });
  });
}
