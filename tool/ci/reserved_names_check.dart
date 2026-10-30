/// Fails when a name the specification closed is used as a public identifier.
///
///     dart tool/ci/reserved_names_check.dart
///
/// Three closed sets, and each one is closed for a reason worth keeping:
///
/// **One public surface for capability.** `DV.Modules.<id>` and the existing
/// subsystems, and nothing beside them. A `DV.Bindings`, `DV.Native`,
/// `DV.Integrations`, `DV.Packages` or `DV.Plugins` would be a second name for
/// the concept the module system exists to be the only one of, and a
/// `DVModuleManager` beside `DV.Modules` is the same thing one level down.
///
/// **Five binding kinds.** Kind, source language and target are three
/// dimensions that do not vary independently: Swift, Objective-C, C++ and Rust
/// all reach Dart across the C ABI, so all four are `DVFfiBinding`. A
/// `DVSwiftBinding` or a `DVWindowsBinding` multiplies the machinery by a
/// cross product nobody needs.
///
/// **No platform channels.** Generated FFI and JNI everywhere, which is the
/// rule the whole native story rests on.
///
/// A rule nothing checks drifts back, which is the same reason
/// `no_python_check.dart` exists. This one runs over tracked Dart sources; it
/// leaves prose alone, so the specification and the rule files can name what
/// they forbid. Comments and the text of string literals are prose too: a
/// docs page saying no `MethodChannel` is used, or a test asserting generated
/// code has none, is the rule being kept. The reserved names and the lexer
/// that tells code from prose are in `reserved_names.dart`.
library;

import 'dart:io';

import 'reserved_names.dart';

void main(List<String> arguments) {
  final ProcessResult tracked = Process.runSync('git', <String>[
    'ls-files',
    '-z',
    '*.dart',
  ]);
  if (tracked.exitCode != 0) {
    stderr.writeln('reserved names: git ls-files failed');
    exitCode = 1;
    return;
  }

  // These two files name every reserved identifier as data.
  const Set<String> exempt = <String>{
    'tool/ci/reserved_names_check.dart',
    'tool/ci/reserved_names.dart',
  };

  final List<String> problems = <String>[];
  int scanned = 0;
  for (final String path in '${tracked.stdout}'.split('\u0000')) {
    if (path.isEmpty || exempt.contains(path)) continue;
    final File file = File(path);
    if (!file.existsSync()) continue;
    scanned++;
    for (final DVReservedUse use in dvReservedNameUses(
      file.readAsStringSync(),
    )) {
      problems.add('$path:${use.line}  ${use.name}: ${use.because}');
    }
  }

  if (problems.isNotEmpty) {
    stderr.writeln('reserved names: ${problems.length} use(s):');
    for (final String problem in problems) {
      stderr.writeln('  - $problem');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'reserved names: $scanned tracked Dart file(s), none naming a closed '
    'set\'s reserved identifier or a platform channel.',
  );
}
