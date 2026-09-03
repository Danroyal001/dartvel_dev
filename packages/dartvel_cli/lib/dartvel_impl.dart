import 'dart:io';

import 'package:args/command_runner.dart';

import 'src/commands/update_command.dart';
import 'src/commands/mcp_command.dart';
import 'src/commands/modules_command.dart';
import 'src/commands/analyze_command.dart';
import 'src/commands/inspect_command.dart';
import 'src/commands/admin_command.dart';
import 'src/commands/ai_command.dart';
import 'src/commands/artifact_command.dart';
import 'src/commands/capture_command.dart';
import 'src/commands/webos_command.dart';
import 'src/commands/explain_command.dart';
import 'src/commands/spec_command.dart';
import 'src/commands/engine_command.dart';
import 'src/commands/ensure_path_command.dart';
import 'src/commands/build_command.dart';
import 'src/commands/cache_command.dart';
import 'src/commands/db_command.dart';
import 'src/commands/deploy_command.dart';
import 'src/commands/dev_command.dart';
import 'src/commands/doctor_command.dart';
import 'src/commands/generate_command.dart';
import 'src/commands/i18n_command.dart';
import 'src/commands/init_command.dart';
import 'src/commands/observability_commands.dart';
import 'src/commands/plugin_command.dart';
import 'src/commands/prerender_command.dart';
import 'src/commands/preview_command.dart';
import 'src/commands/queue_command.dart';
import 'src/commands/routes_command.dart';
import 'src/commands/shell_command.dart';
import 'src/commands/key_command.dart';
import 'src/commands/test_command.dart';
import 'src/commands/updates_command.dart';
import 'src/commands/version_command.dart';

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
    ..addCommand(InspectCommand())
    ..addCommand(AnalyzeCommand())
    ..addCommand(McpCommand())
    ..addCommand(BuildCommand())
    ..addCommand(ArtifactCommand())
    ..addCommand(CaptureCommand())
    ..addCommand(WebosCommand())
    ..addCommand(SpecCommand())
    ..addCommand(ExplainCommand())
    ..addCommand(EngineCommand())
    ..addCommand(EnsurePathCommand())
    ..addCommand(DeployCommand())
    ..addCommand(PreviewCommand())
    ..addCommand(PrerenderCommand())
    ..addCommand(PluginCommand())
    ..addCommand(ModulesCommand())
    ..addCommand(UpdatesCommand())
    ..addCommand(QueueCommand())
    ..addCommand(CacheCommand())
    ..addCommand(KeyCommand())
    ..addCommand(DbCommand())
    ..addCommand(GenerateCommand())
    ..addCommand(I18nCommand())
    ..addCommand(LogsCommand())
    ..addCommand(TracesCommand())
    ..addCommand(MetricsCommand())
    ..addCommand(AiCommand())
    ..addCommand(AdminCommand())
    ..addCommand(DevtoolsCommand())
    ..addCommand(ShCommand())
    ..addCommand(TaskCommand())
    ..addCommand(TestCommand())
    ..addCommand(UpdateCommand())
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
