import 'dart:io';

import 'package:args/command_runner.dart';

import '../adoption/adoption_plan.dart';
import 'init_command.dart' show dvLocalPackagesDir;

/// `dartvel init` -- Dartvel inside a project that already exists.
///
/// It used to be an alias of `create`, which replaces the pubspec with the
/// scaffold template. Adoption makes the two words mean different things:
/// `create` makes a project, `init` adds the dependency and the `dartvel:`
/// key to one, and nothing else.
///
/// The plan is always printed first. It is applied after a yes at a terminal
/// or with `--yes`, never by default where nobody can answer.
class AdoptCommand extends Command<void> {
  AdoptCommand() {
    argParser
      ..addFlag(
        'dry-run',
        negatable: false,
        help: 'Print the compatibility report and the pubspec changes; write '
            'nothing.',
      )
      ..addFlag(
        'yes',
        abbr: 'y',
        negatable: false,
        help: 'Apply without asking. Required where there is no terminal to '
            'ask at.',
      );
  }

  @override
  final String name = 'init';

  @override
  final String description =
      'Add Dartvel to an existing project: the dependency and the dartvel: '
      'key, nothing else.';

  @override
  String get invocation => 'dartvel init [--dry-run] [--yes]';

  @override
  Future<void> run() async {
    final int code = await dvRunInit(
      Directory.current.path,
      dryRun: argResults!['dry-run'] as bool,
      assumeYes: argResults!['yes'] as bool,
      interactive: stdin.hasTerminal,
      confirm: () async {
        stdout.write('Apply these changes to pubspec.yaml? [y/N] ');
        final String answer = (stdin.readLineSync() ?? '').trim().toLowerCase();
        return answer == 'y' || answer == 'yes';
      },
      out: stdout.writeln,
      localPackagesDir: await dvLocalPackagesDir(),
    );
    if (code != 0) exitCode = code;
  }
}

/// The body of `dartvel init`, returning the exit code.
///
/// Exit codes: 0 applied, dry run, or nothing to do; 1 refused or blocked;
/// 2 not applied because nobody confirmed.
Future<int> dvRunInit(
  String root, {
  required bool dryRun,
  required bool assumeYes,
  required bool interactive,
  required Future<bool> Function() confirm,
  required void Function(String) out,
  String? localPackagesDir,
}) async {
  final DVAdoptionPlan plan =
      dvPlanAdoption(root, localPackagesDir: localPackagesDir);
  out(plan.render().trimRight());

  if (plan.refusal != null) return 1;
  if (plan.alreadyInitialized) return 0;
  if (plan.blocked) {
    out('');
    out('Not applied: the report above has blocking items.');
    return 1;
  }
  if (dryRun) {
    out('');
    out('This was a dry run; nothing was written.');
    return 0;
  }
  if (!assumeYes) {
    if (!interactive) {
      out('');
      out('Not applied: there is no terminal to confirm at. Re-run with '
          '--yes to apply this plan, or --dry-run to only see it.');
      return 2;
    }
    if (!await confirm()) {
      out('Not applied.');
      return 2;
    }
  }

  final DVAdoptionApplyResult result = dvApplyAdoption(plan);
  out('');
  out(result.message);
  return result.written ? 0 : 1;
}
