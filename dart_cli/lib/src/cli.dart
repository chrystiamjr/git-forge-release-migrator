import 'dart:io';

import 'application/run_paths.dart';
import 'application/run_request.dart';
import 'application/run_result.dart';
import 'application/run_service.dart';
import 'cli/runtime_support.dart';
import 'cli/settings_setup_command_handler.dart';
import 'config.dart';
import 'core/console_output.dart';
import 'core/input_reader.dart';
import 'core/logging.dart';
import 'core/std_console_output.dart';
import 'core/std_input_reader.dart';
import 'models/runtime_options.dart';

typedef RunServiceFactory = RunService Function(ConsoleLogger logger);

Future<int> _runCli(
  List<String> argv, {
  ConsoleOutput? output,
  InputReader? input,
  RunServiceFactory? runServiceFactory,
}) async {
  final ConsoleOutput resolvedOutput = output ?? const StdConsoleOutput();
  final InputReader resolvedInput = input ?? const StdInputReader();
  ConsoleLogger? logger;
  try {
    final CliRequest request = CliRequestParser.parseCliRequest(argv);
    if (request.command == 'help') {
      resolvedOutput.writeOutLine(request.usage);
      return 0;
    }

    if (request.command == commandSettings) {
      logger = ConsoleLogger(quiet: false, jsonOutput: false, output: resolvedOutput);
      return SettingsSetupCommandHandler(
        logger: logger,
        output: resolvedOutput,
        input: resolvedInput,
      ).runSettingsCommand(request.settings!);
    }

    if (request.command == commandSetup) {
      logger = ConsoleLogger(quiet: false, jsonOutput: false, output: resolvedOutput);
      return SettingsSetupCommandHandler(
        logger: logger,
        output: resolvedOutput,
        input: resolvedInput,
      ).runSetupCommand(request.setup!);
    }

    final RuntimeOptions initialOptions = request.options!;
    logger = ConsoleLogger(
      quiet: initialOptions.quiet,
      jsonOutput: initialOptions.jsonOutput,
      output: resolvedOutput,
    );
    if (!initialOptions.noBanner && !initialOptions.jsonOutput && !initialOptions.quiet) {
      CliRuntimeSupport.printBanner(resolvedOutput);
    }

    if (initialOptions.commandName == commandDemo) {
      final Directory resultsRoot = Directory(initialOptions.effectiveWorkdir());
      if (!resultsRoot.existsSync()) {
        resultsRoot.createSync(recursive: true);
      }
      final Directory runWorkdir = allocateRunWorkdir(resultsRoot);
      runWorkdir.createSync(recursive: true);
      final RuntimeOptions options = initialOptions.copyWith(
        workdir: runWorkdir.path,
        logFile: initialOptions.logFile.isEmpty ? '${runWorkdir.path}/migration-log.jsonl' : initialOptions.logFile,
      );
      return CliRuntimeSupport.runDemo(
        options,
        logger,
        resultsRoot: resultsRoot,
        runWorkdir: runWorkdir,
      );
    }

    final RunService runService = runServiceFactory != null ? runServiceFactory(logger) : RunService(logger: logger);
    final RunRequest runRequest = CliRuntimeSupport.buildRunRequest(initialOptions);
    final RunResult result = await runService.run(runRequest);
    return CliRuntimeSupport.renderRunResult(logger, result);
  } catch (exc) {
    try {
      logger?.stopSpinner();
    } catch (_) {}

    if (logger != null) {
      logger.error(exc.toString());
    } else {
      resolvedOutput.writeErrLine('[ERROR] $exc');
    }

    return 1;
  }
}

final class CliRunner {
  const CliRunner._();

  static Future<int> run(
    List<String> argv, {
    ConsoleOutput? output,
    InputReader? input,
    RunServiceFactory? runServiceFactory,
  }) async {
    return _runCli(
      argv,
      output: output,
      input: input,
      runServiceFactory: runServiceFactory,
    );
  }
}
