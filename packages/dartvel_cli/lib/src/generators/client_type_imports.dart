/// The imports the generated client needs for the types a backend function
/// names.
///
/// functions.g.dart copies a function's return and parameter types into the
/// client's signatures. It imported none of them, so a function returning a
/// type of the application's own generated a client that did not compile.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// Names the client already has without an import: `dart:core` and the
/// collection types the signatures are built from.
const Set<String> _known = <String>{
  'bool', 'double', 'dynamic', 'int', 'num', 'void', 'Never', 'Null',
  'Object', 'String', 'Function', 'Record', 'Symbol', 'Type',
  'Future', 'FutureOr', 'Stream', 'Iterable', 'List', 'Map', 'Set',
  'DateTime', 'Duration', 'Uri', 'BigInt', 'RegExp',
};

final RegExp _importPattern =
    RegExp(r'''^\s*import\s+['"]([^'"]+)['"]''', multiLine: true);

/// Package URIs, sorted, for every file of [packageName] that [source]
/// imports and that declares one of the type names in [types].
///
/// Only the application's own files are followed: a relative import, or a
/// `package:` import of [packageName]. A type from another package, or from
/// `dart:`, is left to that package's own export, which the client already
/// has when the type is Dartvel's.
List<String> dvClientTypeImports({
  required String source,
  required String sourcePath,
  required String projectRoot,
  required String packageName,
  required List<String> types,
}) {
  final Set<String> wanted = <String>{
    for (final String type in types)
      for (final RegExpMatch m in RegExp(r'[A-Za-z_$][\w$]*').allMatches(type))
        if (!_known.contains(m.group(0))) m.group(0)!,
  };
  if (wanted.isEmpty) return const <String>[];

  final String lib = p.join(projectRoot, 'lib');
  final Set<String> found = <String>{};
  for (final RegExpMatch m in _importPattern.allMatches(source)) {
    final String uri = m.group(1)!;
    final String? file;
    if (uri.startsWith('package:$packageName/')) {
      file = p.joinAll(<String>[
        lib,
        ...uri.substring('package:$packageName/'.length).split('/'),
      ]);
    } else if (!uri.contains(':')) {
      file = p.normalize(
          p.joinAll(<String>[p.dirname(sourcePath), ...uri.split('/')]));
    } else {
      file = null;
    }
    if (file == null || !p.isWithin(lib, file)) continue;
    final File declared = File(file);
    if (!declared.existsSync()) continue;
    final String text = declared.readAsStringSync();
    final bool declares = wanted.any((String name) => RegExp(
          r'^(?:(?:abstract|sealed|final|base|interface|mixin)\s+)*'
          '(?:class|enum|mixin|typedef|extension\\s+type)\\s+'
          '${RegExp.escape(name)}\\b',
          multiLine: true,
        ).hasMatch(text));
    if (!declares) continue;
    found.add('package:$packageName/'
        '${p.split(p.relative(file, from: lib)).join('/')}');
  }
  return found.toList()..sort();
}
