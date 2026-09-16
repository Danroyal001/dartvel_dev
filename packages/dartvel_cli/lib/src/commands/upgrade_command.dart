import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../upgrade/upgrade_plan.dart';

/// `dartvel upgrade --plan` -- what moving this project to the running CLI's
/// Dartvel release would change, changing nothing.
///
/// Not `dartvel update`, which replaces the CLI itself, and not
/// `dartvel updates`, which ships patches to a released application.
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
      'Plan upgrading this project to this CLI\'s Dartvel release.';

  @override
  String get invocation => 'dartvel upgrade --plan';

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
  DVToolchainProbe? probe,
  DVGeneratedCheck? generatedCheck,
}) async {
  if (!plan) {
    out(
      'Only `dartvel upgrade --plan` is built. Applying an upgrade is not: '
      'run the plan, change what it lists, and use '
      '`dartvel migrate-code --apply` for the source rewrites.',
    );
    return 1;
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
