import 'dart:io';

import 'package:args/command_runner.dart';

import 'src/commands/admin_command.dart';
import 'src/commands/ai_command.dart';
import 'src/commands/build_command.dart';
import 'src/commands/cache_command.dart';
import 'src/commands/db_command.dart';
import 'src/commands/deploy_command.dart';
import 'src/commands/dev_command.dart';
import 'src/commands/doctor_command.dart';
import 'src/commands/generate_command.dart';
import 'src/commands/init_command.dart';
import 'src/commands/observability_commands.dart';
import 'src/commands/plugin_command.dart';
import 'src/commands/prerender_command.dart';
import 'src/commands/preview_command.dart';
import 'src/commands/queue_command.dart';
import 'src/commands/routes_command.dart';
import 'src/commands/shell_command.dart';
import 'src/commands/test_command.dart';
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
    ..addCommand(DevCommand())
    // run and start are aliases in DevCommand
    ..addCommand(RoutesCommand())
    ..addCommand(BuildCommand())
    ..addCommand(DeployCommand())
    ..addCommand(PreviewCommand())
    ..addCommand(PrerenderCommand())
    ..addCommand(WatchCommand())
    ..addCommand(PluginCommand())
    ..addCommand(UpdatesCommand())
    ..addCommand(QueueCommand())
    ..addCommand(CacheCommand())
    ..addCommand(DbCommand())
    ..addCommand(GenerateCommand())
    ..addCommand(LogsCommand())
    ..addCommand(TracesCommand())
    ..addCommand(MetricsCommand())
    ..addCommand(AiCommand())
    ..addCommand(AdminCommand())
    ..addCommand(DevtoolsCommand())
    ..addCommand(ShCommand())
    ..addCommand(TaskCommand())
    ..addCommand(TestCommand())
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
