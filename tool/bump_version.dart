// Moves every version and every sibling constraint together.
//
// A release here is not one number. Six pub packages carry a `version:`, each
// names its siblings with a hosted constraint, and two npm packages carry a
// version of their own with dartvel_cli pinning dartvel_dev exactly. Bumping
// the versions and leaving the constraints is the specific mistake
// tool/check_constraints.dart exists to catch: dartvel_dev 0.3.1 shipped
// depending on dartvel_core ^0.2.1, a caret that stops at the next minor, so
// everyone installing that set resolved 0.2.x for every sibling.
//
// Doing it by hand across eight files is how that happens. This does all of
// it, then check_constraints says whether it worked.
//
//   dart tool/bump_version.dart 0.4.0
//   dart tool/bump_version.dart 0.4.0 --set dartvel_shelf=0.5.0
//   dart tool/bump_version.dart 0.4.0 --dry-run
//
// `--set` because the versions are not all the same: dartvel_shelf and
// dartvel_generator have their own histories and their own numbers, and
// forcing them onto one line would be a fake bump for whichever had not
// changed.
//
// dart:io only, so it runs from a bare checkout the way the other release
// tools do.
library;

import 'dart:io';

/// The pub packages that are published, in no particular order -- the ordering
/// that matters is in tool/publish.sh, which has to publish a package before
/// anything that depends on it.
const List<String> _pubPackages = <String>[
  'dartvel_core',
  'dartvel_shelf',
  'dartvel_flutter',
  'dartvel_generator',
  'dartvel_cli',
  'dartvel_dev',
];

const List<String> _npmPackages = <String>['dartvel_cli', 'dartvel_dev'];

void main(List<String> args) {
  if (args.isEmpty || args.first.startsWith('-')) {
    stderr.writeln('usage: dart tool/bump_version.dart <version> '
        '[--set name=version]... [--dry-run]');
    exit(2);
  }

  final String base = args.first;
  bool dryRun = false;
  final Map<String, String> overrides = <String, String>{};

  for (int i = 1; i < args.length; i++) {
    final String arg = args[i];
    if (arg == '--dry-run') {
      dryRun = true;
      continue;
    }
    if (arg == '--set') {
      if (i + 1 >= args.length) {
        stderr.writeln('--set needs name=version');
        exit(2);
      }
      final List<String> parts = args[++i].split('=');
      if (parts.length != 2) {
        stderr.writeln('--set takes name=version, got "${args[i]}"');
        exit(2);
      }
      overrides[parts[0]] = parts[1];
      continue;
    }
    stderr.writeln('unknown argument: $arg');
    exit(2);
  }

  final Map<String, String> target = <String, String>{
    for (final String name in _pubPackages) name: overrides[name] ?? base,
  };

  for (final MapEntry<String, String> e in overrides.entries) {
    if (!_pubPackages.contains(e.key)) {
      stderr.writeln('--set names ${e.key}, which is not a published package');
      exit(2);
    }
  }

  final List<String> changed = <String>[];

  for (final String name in _pubPackages) {
    final File pubspec = File('packages/$name/pubspec.yaml');
    if (!pubspec.existsSync()) {
      stderr.writeln('missing ${pubspec.path}; run from the repository root');
      exit(2);
    }
    final String before = pubspec.readAsStringSync();
    String after = _setVersion(before, target[name]!);
    after = _setSiblingConstraints(after, target);
    if (after == before) continue;
    changed.add(pubspec.path);
    if (!dryRun) pubspec.writeAsStringSync(after);
  }

  for (final String name in _npmPackages) {
    final File manifest = File('npm/$name/package.json');
    if (!manifest.existsSync()) continue;
    final String before = manifest.readAsStringSync();
    String after = before.replaceFirst(
      RegExp(r'"version":\s*"[^"]*"'),
      '"version": "${target[name]!}"',
    );
    // dartvel_cli pins dartvel_dev exactly rather than with a range, because
    // the launcher and the binaries it fetches are one release.
    after = after.replaceFirst(
      RegExp(r'"dartvel_dev":\s*"[^"]*"'),
      '"dartvel_dev": "${target['dartvel_dev']!}"',
    );
    if (after == before) continue;
    changed.add(manifest.path);
    if (!dryRun) manifest.writeAsStringSync(after);
  }

  for (final MapEntry<String, String> e in target.entries) {
    stdout.writeln('${e.key.padRight(20)} -> ${e.value}');
  }
  stdout.writeln('\n${changed.length} file(s)'
      '${dryRun ? ' would change' : ' written'}:');
  for (final String path in changed) {
    stdout.writeln('  $path');
  }
  if (!dryRun) {
    stdout.writeln('\nnow run: dart tool/check_constraints.dart');
  }
}

/// The top-level `version:` line, and only that one.
///
/// Anchored to the start of a line so it cannot match the `version:` nested
/// under a dependency, which is how a sibling constraint written in the long
/// form gets rewritten into the package's own version.
String _setVersion(String pubspec, String version) => pubspec.replaceFirst(
      RegExp(r'^version:.*$', multiLine: true),
      'version: $version',
    );

/// Every hosted constraint naming a sibling, moved to that sibling's version.
///
/// Both spellings, because this repository uses both: the short
/// `dartvel_core: ^0.3.2` and the long form with a nested `version:` under the
/// package name. Missing the long one leaves exactly the stale caret the
/// constraint checker was written for.
String _setSiblingConstraints(String pubspec, Map<String, String> target) {
  String out = pubspec;
  for (final MapEntry<String, String> e in target.entries) {
    out = out.replaceAllMapped(
      RegExp('^(\\s+)${e.key}:\\s*\\^[0-9][^\\s]*[ \\t]*\$', multiLine: true),
      (Match m) => '${m.group(1)}${e.key}: ^${e.value}',
    );
    out = out.replaceAllMapped(
      RegExp('^(\\s+)${e.key}:\\s*\$\\n(\\s+)version:\\s*\\^[0-9][^\\s]*[ \\t]*\$',
          multiLine: true),
      (Match m) => '${m.group(1)}${e.key}:\n${m.group(2)}version: ^${e.value}',
    );
  }
  return out;
}
