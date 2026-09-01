// Every path a pubspec declares must exist in the repository.
//
//   dart run tool/pubspec_paths_check.dart
//
// Flutter refuses to build when `flutter: assets:` names a directory that is
// not there -- "unable to find directory entry in pubspec.yaml" -- and the way
// that happens is not a typo. It is an empty directory: it exists on the
// machine where the entry was written, git does not track empty directories,
// and it is simply absent from a fresh checkout. So the build works for
// everyone who has ever run it locally and fails for CI and for every new
// clone.
//
// That is exactly what happened to sites/dartvel_site, and it went unnoticed
// through two and a half hours of red runtime verification, because one target
// failing among twenty reads as that target being flaky.
//
// Exits non-zero and prints every problem rather than the first.
import 'dart:io';

int main(List<String> arguments) {
  final Directory root = _repoRoot();
  final List<String> problems = <String>[];
  var checked = 0;

  for (final File pubspec in _pubspecs(root)) {
    final String rel = _relative(pubspec.path, root.path);
    // Generated and vendored trees are not ours to fix.
    if (rel.contains('/build/') ||
        rel.contains('/.dart_tool/') ||
        rel.contains('/toolchains/')) {
      continue;
    }
    checked += 1;

    final Directory dir = pubspec.parent;
    for (final _Declared declared in _declaredPaths(pubspec)) {
      final String path = '${dir.path}/${declared.path}';
      final bool exists = declared.path.endsWith('/')
          ? Directory(path).existsSync()
          : File(path).existsSync() || Directory(path).existsSync();
      if (!exists) {
        problems.add('$rel:${declared.line} declares "${declared.path}", '
            'which does not exist.');
        continue;
      }

      // An asset directory that exists but is empty is the same failure one
      // commit later: nothing in it means git has nothing to track, so it
      // disappears from the next clone.
      if (declared.path.endsWith('/') &&
          Directory(path).listSync().isEmpty) {
        problems.add('$rel:${declared.line} declares "${declared.path}", '
            'which is empty. Git does not track empty directories, so it will '
            'not exist in a fresh checkout. Put a file in it or drop the '
            'entry.');
      }
    }
  }

  if (problems.isNotEmpty) {
    stderr.writeln('pubspec paths: ${problems.length} problem(s)');
    for (final String problem in problems) {
      stderr.writeln('  $problem');
    }
    return 1;
  }

  stdout.writeln('pubspec paths: $checked pubspecs, every declared path exists.');
  return 0;
}

/// One `assets:`/`- asset:` entry and where it was written.
class _Declared {
  const _Declared(this.path, this.line);
  final String path;
  final int line;
}

/// Reads the asset and font paths a pubspec declares.
///
/// Deliberately a line scan rather than a YAML parse: this runs with no
/// package resolution, as the first thing CI does, so it must not need a
/// dependency to tell you the build is broken.
List<_Declared> _declaredPaths(File pubspec) {
  final List<String> lines = pubspec.readAsLinesSync();
  final List<_Declared> found = <_Declared>[];
  var inAssets = false;

  for (var i = 0; i < lines.length; i++) {
    final String line = lines[i];
    final String trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

    if (trimmed == 'assets:') {
      inAssets = true;
      continue;
    }

    // A font asset carries its own key wherever it appears.
    final RegExpMatch? font =
        RegExp(r'^-\s*asset:\s*(\S+)\s*$').firstMatch(trimmed);
    if (font != null) {
      found.add(_Declared(font.group(1)!, i + 1));
      continue;
    }

    if (!inAssets) continue;
    final RegExpMatch? asset = RegExp(r'^-\s*(\S+)\s*$').firstMatch(trimmed);
    if (asset != null) {
      found.add(_Declared(asset.group(1)!, i + 1));
      continue;
    }
    // Any other key ends the assets list.
    inAssets = false;
  }
  return found;
}

List<File> _pubspecs(Directory root) => <File>[
      for (final FileSystemEntity entity in root.listSync(recursive: true))
        if (entity is File && entity.path.endsWith('/pubspec.yaml')) entity,
    ];

String _relative(String path, String from) =>
    path.startsWith(from) ? path.substring(from.length + 1) : path;

/// The repository root, found by walking up to the directory holding
/// NEW_SPEC.md.
Directory _repoRoot() {
  Directory dir = Directory.current;
  while (true) {
    if (File('${dir.path}/NEW_SPEC.md').existsSync()) return dir;
    final Directory parent = dir.parent;
    if (parent.path == dir.path) return Directory.current;
    dir = parent;
  }
}
