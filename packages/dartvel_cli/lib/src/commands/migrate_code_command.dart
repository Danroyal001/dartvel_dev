import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../upgrade/code_migrations.dart';

/// `dartvel migrate-code` -- rewrite deprecated Dartvel names to the names
/// that replace them.
///
/// A dry run unless `--apply` is given, the way `dart fix` is: the rewrites
/// are printed line by line first, because a codemod that edits a project the
/// first time it is run is one a team runs once.
class MigrateCodeCommand extends Command<void> {
  MigrateCodeCommand() {
    argParser.addFlag(
      'apply',
      negatable: false,
      help: 'Write the rewrites. Without it nothing is written.',
    );
  }

  @override
  final String name = 'migrate-code';

  @override
  final String description =
      'Rewrite deprecated Dartvel names in this project to their replacements '
      '(a dry run unless --apply).';

  @override
  String get invocation => 'dartvel migrate-code [--apply]';

  @override
  Future<void> run() async {
    final int code = await dvRunMigrateCode(
      Directory.current.path,
      apply: argResults!['apply'] as bool,
      out: stdout.writeln,
    );
    if (code != 0) exitCode = code;
  }
}

/// The body of `dartvel migrate-code`, returning the exit code: 0 for a dry
/// run, an apply, or nothing to do; 1 when refused.
Future<int> dvRunMigrateCode(
  String root, {
  required bool apply,
  required void Function(String) out,
}) async {
  if (!File(p.join(root, 'pubspec.yaml')).existsSync()) {
    out('No pubspec.yaml here. Run migrate-code from the root of a project.');
    return 1;
  }
  final DVCodeMigrationPlan plan = dvPlanCodeMigration(root);
  if (plan.isEmpty) {
    out(
      'Nothing to migrate: no deprecated Dartvel name is used in this '
      'project (${dvCodeMigrationRules.length} rules checked).',
    );
    return 0;
  }
  out(plan.render().trimRight());
  out('');
  final String counts =
      (plan.countsByRule.entries.toList()..sort(
            (MapEntry<String, int> a, MapEntry<String, int> b) =>
                a.key.compareTo(b.key),
          ))
          .map((MapEntry<String, int> e) => '${e.key} ${e.value}')
          .join(', ');
  out('${plan.rewriteCount} rewrites in ${plan.files.length} files ($counts).');
  if (!apply) {
    out(
      'Dry run: nothing was written. Run `dartvel migrate-code --apply` to '
      'write these.',
    );
    return 0;
  }
  final DVCodeMigrationApplyResult result = dvApplyCodeMigration(plan);
  if (!result.applied) {
    out(result.message!);
    return 1;
  }
  out(
    'Written. Run `dartvel routes` to regenerate the client, which '
    'migrate-code does not edit.',
  );
  return 0;
}
