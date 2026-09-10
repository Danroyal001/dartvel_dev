/// What each platform binds, counted from the source.
///
/// This exists because the number kept being wrong in prose. `docs/build-targets.md`
/// said 8 of 43 on Linux and none at all on five platforms, when it was 63 of
/// 87 and every one of those five bound something. `docs/spec-status.json` has
/// carried three different Android figures in a day. Every one of them was
/// written by a person reading the source and counting, and every one of them
/// was correct on the morning it was written.
///
/// Counting by hand also goes wrong in a way that is hard to see. A grep for
/// `'word.word'` misses `device.fleet.provision`, which is how 87 names were
/// reported as 70; grepping one file per platform misses everything a platform
/// delegates to a sub-module, which is how Linux's 63 were reported as 8.
///
/// So the count is computed instead, and prose should point here rather than
/// quote a number that was true once.
///
/// Run: dart tool/binding_coverage.dart
///
/// `dart`, not `dart run` -- this imports only `dart:` libraries, so it works
/// from a bare checkout with nothing resolved.
library;

import 'dart:io';

const String _platform = 'packages/dartvel_flutter/lib/src/platform';

/// Names inside a `const`/`static const` set or map literal in [source].
///
/// Deliberately anchored on the indentation the formatter produces for a
/// top-level literal, because the alternative -- every quoted dotted string in
/// the file -- also matches the names written in doc comments, and every one of
/// these files explains itself at length.
Set<String> dvNamesInLiteral(String source, String declaration) {
  final int start = source.indexOf(declaration);
  if (start < 0) return const <String>{};

  final Set<String> found = <String>{};
  final RegExp entry = RegExp(r"""^\s{2,6}'([a-z][A-Za-z0-9]*(?:\.[A-Za-z0-9]+)+)'""");
  for (final String line in source.substring(start).split('\n').skip(1)) {
    // The closing brace of the literal, at whatever indent it was declared.
    if (RegExp(r'^\s{0,4}\};').hasMatch(line)) break;
    final RegExpMatch? m = entry.firstMatch(line);
    if (m != null) found.add(m.group(1)!);
  }
  return found;
}

String _read(String path) {
  final File file = File(path);
  return file.existsSync() ? file.readAsStringSync() : '';
}

void main() {
  final Set<String> declared = dvNamesInLiteral(
    _read('$_platform/binding_names.dart'),
    'const Set<String> dvNativeBindingNames',
  );

  if (declared.isEmpty) {
    stderr.writeln('found no declared binding names. Run this from the '
        'repository root, or check whether dvNativeBindingNames was renamed.');
    exit(1);
  }

  // Where each platform states what it covers. Linux keeps its set inside the
  // bindings class rather than in a capabilities file of its own; the others
  // split it out so both branches of the conditional import can share it.
  final Map<String, ({String path, String declaration})> sets =
      <String, ({String path, String declaration})>{
    'linux': (
      path: '$_platform/linux/linux_bindings_ffi.dart',
      declaration: 'static const Set<String> implemented',
    ),
    'windows': (
      path: '$_platform/windows/windows_capabilities.dart',
      declaration: 'const Set<String> dvWindowsImplementedBindings',
    ),
    'macos': (
      path: '$_platform/macos/macos_capabilities.dart',
      declaration: 'const Set<String> dvMacosImplementedBindings',
    ),
    'android': (
      path: '$_platform/android/android_capabilities.dart',
      declaration: 'const Set<String> dvAndroidImplementedBindings',
    ),
    'web': (
      path: '$_platform/web/web_capabilities.dart',
      declaration: 'const Set<String> dvWebImplementedBindings',
    ),
    'ios': (
      path: '$_platform/ios/ios_capabilities.dart',
      declaration: 'const Set<String> dvIosImplementedBindings',
    ),
  };

  final Map<String, Set<String>> bound = <String, Set<String>>{
    for (final MapEntry<String, ({String declaration, String path})> e
        in sets.entries)
      e.key: dvNamesInLiteral(_read(e.value.path), e.value.declaration),
  };

  final List<String> order = bound.keys.toList()
    ..sort((String a, String b) => bound[b]!.length.compareTo(bound[a]!.length));

  stdout.writeln('${declared.length} binding names declared\n');
  for (final String name in order) {
    final Set<String> set = bound[name]!;
    // A name a platform claims and the declaration does not know about. The
    // names test already fails on this; reported here because a coverage
    // figure counted against the wrong denominator is worse than no figure.
    final Set<String> undeclared = set.difference(declared);
    final String note = undeclared.isEmpty ? '' : '  (undeclared: $undeclared)';
    stdout.writeln('${name.padRight(9)} ${set.length.toString().padLeft(3)}'
        ' of ${declared.length}$note');
  }

  // Names in no capability set. That is not the same as unbound, and saying
  // so would be the mistake this tool exists to stop: window.open is
  // registered by dartvel_windowing, which is a package rather than a
  // platform, so it belongs to no capability set and works. Each one is
  // therefore looked for across every package before it is called missing.
  final Set<String> unclaimed = declared.difference(
    bound.values.expand((Set<String> s) => s).toSet(),
  );
  if (unclaimed.isEmpty) return;

  final List<String> elsewhere = <String>[];
  final List<String> nowhere = <String>[];
  for (final String name in unclaimed.toList()..sort()) {
    final String? file = _registrarOf(name);
    (file == null ? nowhere : elsewhere).add(
      file == null ? name : '$name  <- $file',
    );
  }

  if (elsewhere.isNotEmpty) {
    stdout.writeln('\n${elsewhere.length} registered outside a capability set');
    for (final String line in elsewhere) {
      stdout.writeln('  $line');
    }
  }
  if (nowhere.isNotEmpty) {
    stdout.writeln('\n${nowhere.length} declared and registered nowhere');
    for (final String line in nowhere) {
      stdout.writeln('  $line');
    }
  }
}

/// The file that registers [name], anywhere under `packages/`, or null.
///
/// `\s*` after the parenthesis because the formatter wraps a long handler onto
/// the next line, and a pattern without it reads that as no registration --
/// which is how thirteen Android bindings once looked claimed and unwired.
String? _registrarOf(String name) {
  final RegExp call = RegExp(
    '(?:DVNativeBridge\\.)?(?:register|bind)\\(\\s*'
    "'${RegExp.escape(name)}'",
  );
  final Directory packages = Directory('packages');
  if (!packages.existsSync()) return null;
  for (final FileSystemEntity entity in packages.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (!entity.path.contains('/lib/')) continue;
    if (call.hasMatch(entity.readAsStringSync())) return entity.path;
  }
  return null;
}
