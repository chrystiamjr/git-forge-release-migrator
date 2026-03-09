import '../../core/settings.dart';
import '../../models/runtime_options.dart';
import 'setup_command_options.dart';

class CliRequest {
  CliRequest({
    required this.command,
    this.options,
    this.settings,
    this.setup,
    this.usage = '',
  });

  final String command;
  final RuntimeOptions? options;
  final SettingsCommandOptions? settings;
  final SetupCommandOptions? setup;
  final String usage;
}
