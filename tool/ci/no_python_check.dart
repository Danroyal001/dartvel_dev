/// Fails when Python appears in this repository.
///
///     dart run tool/ci/no_python_check.dart
///
/// Dartvel is a Dart monorepo and everything in it, tooling included, is
/// Dart. This has drifted back more than once — a workflow reaches for a
/// `python3` heredoc because the script is six lines, and the language
/// breakdown of a project sold as "Flutter's Laravel" then says Python.
///
/// So it is checked. Tracked `.py` files and inline `python3` in a workflow
/// both fail, and the one exception is named here rather than left to
/// judgement: the Flutter engine's build runs Chromium's own
/// `install-sysroot.py`, which is upstream's and not ours to rewrite.
library;

import 'dart:io';

/// Where a third-party build system runs its own scripts.
const Map<String, String> _allowed = <String, String>{
  '.github/workflows/engine-build.yml':
      "the Flutter engine's build system is Chromium's, and it runs its own "
          'install-sysroot.py',
};

void main(List<String> arguments) {
  final ProcessResult tracked =
      Process.runSync('git', <String>['ls-files'], runInShell: true);
  if (tracked.exitCode != 0) {
    stderr.writeln('git ls-files failed: ${tracked.stderr}');
    exitCode = 1;
    return;
  }

  final List<String> problems = <String>[];
  final List<String> files = '${tracked.stdout}'
      .split('\n')
      .map((String line) => line.trim())
      .where((String line) => line.isNotEmpty)
      .toList();

  for (final String path in files) {
    if (path.endsWith('.py')) {
      problems.add('$path is Python. Write it in Dart under tool/ci/.');
      continue;
    }
    if (!path.startsWith('.github/workflows/')) continue;
    if (_allowed.containsKey(path)) continue;
    final File file = File(path);
    if (!file.existsSync()) continue;
    final List<String> lines = file.readAsLinesSync();
    for (int i = 0; i < lines.length; i++) {
      if (!lines[i].contains('python3')) continue;
      problems.add('$path:${i + 1} runs python3. Write a Dart program under '
          'tool/ci/ and call it with `dart tool/ci/<name>.dart`.');
    }
  }

  if (problems.isNotEmpty) {
    stdout.writeln('this repository is Dart, and these are not:');
    for (final String problem in problems) {
      stdout.writeln('  $problem');
    }
    exitCode = 1;
    return;
  }

  final String exceptions = _allowed.keys.join(', ');
  stdout.writeln('no python: ${files.length} tracked files, '
      'the only exception being $exceptions.');
}
