// The frontend entrypoint cannot reach the backend.
//
// `dartvel_core` depends on this package for its request and response types,
// so every Dartvel application pulls it whether or not it ever serves. Keeping
// the server behind its own entrypoint means an application that imports the
// shared types cannot reach `serve()` at all -- the boundary is enforced by
// what resolves, rather than by a convention someone has to remember.
//
// This walks the actual import graph rather than checking a list of names: a
// new file added under src/ that pulls dart:ffi into the shared half is
// exactly the regression worth catching, and nobody would think to update a
// list for it.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final Directory libDir = Directory('lib');

/// Every file reachable from [entrypoint] by following relative imports and
/// exports within this package.
Set<String> closureOf(String entrypoint) {
  // An entrypoint that does not exist yields an empty closure, and every
  // "contains no ffi" assertion over it passes for the wrong reason.
  if (!File(entrypoint).existsSync()) {
    throw StateError('$entrypoint does not exist; the closure would be empty '
        'and every assertion over it vacuous.');
  }
  final Set<String> seen = <String>{};
  final List<String> queue = <String>[p.normalize(entrypoint)];

  while (queue.isNotEmpty) {
    final String current = queue.removeLast();
    if (!seen.add(current)) continue;

    final File file = File(current);
    if (!file.existsSync()) continue;

    for (final RegExpMatch match in RegExp(
      r"""^\s*(?:import|export)\s+'([^']+)'""",
      multiLine: true,
    ).allMatches(file.readAsStringSync())) {
      final String target = match.group(1)!;
      // Only this package's own files: a dart: or package: URI is a leaf here
      // and is checked separately by [urisIn].
      if (target.startsWith('dart:') || target.startsWith('package:')) continue;
      queue.add(p.normalize(p.join(p.dirname(current), target)));
    }
  }
  return seen;
}

/// Every `dart:` and `package:` URI imported anywhere in [files], including
/// conditional-import targets.
Set<String> urisIn(Set<String> files) {
  final Set<String> uris = <String>{};
  for (final String path in files) {
    final File file = File(path);
    if (!file.existsSync()) continue;
    final String source = file.readAsStringSync();
    for (final RegExpMatch match in RegExp(
      r"""(?:import|export|if\s*\([^)]*\))\s*'((?:dart|package):[^']+)'""",
    ).allMatches(source)) {
      uris.add(match.group(1)!);
    }
  }
  return uris;
}

void main() {
  test('the shared entrypoint exists and is reachable', () {
    expect(File(p.join('lib', 'core.dart')).existsSync(), isTrue,
        reason: 'lib/core.dart is the half a frontend may import');
    expect(File(p.join('lib', 'backend.dart')).existsSync(), isTrue,
        reason: 'lib/backend.dart is the half only a server imports');
  });

  test('the shared half never reaches dart:ffi', () {
    // The whole point. dart:ffi in this closure means a frontend importing the
    // request and response types has pulled the native server surface in with
    // them.
    final Set<String> uris = urisIn(closureOf(p.join('lib', 'core.dart')));

    expect(uris, isNot(contains('dart:ffi')));
    expect(uris.where((String u) => u.contains('ffi')), isEmpty,
        reason: 'found: ${uris.where((String u) => u.contains('ffi'))}');
  });

  test('the shared half does not reach the server implementation', () {
    final Set<String> files = closureOf(p.join('lib', 'core.dart'));

    expect(
      files.where((String f) => p.basename(f) == 'server.dart'),
      isEmpty,
      reason: 'the server must be reachable only from backend.dart',
    );
  });

  test('the backend half does reach the server, or it serves nothing', () {
    // The inverse, so a split that quietly excluded everything would fail
    // rather than look like success.
    final Set<String> files = closureOf(p.join('lib', 'backend.dart'));

    expect(
      files.where((String f) => p.basename(f).startsWith('server')),
      isNotEmpty,
    );
  });

  test('the shared half still carries the types a frontend needs', () {
    final String source = File(p.join('lib', 'core.dart')).readAsStringSync();

    for (final String type in <String>['Request', 'Response', 'Headers']) {
      expect(source, contains(type),
          reason: 'dartvel_core re-exports $type from here');
    }
  });
}
