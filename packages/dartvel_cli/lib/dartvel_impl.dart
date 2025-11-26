import 'dart:io';
import 'package:args/command_runner.dart';

import 'src/commands/build_command.dart';
import 'src/commands/dev_command.dart';
import 'src/commands/doctor_command.dart';
import 'src/commands/init_command.dart';
import 'src/commands/new_command.dart';
import 'src/commands/plugin_command.dart';
import 'src/commands/preview_command.dart';
import 'src/commands/routes_command.dart';
import 'src/commands/updates_command.dart';
import 'src/commands/version_command.dart';
import 'src/commands/watch_command.dart';

Future<void> main(List<String> args) async {
  // Handle --version flag
  if (args.contains('--version')) {
    await VersionCommand().run();
    return;
  }

  final runner = CommandRunner<void>('dartvel', 'The Dartvel CLI tool.')
    ..addCommand(InitCommand())
    ..addCommand(DoctorCommand())
    ..addCommand(NewCommand())
    ..addCommand(DevCommand())
    ..addCommand(RoutesCommand())
    ..addCommand(BuildCommand())
    ..addCommand(PreviewCommand())
    ..addCommand(WatchCommand())
    ..addCommand(PluginCommand())
    ..addCommand(UpdatesCommand())
    ..addCommand(VersionCommand());

  try {
    await runner.run(args);
  } catch (e) {
    if (e is UsageException) {
      stderr.writeln(e.message);
      stderr.writeln(e.usage);
      exit(64);
    } else {
      stderr.writeln('An error occurred: $e');
      exit(1);
    }
  }
}
