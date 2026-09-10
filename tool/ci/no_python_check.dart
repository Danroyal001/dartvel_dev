/// Fails when Python appears in this repository.
///
///     dart run tool/ci/no_python_check.dart
///
/// Dartvel is a Dart monorepo and everything in it, tooling included, is
/// Dart. This has drifted back more than once — a workflow reaches for a
/// `python3` heredoc because the script is six lines, and the language
/// breakdown of a project sold as "Flutter's Laravel" then says Python.
///
/// So it is checked. Tracked `.py` files fail, and so does an inline
/// `python3` anywhere a command can run — a workflow, a shell script, or a
/// Dart file. Workflows alone was too narrow: a test in
/// `packages/dartvel_flutter` stood a systemd notification socket up by
/// spawning `python3 -c`, and it sat there passing because nothing looked at
/// Dart sources. Prose is left alone, so this file and the rule files can
/// name the thing they forbid.
///
/// The one exception is named here rather than left to judgement: the Flutter
/// engine's build runs Chromium's own `install-sysroot.py`, which is
/// upstream's and not ours to rewrite.
library;

import 'dart:io';

/// Where a command can live. Markdown and the rule files are prose about the
/// rule and are not scanned.
const Set<String> _executableSuffixes = <String>{
  '.dart',
  '.sh',
  '.yml',
  '.yaml',
};

/// This file, which has to be able to spell what it forbids.
const String _self = 'tool/ci/no_python_check.dart';

/// Whether [line] is a comment in any of the scanned languages.
bool _isComment(String line) {
  final String trimmed = line.trimLeft();
  return trimmed.startsWith('#') ||
      trimmed.startsWith('//') ||
      trimmed.startsWith('*');
}

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
    if (path == _self) continue;
    if (_allowed.containsKey(path)) continue;
    if (!_executableSuffixes.any(path.endsWith)) continue;
    final File file = File(path);
    if (!file.existsSync()) continue;
    final List<String> lines = file.readAsLinesSync();
    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i];
      // A comment is prose, and the rule itself has to be able to name the
      // thing it forbids. A command never lives in one.
      if (_isComment(line)) continue;
      if (!line.contains('python3')) continue;
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
