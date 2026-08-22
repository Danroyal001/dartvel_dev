// The native-asset hook runs before anything else — before `dart run` reaches
// a CLI main, before any Dartvel logging. A process that hangs in here hangs
// the whole build with no output at all and nothing downstream can time it
// out, because nothing downstream has started.
//
// A Windows build proved it: 40 minutes, and the entire captured output was
// "Running build hooks...". Two earlier attempts ran 257 and 226 minutes. The
// `--build-timeout` added to the CLI could not help, since the CLI never ran.
import 'dart:io';

import 'package:test/test.dart';

void main() {
  missingToolsSkipTests();

  group('the native asset hook', () {
    late String source;
    late String outsideGuard;

    setUp(() {
      source = File('hook/build.dart').readAsStringSync();
      // The guard is where a process is legitimately spawned unbounded before
      // being timed out, so its own body is excluded.
      final guardStart = source.indexOf('Future<ProcessResult?> _runBounded(');
      expect(guardStart, greaterThan(0), reason: 'the guard must exist');
      final guardBody = source.indexOf('async {', guardStart);
      final guardEnd = source.indexOf('\n}', guardBody);
      outsideGuard =
          source.substring(0, guardStart) + source.substring(guardEnd);
    });

    test('spawns no process without a bound', () {
      // Every Process.run and Process.start outside the guard is a way for the
      // build to stop forever. cargo build is the one that matters most: on a
      // cold cache it compiles nearly two hundred crates, so "slow" and
      // "wedged" look identical without a limit.
      final unbounded = RegExp(r'Process\.(run|start)\s*\(')
          .allMatches(outsideGuard)
          .map((m) => m.group(0))
          .toList();

      expect(
        unbounded,
        isEmpty,
        reason: 'route every process through _runBounded; a hook that hangs '
            'hangs the build before anything can report it',
      );
    });

    test('awaits no exit code without a bound', () {
      // Bounding the spawn is not enough on its own: awaiting exitCode
      // directly reintroduces the same unbounded wait.
      final unbounded = RegExp(r'await\s+[A-Za-z_][A-Za-z0-9_]*\.exitCode\b')
          .allMatches(outsideGuard)
          .map((m) => m.group(0))
          .toList();

      expect(unbounded, isEmpty,
          reason: 'an exit code awaited directly cannot be timed out');
    });

    test('the guard actually kills, rather than only reporting', () {
      // A timeout that leaves the process running turns one wedged build into
      // a wedged build plus an orphan holding its locks.
      final guardStart = source.indexOf('Future<ProcessResult?> _runBounded(');
      final guard = source.substring(guardStart);
      expect(guard.contains('.kill('), isTrue,
          reason: 'a bounded process must be killed when it outlives its bound');
    });
  });
}

// A missing tool must not break unrelated Dart commands. The hook runs for
// anything that depends on this package, including `dart run` on a
// documentation checker — which is how a spec-status job ended up compiling
// 162 Rust crates and then failing on a tool it had no reason to need.
void missingToolsSkipTests() {
  group('missing build tools', () {
    late String source;

    setUp(() => source = File('hook/build.dart').readAsStringSync());

    test('cbindgen is probed before use, the way cargo is', () {
      // cargo already gets this treatment: absent means skip, not fail. A
      // hard error for cbindgen is the same situation reported differently.
      expect(
        source.contains("'cbindgen',\n      <String>['--version']") ||
            source.contains('cbindgenCheck'),
        isTrue,
        reason: 'probe for cbindgen and skip when it is absent',
      );
    });

    test('an absent tool skips rather than throwing', () {
      // The skip messages are the contract: a build that cannot produce a
      // native asset says so and lets the caller continue.
      final skipMessages = RegExp(r"skipping[^']*'")
          .allMatches(source)
          .length;
      expect(skipMessages, greaterThanOrEqualTo(3),
          reason: 'cargo, cbindgen and an unsupported target each skip');
    });
  });
}
