import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../build/spec_status.dart';
import '../utils/logger.dart';

/// `dartvel spec status` — what the specification index says is built.
///
/// The validation behind this has existed as `tool/spec_status_check.dart`
/// and runs in CI, but it was reachable only by knowing that script's path.
/// The spec lists `dartvel spec status` among the commands, and the thing
/// that decides whether the status index is honest should be easy to run.
class SpecCommand extends Command<void> {
  @override
  final String name = 'spec';

  @override
  final String description = 'Inspect the specification status index.';

  SpecCommand() {
    addSubcommand(_SpecStatusCommand());
  }
}

class _SpecStatusCommand extends Command<void> {
  @override
  final String name = 'status';

  @override
  final String description =
      'Summarise docs/spec-status.json: what is built and what is not.';

  @override
  String get invocation => 'dartvel spec status [--contracts]';

  _SpecStatusCommand() {
    argParser.addFlag('contracts',
        negatable: false,
        help: 'List the frozen surfaces that are not finished.');
  }

  @override
  void run() {
    final file = File(p.join(Directory.current.path, 'docs', 'spec-status.json'));
    if (!file.existsSync()) {
      log('No docs/spec-status.json here. Run this from the project root.');
      exit(1);
    }

    final Object? decoded = jsonDecode(file.readAsStringSync());
    final List<Object?> raw = decoded is Map<String, Object?>
        ? (decoded['sections'] as List<Object?>? ?? const <Object?>[])
        : (decoded as List<Object?>);
    final sections = <Map<String, Object?>>[
      for (final Object? entry in raw)
        if (entry is Map) entry.cast<String, Object?>(),
    ];

    final summary = specStatusSummary(sections);
    log('${summary.total} sections, ${summary.labelled} labelled.');
    log('  Shipped   ${summary.shipped}');
    log('  Partial   ${summary.partial}');
    log('  Designed  ${summary.designed}');

    if (summary.unbuiltContracts.isEmpty) {
      log('Every frozen surface is finished.');
      return;
    }

    // Said plainly rather than buried. A frozen contract that is deliberately
    // unbuilt is the scope rule working; a list of them is a decision to make
    // on purpose rather than a number to walk past.
    log('');
    log('${summary.unbuiltContracts.length} frozen surfaces are not finished:');
    if (argResults!['contracts'] == true) {
      for (final String section in summary.unbuiltContracts) {
        log('  - $section');
      }
    } else {
      log('  ${summary.unbuiltContracts.take(5).join(', ')}'
          '${summary.unbuiltContracts.length > 5 ? ', …' : ''}');
      log('  Run with --contracts for all of them.');
    }
  }
}
