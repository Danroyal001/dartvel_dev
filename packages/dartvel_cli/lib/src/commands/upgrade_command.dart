import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../upgrade/upgrade_apply.dart';
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
    argParser.addFlag(
      'apply',
      negatable: false,
      help:
          'Apply the project plan: raise the SDK constraint to the floor, move '
          'each Dartvel package to this release, rewrite deprecated names, '
          'then run pub upgrade and the generator. Refused, with nothing '
          'written, while anything in the plan is blocked. Does not upgrade '
          'the CLI.',
    );
  }

  @override
  final String name = 'upgrade';

  @override
  final String description =
      'Upgrade the CLI, or plan a project upgrade with --plan and apply it '
      'with --apply.';

  @override
  String get invocation => 'dartvel upgrade [--plan | --apply]';

  @override
  Future<void> run() async {
    final int code = await dvRunUpgrade(
      Directory.current.path,
      plan: argResults!['plan'] as bool,
      apply: argResults!['apply'] as bool,
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
  bool apply = false,
  Future<void> Function()? selfUpgrade,
  DVToolchainProbe? probe,
  DVGeneratedCheck? generatedCheck,
  DVPubUpgrade? pubUpgrade,
  Future<void> Function()? generate,
  Future<void> Function()? beforeWrite,
}) async {
  if (plan && apply) {
    out('--plan writes nothing and --apply writes the plan; use one.');
    return 1;
  }
  if (apply) {
    if (!File(p.join(root, 'pubspec.yaml')).existsSync()) {
      out('No pubspec.yaml here. Run upgrade --apply from the root of a '
          'project.');
      return 1;
    }
    // The project only. The CLI is upgraded by `dartvel upgrade` alone, so
    // one command never makes two changes nobody reviewed together.
    return dvApplyUpgrade(
      root,
      out: out,
      probe: probe,
      generatedCheck: generatedCheck,
      pubUpgrade: pubUpgrade,
      generate: generate,
      beforeWrite: beforeWrite,
    );
  }
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
