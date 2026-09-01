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
