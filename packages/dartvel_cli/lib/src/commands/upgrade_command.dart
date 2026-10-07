import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../upgrade/upgrade_plan.dart';
import 'update_command.dart';

/// Upgrade the CLI transactionally; --plan keeps project planning read-only.
class UpgradeCommand extends Command<void> {
  UpgradeCommand() {
    argParser.addFlag(
      'plan',
      negatable: false,
      help:
          'Report what the upgrade changes across the toolchain, '
          'dependencies, source, generated code, protocol, database, modules, '
          'plugins and deployment. Writes nothing.',
    );
  }

  @override
  final String name = 'upgrade';

  @override
  final String description =
      'Upgrade the CLI, or plan a project upgrade with --plan.';

  @override
  String get invocation => 'dartvel upgrade [--plan]';

  @override
  Future<void> run() async {
    final int code = await dvRunUpgrade(
      Directory.current.path,
      plan: argResults!['plan'] as bool,
      out: stdout.writeln,
    );
    if (code != 0) exitCode = code;
  }
}

/// The body of `dartvel upgrade`: 0 when the plan has nothing blocked, 1 when
/// it does or when it was refused.
Future<int> dvRunUpgrade(
  String root, {
  required bool plan,
  required void Function(String) out,
  Future<void> Function()? selfUpgrade,
  DVToolchainProbe? probe,
  DVGeneratedCheck? generatedCheck,
}) async {
  if (!plan) {
    if (selfUpgrade != null) {
      await selfUpgrade();
    } else {
      final runner = CommandRunner<void>('dartvel', 'Dartvel CLI')
        ..addCommand(UpdateCommand());
      await runner.run(['update']);
    }
    return 0;
  }
  if (!File(p.join(root, 'pubspec.yaml')).existsSync()) {
    out('No pubspec.yaml here. Run upgrade --plan from the root of a project.');
    return 1;
  }
  final DVUpgradePlan result = await dvPlanUpgrade(
    root,
    probe: probe,
    generatedCheck: generatedCheck,
  );
  out(result.render().trimRight());
  return result.blocked ? 1 : 0;
}
