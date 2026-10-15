/// Fails when a tracked file names a path on a maintainer's own machine.
///
///     dart tool/ci/private_paths_check.dart
///
/// This repository is public. Agent working notes and review write-ups have
/// more than once carried the shape of somebody's host into it: a load-slot
/// wrapper in the home directory, a file of stored credentials under
/// `~/.config`, a brief or a worktree under `~/`. None of it helps a reader,
/// all of it describes a machine nobody else has, and some of it says where a
/// secret is kept.
///
/// So it is checked, by the shape of the path rather than by a list of names:
/// a list of the projects a maintainer works on would itself be the leak.
library;

import 'dart:io';

/// Paths that only exist on a maintainer's host.
final List<RegExp> _private = <RegExp>[
  RegExp(r'heavy\.sh'),
  RegExp(r'~/(AGENTS\.md|agent-context|briefs|wt/|\.config/|\.cache/|'
      r'browser-agent|dartvel-proposals)'),
  RegExp(r'/home/[a-z][a-z0-9_-]*/(briefs|wt|agent-context|\.config)/'),
];

/// Files that have to be able to spell what they forbid.
const Set<String> _exempt = <String>{
  'tool/ci/private_paths_check.dart',
  // Asserts that the architecture docs do not mention the slot wrapper.
  'packages/dartvel_cli/test/architecture_docs_test.dart',
};

void main(List<String> arguments) {
  final ProcessResult tracked =
      Process.runSync('git', <String>['ls-files'], runInShell: true);
  if (tracked.exitCode != 0) {
    stderr.writeln('git ls-files failed: ${tracked.stderr}');
    exitCode = 1;
    return;
  }
  final List<String> found = <String>[];
  for (final String path in (tracked.stdout as String).split('\n')) {
    if (path.isEmpty || _exempt.contains(path)) continue;
    final File file = File(path);
    if (!file.existsSync()) continue;
    final List<String> lines;
    try {
      lines = file.readAsLinesSync();
    } on FileSystemException {
      continue; // Binary.
    }
    for (int i = 0; i < lines.length; i++) {
      if (_private.any((RegExp p) => p.hasMatch(lines[i]))) {
        found.add('$path:${i + 1}: ${lines[i].trim()}');
      }
    }
  }
  if (found.isEmpty) {
    stdout.writeln('No private host paths in tracked files.');
    return;
  }
  stderr
    ..writeln('Tracked files name paths on a maintainer\'s own machine:')
    ..writeAll(found.map((String f) => '  $f\n'));
  exitCode = 1;
}
