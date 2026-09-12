// Does every package accept the sibling versions being published with it?
//
// Standalone on purpose: only dart:io, no package imports, no pub resolution.
// This runs as a gate in tool/publish.sh, and a release check that cannot run
// because the pub cache is cold -- or damaged, which is how this was found --
// is a gate that gets skipped exactly when it matters.
//
// The bug it exists for: dartvel_dev 0.3.1 shipped depending on dartvel_core
// ^0.2.1. A caret on a 0.x version stops at the next minor, so it excluded the
// 0.3.1 published beside it, and anyone installing that set resolved 0.2.x for
// every sibling.
//
// `dart pub publish --dry-run` cannot see this: it resolves against
// pubspec_overrides.yaml, where every sibling points at a local path, so the
// hosted constraint is never exercised.
import 'dart:io';

void main(List<String> args) {
  final Directory packages = _findPackages();
  final Map<String, String> versions = <String, String>{};

  for (final FileSystemEntity entity in packages.listSync()) {
    if (entity is! Directory) continue;
    final File pubspec = File('${entity.path}/pubspec.yaml');
    if (!pubspec.existsSync()) continue;
    final String source = pubspec.readAsStringSync();
    final String? name = _field(source, 'name');
    final String? version = _field(source, 'version');
    if (name != null && version != null) versions[name] = version;
  }

  if (versions.length < 2) {
    stderr.writeln('check_constraints: found ${versions.length} package(s) in '
        '${packages.path}; expected the Dartvel workspace.');
    exit(2);
  }

  final List<String> problems = <String>[];

  for (final MapEntry<String, String> pkg in versions.entries) {
    final String source =
        File('${packages.path}/${pkg.key}/pubspec.yaml').readAsStringSync();

    for (final MapEntry<String, String> dep
        in _siblingConstraints(source).entries) {
      final String? actual = versions[dep.key];
      if (actual == null) continue;

      if (!_allows(dep.value, actual)) {
        problems.add(
          '${pkg.key} declares ${dep.key}: ${dep.value}, which does not admit '
          '${dep.key} $actual',
        );
      }
    }
  }

  // Two versions a bump has to reach that do not live in a pubspec, and both
  // shipped wrong in 0.4.0. Checked here because this runs as a gate inside
  // tool/publish.sh: the unit tests that cover them only help if somebody runs
  // the CLI suite before tagging, and for 0.4.0 nobody did.
  final String? cliDeclared = versions['dartvel_cli'];
  final String? cliReports = _constant(packages,
      'dartvel_cli/lib/src/commands/version_command.dart', 'dartvelCliVersion');
  if (cliDeclared != null && cliReports != cliDeclared) {
    problems.add('dartvel_cli declares $cliDeclared but reports '
        '$cliReports (dartvelCliVersion in version_command.dart). '
        '`dartvel --version` prints the constant and `dartvel update` compares '
        'it with the latest release, so a mismatched binary offers itself as '
        'an update for ever.');
  }
  // Every constraint the scaffold writes, read from the template's own text
  // rather than from a list of package names kept here. dartvel_shelf was a
  // bare '^0.3.0' literal beside three interpolated constraints, so a loop
  // over <core, flutter, cli> checked every constraint except the wrong one,
  // and `dartvel create` asked for a shelf three releases old.
  _scaffoldConstraints(packages).forEach((String package, String base) {
    final String? version = versions[package];
    if (version == null) return;
    if (!_caretAllows(base, version)) {
      problems.add('dartvel create writes $package: ^$base '
          '(project_templates.dart), which does not admit the $version being '
          'published. Every new project would resolve an older release.');
    }
  });

  // The applications checked into this repository. Each resolves from its own
  // overrides, so a stale constraint never shows up in a build here; it shows
  // up for the reader who copies the file, which is what the site and the
  // examples are for.
  _appConstraints(packages.parent).forEach((String where, String constraint) {
    final int split = where.lastIndexOf(' ');
    final String label = where.substring(0, split);
    final String package = where.substring(split + 1);
    final String? version = versions[package];
    if (version == null) return;
    if (!_allows(constraint, version)) {
      problems.add('$label declares $package: $constraint, which does not '
          'admit the $package $version in this repository. It is what a '
          'reader copying the file gets.');
    }
  });

  if (problems.isEmpty) {
    stdout.writeln('every package accepts the sibling versions being published');
    return;
  }
  for (final String problem in problems) {
    stdout.writeln(problem);
  }
  exit(1);
}

