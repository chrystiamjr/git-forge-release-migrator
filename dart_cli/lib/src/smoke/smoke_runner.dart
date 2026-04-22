import 'dart:io';

import '../config/types/smoke_command_options.dart';
import '../core/logging.dart';
import 'artifact_validator.dart';
import 'fixture_trigger.dart';
import 'smoke_delay.dart';
import 'smoke_phase_outcome.dart';
import 'smoke_result.dart';

export 'smoke_phase_outcome.dart';
export 'smoke_result.dart';
export 'smoke_delay.dart';

/// Callback invoked by the runner to execute the underlying migration.
///
/// Returns the run directory where `summary.json` landed. Injected so the
/// runner is testable without spinning up the real migration engine.
typedef MigrationCallback = Future<Directory> Function();

/// Orchestrates the end-to-end smoke flow:
///   setup → cooldown → migrate → validate → cooldown → teardown
///
/// Honors `--skip-setup` / `--skip-teardown` and the chosen mode. Does not
/// know about any forge — that responsibility lives in the concrete
/// `FixtureTrigger` implementations the caller supplies.
final class SmokeRunner {
  SmokeRunner({
    required this.options,
    required this.logger,
    required this.sourceTrigger,
    required this.migrate,
    required this.validator,
    SmokeDelay? delay,
  }) : _delay = delay ?? defaultSmokeDelay;

  final SmokeCommandOptions options;
  final ConsoleLogger logger;
  final FixtureTrigger sourceTrigger;
  final MigrationCallback migrate;
  final ArtifactValidator validator;
  final SmokeDelay _delay;

  Future<SmokeResult> run() async {
    final List<SmokePhaseOutcome> phases = <SmokePhaseOutcome>[];

    if (!options.skipSetup) {
      logger.info('Creating fixture on source (${sourceTrigger.provider}) ...');
      final FixtureRunResult setup = await sourceTrigger.createFakeReleases();
      phases.add(SmokePhaseOutcome(
        name: 'setup',
        succeeded: setup.isSuccess,
        detail: setup.detail,
      ));
      if (!setup.isSuccess) {
        logger.error('Fixture setup failed: ${setup.detail}');
        return SmokeResult(exitCode: 1, phases: phases);
      }
      await _cooldown('after setup');
    } else {
      logger.info('Skipping fixture setup (--skip-setup).');
    }

    logger.info('Running migration ...');
    final Directory runDir;
    try {
      runDir = await migrate();
    } catch (exc) {
      logger.error('Migration failed: $exc');
      phases.add(SmokePhaseOutcome(name: 'migrate', succeeded: false, detail: exc.toString()));
      return SmokeResult(exitCode: 1, phases: phases);
    }
    phases.add(SmokePhaseOutcome(name: 'migrate', succeeded: true));

    final RetryExpectation retryExpectation = _retryExpectationFor(options.mode);
    final ValidationReport report = validator.validate(
      runDir: runDir,
      expectedCommand: 'migrate',
      retryExpectation: retryExpectation,
    );
    phases.add(SmokePhaseOutcome(
      name: 'validate',
      succeeded: report.passed,
      detail: report.errors.join('; '),
    ));
    if (!report.passed) {
      for (final String error in report.errors) {
        logger.error(error);
      }
      return SmokeResult(exitCode: 1, phases: phases);
    }

    await _cooldown('after migration');

    if (!options.skipTeardown) {
      logger.info('Cleaning up source (${sourceTrigger.provider}) ...');
      final FixtureRunResult teardown = await sourceTrigger.cleanupTagsAndReleases();
      phases.add(SmokePhaseOutcome(
        name: 'teardown',
        succeeded: teardown.isSuccess,
        detail: teardown.detail,
      ));
      if (!teardown.isSuccess) {
        logger.error('Teardown failed: ${teardown.detail}');
        return SmokeResult(exitCode: 1, phases: phases);
      }
    } else {
      logger.info('Skipping fixture teardown (--skip-teardown).');
    }

    logger.info('Smoke completed successfully. Run dir: ${runDir.path}');
    return SmokeResult(exitCode: 0, phases: phases);
  }

  Future<void> _cooldown(String label) async {
    if (options.cooldownSeconds <= 0) {
      return;
    }
    logger.info('Cooldown ${options.cooldownSeconds}s ($label)');
    await _delay(Duration(seconds: options.cooldownSeconds));
  }

  RetryExpectation _retryExpectationFor(String mode) {
    return switch (mode) {
      smokeModeHappyPath => RetryExpectation.empty,
      smokeModeContractCheck => RetryExpectation.empty,
      smokeModePartialFailureResume => RetryExpectation.nonempty,
      _ => RetryExpectation.any,
    };
  }
}
