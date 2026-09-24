/// Fails when a workflow step writes `set -uo pipefail`.
///
///     dart tool/ci/workflow_errexit_check.dart
///
/// GitHub runs every `run:` step as `shell: /usr/bin/bash -e {0}`, so
/// errexit is already on before the script's first line. `set -uo pipefail`
/// reads as "nounset and pipefail, and deliberately not errexit" and does
/// nothing of the kind: it adds two options and leaves -e exactly where it
/// was.
///
/// That is not pedantry. The Linux GUI capture died on this for three runs.
/// It assigned
///
///     WID=$(xwininfo -root -tree | grep -m1 '"Oakline Coffee":' | awk ...)
///
/// inside a twenty-attempt loop. When the window had not mapped yet the grep
/// matched nothing, pipefail failed the pipeline, and the -e nobody thought
/// was on killed the shell at that line -- before the echo that would have
/// said so. The job reported a failed capture with an empty log, three times,
/// and the application was fine.
///
/// So a step says which it means. `set -euo pipefail` is the common case and
/// is honest about the -e that is there anyway. A step that really wants to
/// run past a failure turns it off with `set +e`, which anybody reading can
/// see. Either is allowed here; the one that quietly misleads is not.
library;

import 'dart:io';

void main(List<String> arguments) {
  final Directory workflows = Directory('.github/workflows');
  if (!workflows.existsSync()) {
    stderr.writeln('workflow errexit: .github/workflows not found');
    exitCode = 1;
    return;
  }

  final List<String> problems = <String>[];
  int steps = 0;

  final List<File> files = workflows
      .listSync()
      .whereType<File>()
      .where((File f) => f.path.endsWith('.yml') || f.path.endsWith('.yaml'))
      .toList()
    ..sort((File a, File b) => a.path.compareTo(b.path));

  for (final File file in files) {
    final List<String> lines = file.readAsLinesSync();
    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i];
      // Prose about the rule is not the rule. The comment in
      // runtime-verification.yml that explains this check names the very
      // string it forbids.
      if (line.trimLeft().startsWith('#')) continue;
      if (!line.contains('set -')) continue;
      steps++;
      // Any ordering of u, o pipefail and friends that leaves out e.
      final RegExpMatch? match =
          RegExp(r'\bset\s+(-[a-z]+)(\s+-o\s+pipefail)?\b').firstMatch(line);
      if (match == null) continue;
      final String flags = match.group(1)!;
      if (flags.contains('e')) continue;
      problems.add(
        '${file.path}:${i + 1}  ${line.trim()}\n'
        '    GitHub already runs this step with bash -e. Write '
        '"set -euo pipefail" if that is what you want, or "set +e" if it '
        'is not.',
      );
    }
  }

  if (problems.isNotEmpty) {
    stderr.writeln('workflow errexit: ${problems.length} step(s) mislead:');
    for (final String problem in problems) {
      stderr.writeln('  - $problem');
    }
    // Returning a value from main does not set the exit code in Dart, so a
    // check that only printed its findings would have reported them into a
    // green job -- which is the shape of bug this file exists to catch.
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'workflow errexit: ${files.length} workflow(s), $steps shell option '
    'line(s), every one honest about the -e GitHub supplies.',
  );
}