/// The workspace's packages/ directory, found by walking up.
Directory _findPackages() {
  Directory dir = Directory.current;
  for (int depth = 0; depth < 6; depth += 1) {
    final Directory candidate = Directory('${dir.path}/packages');
    if (Directory('${candidate.path}/dartvel_core').existsSync()) {
      return candidate;
    }
    final Directory parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  stderr.writeln('check_constraints: no packages/ directory above '
      '${Directory.current.path}');
  exit(2);
}

String? _field(String source, String key) {
  final RegExpMatch? match =
      RegExp('^$key:\\s*(\\S+)\\s*\$', multiLine: true).firstMatch(source);
  return match?.group(1);
}

/// Each Dartvel dependency and the constraint declared on it.
///
/// Handles both `dartvel_core: ^0.3.2` and the long form with a nested
/// `version:` under `hosted:`.
Map<String, String> _siblingConstraints(String source) {
  final int start = source.indexOf(RegExp(r'^dependencies:', multiLine: true));
  if (start < 0) return <String, String>{};

  // To the next top-level key, so dev_dependencies are not read as runtime
  // ones -- a dev-only constraint being stale does not ship to anybody.
  final int next = source.indexOf(RegExp(r'^\w', multiLine: true), start + 1);
  final String block =
      next < 0 ? source.substring(start) : source.substring(start, next);

  final Map<String, String> out = <String, String>{};

  for (final RegExpMatch m
      in RegExp(r'^  (dartvel_\w+):\s*(\S+)\s*$', multiLine: true)
          .allMatches(block)) {
    out[m.group(1)!] = m.group(2)!;
  }

  for (final RegExpMatch m in RegExp(
    r'^  (dartvel_\w+):\s*$((?:\n^ {4}.*$)*)',
    multiLine: true,
  ).allMatches(block)) {
    final RegExpMatch? version =
        RegExp(r'^\s+version:\s*(\S+)\s*$', multiLine: true)
            .firstMatch(m.group(2) ?? '');
    if (version != null) out[m.group(1)!] = version.group(1)!;
  }

  return out;
}

/// Whether [constraint] admits [version].
///
/// Only the forms Dartvel uses: a caret, or a bare version. The caret rule is
/// the whole point -- for a 0.x version it stops at the next *minor*, not the
/// next major, so ^0.2.1 excludes 0.3.1. That is the difference this check
/// exists to catch, and getting it wrong here would make the gate agree with
/// the bug.
bool _allows(String constraint, String version) {
  final List<int>? actual = _parse(version);
  if (actual == null) return true;

  if (constraint.startsWith('^')) {
    final List<int>? min = _parse(constraint.substring(1));
    if (min == null) return true;

    if (_compare(actual, min) < 0) return false;

    final List<int> upper = min[0] > 0
        ? <int>[min[0] + 1, 0, 0]
        : <int>[0, min[1] + 1, 0];
    return _compare(actual, upper) < 0;
  }

  // A bare version is an exact pin.
  final List<int>? pinned = _parse(constraint);
  if (pinned == null) return true;
  return _compare(actual, pinned) == 0;
}

List<int>? _parse(String value) {
  final RegExpMatch? m =
      RegExp(r'^(\d+)\.(\d+)\.(\d+)').firstMatch(value.trim());
  if (m == null) return null;
  return <int>[
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
  ];
}

int _compare(List<int> a, List<int> b) {
  for (int i = 0; i < 3; i += 1) {
    if (a[i] != b[i]) return a[i].compareTo(b[i]);
  }
  return 0;
}

/// The value of `const String [name] = '...';` in a source file under
/// [packages], or null when the declaration is not there -- in which case the
/// check above is skipped rather than reporting a mismatch against nothing.
String? _constant(Directory packages, String path, String name) {
  final File file = File('${packages.path}/$path');
  if (!file.existsSync()) return null;
  final RegExpMatch? m = RegExp("const String $name = '([^']+)';")
      .firstMatch(file.readAsStringSync());
  return m?.group(1);
}

/// Each Dartvel constraint `dartvel create` writes, by package, caret
/// stripped, resolved through the constant when the template interpolates one.
///
/// Reads the template's source text, so a constraint added as a literal is
/// covered the day it is added rather than when somebody remembers to name it
/// here.
Map<String, String> _scaffoldConstraints(Directory packages) {
  const String path =
      'dartvel_cli/lib/src/templates/project_templates.dart';
  final File template = File('${packages.path}/$path');
  if (!template.existsSync()) return <String, String>{};
  final String source = template.readAsStringSync();

  final Map<String, String> out = <String, String>{};
  for (final RegExpMatch m in RegExp(
    r"^\s+(dartvel_\w+):.*\?\s*'\^\$?(\w[\w.]*)'",
    multiLine: true,
  ).allMatches(source)) {
    final String value = m.group(2)!;
    // Either a version, or the name of the constant holding one.
    final String? resolved = RegExp(r'^\d').hasMatch(value)
        ? value
        : _constant(packages, path, value);
    if (resolved != null) out[m.group(1)!] = resolved;
  }
  return out;
}

/// Each Dartvel constraint declared by an application in this repository,
/// keyed by '<path> <package>'.
///
/// Runtime and dev dependencies alike: in a published package a stale dev
/// constraint ships to nobody, but in an application it ships to everybody who
/// copies the file, and `dartvel_cli` -- a dev dependency -- is the build tool.
Map<String, String> _appConstraints(Directory root) {
  final Map<String, String> out = <String, String>{};

  for (final String dir in <String>['sites', 'examples']) {
    final Directory base = Directory('${root.path}/$dir');
    if (!base.existsSync()) continue;

    for (final FileSystemEntity entity in base.listSync(recursive: true)) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('/pubspec.yaml')) continue;
      if (entity.path.contains('/build/')) continue;
      if (entity.path.contains('/.dart_tool/')) continue;

      final String label = entity.path.substring(root.path.length + 1);
      final String source = entity.readAsStringSync();

      // A path dependency has no version to be stale about, and the regex
      // below does not match one.
      for (final RegExpMatch m
          in RegExp(r'^  (dartvel_\w+):\s*(\S+)\s*$', multiLine: true)
              .allMatches(source)) {
        out['$label ${m.group(1)}'] = m.group(2)!;
      }
    }
  }
  return out;
}

/// Whether `^base` admits [version]. The caret stops at the first non-zero
/// component: ^0.m.p is below 0.(m+1).0, ^M.m.p is below (M+1).0.0.
bool _caretAllows(String base, String version) {
  List<int> parts(String v) =>
      v.split('+').first.split('-').first.split('.').map(int.parse).toList();
  bool below(List<int> a, List<int> b) {
    for (int i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] < b[i];
    }
    return false;
  }

  final List<int> b = parts(base);
  final List<int> v = parts(version);
  if (below(v, b)) return false;
  final List<int> upper = b[0] > 0
      ? <int>[b[0] + 1, 0, 0]
      : b[1] > 0
          ? <int>[0, b[1] + 1, 0]
          : <int>[0, 0, b[2] + 1];
  return below(v, upper);
}
