/// Studio's code, out of the public web root.
///
/// Studio is routes of the application, and its screens are the deferred
/// library the Studio route loads (`dartvel_studio`). dart2js writes that
/// library's code into parts beside `main.dart.js`, where every file is served
/// to anybody. The parts only Studio's screens load are moved out, to be
/// carried apart from the web files and served from memory to a session with
/// the Studio grant. A part Studio shares with the sign-in or with a page is
/// public code somebody with no grant needs, and stays.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'route_prefetch.dart' show dvDeferredParts;

/// The deferred import Studio's screens are loaded through, as dart2js
/// names it in `main.dart.js`.
const String dvStudioDeferredImport = 'dartvel_studio';

/// What [dvSplitStudioParts] did.
class DVStudioPartsResult {
  const DVStudioPartsResult({this.parts = const <String>[], this.problem});

  /// The part files moved, by name.
  final List<String> parts;

  /// Why the build must fail, or null.
  final String? problem;
}

/// Moves the parts only Studio's screens load from [webRoot] into
/// [partsRoot], which is emptied first.
DVStudioPartsResult dvSplitStudioParts({
  required String webRoot,
  required String partsRoot,
}) {
  final Directory out = Directory(partsRoot);
  if (out.existsSync()) out.deleteSync(recursive: true);

  final File main = File(p.join(webRoot, 'main.dart.js'));
  if (!main.existsSync()) {
    return DVStudioPartsResult(
        problem: 'No main.dart.js in $webRoot, so there is no telling which '
            "of its parts are Studio's.");
  }
  final Map<String, List<String>> table =
      dvDeferredParts(main.readAsStringSync());
  final List<String>? studio = table[dvStudioDeferredImport];
  if (studio == null) {
    return const DVStudioPartsResult(
        problem: "Studio's screens are not a deferred library of their own in "
            'this build, so their code would be in main.dart.js and served to '
            'every visitor. The build is stopped rather than ship that.');
  }
  final Set<String> public = <String>{
    for (final MapEntry<String, List<String>> entry in table.entries)
      if (entry.key != dvStudioDeferredImport) ...entry.value,
  };
  final List<String> own = <String>[
    for (final String part in studio)
      if (!public.contains(part)) part,
  ];
  if (own.isEmpty) {
    return const DVStudioPartsResult(
        problem: "Studio's screens have no part of their own in this build: "
            'every part they load is also loaded by public code, so there is '
            'nothing to keep behind the Studio grant. The build is stopped.');
  }

  out.createSync(recursive: true);
  for (final String part in own) {
    for (final String name in <String>[part, '$part.map']) {
      final File file = File(p.join(webRoot, name));
      if (!file.existsSync()) continue;
      file.copySync(p.join(out.path, name));
      file.deleteSync();
    }
  }
  return DVStudioPartsResult(parts: own);
}

/// The parts [dvSplitStudioParts] wrote to [partsRoot], by name.
Map<String, List<int>> dvReadStudioParts(String partsRoot) {
  final Directory root = Directory(partsRoot);
  if (!root.existsSync()) return const <String, List<int>>{};
  return <String, List<int>>{
    for (final FileSystemEntity entity in root.listSync())
      if (entity is File) p.basename(entity.path): entity.readAsBytesSync(),
  };
}

/// Where a web-server build keeps what it carries of Studio, apart from the
/// public web root: `data` (the graph and page structures) and `parts`
/// (Studio's code).
const String dvStudioDirectory = 'build/studio';

/// Studio's data, relative to the project.
const String dvStudioDataDirectory = 'build/studio/data';

/// Studio's code, relative to the project.
const String dvStudioPartsDirectory = 'build/studio/parts';

/// Whether Studio's code is in the web build whose main.dart.js is [mainJs].
///
/// Studio is reached only through its deferred import, so its code is in the
/// build exactly when that import owns part files. dart2js keeps the import's
/// key in its table after tree shaking has removed everything behind it --
/// `dartvel_studio:[]` -- and reading the key alone refused every static
/// `dartvel build web`, whose Studio routes sit behind a false constant.
bool dvStudioCompiledIn(String mainJs) =>
    (dvDeferredParts(mainJs)[dvStudioDeferredImport] ?? const <String>[])
        .isNotEmpty;
