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
/// they forbid.
library;

import 'dart:io';

/// A reserved name, and why.
typedef _Reserved = (String name, String because);

const List<_Reserved> _reserved = <_Reserved>[
  // A second namespace for what DV.Modules already is.
  ('DVModuleManager', 'DV.Modules is the surface; a manager beside it is a '
      'second name for one concept'),
  ('DVBindingManager', 'bindings are internal machinery beneath modules and '
      'have no manager an application names'),
  ('DVBindings', 'internal means internal; a public DV.Bindings would make a '
      'binding a thing developers manage'),
  ('DVIntegrations', 'an integration is a module'),
  ('DVPackages', 'a package is a package; what an application composes is a '
      'module'),
  ('DVPlugins', 'Dartvel has no plugin tier, which is the whole point of '
      'having one composition unit'),
  // Per-language and per-platform binding classes.
  ('DVSwiftBinding', 'Swift reaches Dart across the C ABI: DVFfiBinding'),
  ('DVRustBinding', 'Rust reaches Dart across the C ABI: DVFfiBinding'),
  ('DVKotlinBinding', 'Kotlin is reached through the JVM: DVJniBinding'),
  ('DVObjCBinding', 'Objective-C reaches Dart across the C ABI: DVFfiBinding'),
  ('DVAppleBinding', 'a target is not a binding kind: DVFfiBinding'),
  ('DVWindowsBinding', 'a target is not a binding kind: DVFfiBinding'),
  ('DVLinuxBinding', 'a target is not a binding kind: DVFfiBinding'),
  ('DVAndroidBinding', 'a target is not a binding kind: DVJniBinding or '
      'DVFfiBinding, and an Android module may carry both'),
  ('DVJvmBinding', 'JNI is the boundary being crossed, so DVJniBinding'),
];

/// Flutter's platform channels, which Dartvel never uses.
const List<String> _channels = <String>[
  'MethodChannel',
  'EventChannel',
  'BasicMessageChannel',
];

void main(List<String> arguments) {
  final ProcessResult tracked = Process.runSync(
    'git',
    <String>['ls-files', '-z', '*.dart'],
  );
  if (tracked.exitCode != 0) {
    stderr.writeln('reserved names: git ls-files failed');
    exitCode = 1;
    return;
  }

  final List<String> problems = <String>[];
  int scanned = 0;
  for (final String path in '${tracked.stdout}'.split('\u0000')) {
    if (path.isEmpty) continue;
    // This file names every one of them, and so does the checker that would
    // otherwise have to be written to exempt it.
    if (path == 'tool/ci/reserved_names_check.dart') continue;
    final File file = File(path);
    if (!file.existsSync()) continue;
    scanned++;
    final List<String> lines = file.readAsLinesSync();
    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i];
      // A rule explained in a comment is not a rule broken.
      final String code = line.split('//').first;
      if (code.trim().isEmpty) continue;
      for (final _Reserved name in _reserved) {
        if (!RegExp('\\b${name.$1}\\b').hasMatch(code)) continue;
        problems.add('$path:${i + 1}  ${name.$1} is reserved: ${name.$2}');
      }
      for (final String channel in _channels) {
        if (!RegExp('\\b$channel\\b').hasMatch(code)) continue;
        problems.add(
          '$path:${i + 1}  $channel is a Flutter platform channel. Dartvel '
          'binds natively through generated FFI/ffigen and JNI/jnigen.',
        );
      }
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
