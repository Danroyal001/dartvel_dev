/// Code splitting for the WebAssembly build.
///
/// Every Dartvel page is a deferred library. Flutter 3.50's
/// `flutter build web --wasm --enable-wasm-deferred-loading` has dart2wasm
/// write each into modules of its own (`main.dart_module<N>.wasm`), and the
/// deferred-module loader Dartvel gives flutter.js (see
/// `dvBootstrapWithLoaderConfig`) fetches each once.
///
/// What Flutter does not hand over is which modules each deferred import
/// needs. dart2wasm writes that only when asked with `--deferred-map`, an
/// option `flutter build web` cannot pass: its one channel to dart2wasm,
/// `--extra-front-end-options`, reaches dart2js too, and each compiler
/// rejects the other's spelling. The build needs it twice -- each page
/// preloads its route's modules, and Studio's modules are kept out of the
/// public files -- so it works it out from what the build wrote:
///
///  * the build asks for source maps, so each module says which libraries
///    its code comes from;
///  * dart2js's table in main.dart.js says exactly which parts each import
///    loads, and their source maps say which libraries those hold.
///
/// A module belongs to the imports whose dart2js parts hold every library of
/// it that main.dart.js does not ([dvInferWasmModules]). The maps then
/// leave the site ([dvRemoveCompilerSourceMaps]): they were never part of it.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'route_prefetch.dart' show dvDeferredParts;

/// The libraries a source map names, as absolute paths (or URIs, for a
/// scheme that is not a file), leaving out the SDK's own (`org-dartlang-sdk:`).
///
/// dart2wasm names `file:` URIs and dart2js paths relative to the map, which
/// is at [mapPath]; both come out the same. A map that will not parse names
/// nothing.
Set<String> dvSourceMapLibraries(String mapJson, String mapPath) {
  final Object? decoded;
  try {
    decoded = jsonDecode(mapJson);
  } on FormatException {
    return const <String>{};
  }
  if (decoded is! Map) return const <String>{};
  final Object? sources = decoded['sources'];
  if (sources is! List) return const <String>{};
  final Object? root = decoded['sourceRoot'];
  final String base = p.normalize(p.join(
      p.dirname(mapPath), root is String && root.isNotEmpty ? root : ''));
  return <String>{
    for (final Object? source in sources)
      if (source is String && source.isNotEmpty)
        if (_library(source, base) case final String library) library,
  };
}

String? _library(String source, String base) {
  final Uri? uri = Uri.tryParse(source);
  if (uri == null) return null;
  if (uri.scheme == 'org-dartlang-sdk' || uri.scheme == 'dart') return null;
  if (uri.scheme == 'file') return p.normalize(uri.toFilePath());
  if (uri.hasScheme && uri.scheme.length > 1) return source;
  return p.normalize(p.join(base, source));
}

/// Which wasm modules each deferred import needs, by import prefix, in
/// module-number order.
///
/// [jsParts] is dart2js's own table (prefix to part files), [jsPartLibraries]
/// what each part's source map names, [jsMainLibraries] what main.dart.js's
/// names, and [wasmModuleLibraries] what each module's names.
///
/// Both compilers split by the set of deferred imports that reach each piece
/// of code, so a module and the dart2js parts of the same imports hold the
/// same libraries. What tells a module apart is its libraries main.dart.js
/// lacks; a library dart2js put in no part (shaken out, or in main) says
/// nothing and is passed over. A module belongs to every import whose parts
/// hold all of what is left. A module with nothing left -- dart2wasm's
/// catch-all for code nothing calls, or code dart2js keeps in main -- belongs
/// to none: no page preloads it, and Studio never claims it. When no single
/// import holds all of it (the compilers disagreeing), it belongs to each
/// import that holds any of it, so Studio never takes a module a page may
/// load.
Map<String, List<String>> dvInferWasmModules({
  required Map<String, List<String>> jsParts,
  required Map<String, Set<String>> jsPartLibraries,
  required Set<String> jsMainLibraries,
  required Map<String, Set<String>> wasmModuleLibraries,
}) {
  // Which imports load a part holding each library.
  final Map<String, Set<String>> importsOf = <String, Set<String>>{};
  for (final MapEntry<String, List<String>> entry in jsParts.entries) {
    for (final String part in entry.value) {
      for (final String library
          in jsPartLibraries[part] ?? const <String>{}) {
        (importsOf[library] ??= <String>{}).add(entry.key);
      }
    }
  }
  final Map<String, List<String>> byImport = <String, List<String>>{};
  for (final MapEntry<String, Set<String>> module
      in wasmModuleLibraries.entries) {
    final List<Set<String>> holders = <Set<String>>[
      for (final String library in module.value)
        if (!jsMainLibraries.contains(library))
          if (importsOf[library] case final Set<String> imports) imports,
    ];
    if (holders.isEmpty) continue;
    Set<String> owners = holders
        .skip(1)
        .fold<Set<String>>(<String>{...holders.first},
            (Set<String> all, Set<String> next) => all.intersection(next));
    if (owners.isEmpty) {
      owners = <String>{for (final Set<String> imports in holders) ...imports};
    }
    for (final String import in owners) {
      (byImport[import] ??= <String>[]).add(module.key);
    }
  }
  for (final List<String> modules in byImport.values) {
    modules.sort((String a, String b) => _moduleNumber(a).compareTo(_moduleNumber(b)));
  }
  return byImport;
}

final RegExp _modulePattern = RegExp(r'^main\.dart_module(\d+)\.wasm$');

int _moduleNumber(String module) =>
    int.tryParse(_modulePattern.firstMatch(module)?.group(1) ?? '') ?? 0;

/// What [dvReadWasmDeferredImports] found.
class DVWasmDeferredImports {
  const DVWasmDeferredImports(
      {this.byImport = const <String, List<String>>{}, this.problem});

  /// Each deferred import's modules, by prefix ([dvInferWasmModules]).
  final Map<String, List<String>> byImport;

  /// Why nothing could be read, or null.
  final String? problem;
}

/// [dvInferWasmModules] for the build in [webRoot], from main.dart.js's
/// table and the source maps the build asked for. A module or part without
/// its map is reported rather than guessed at.
DVWasmDeferredImports dvReadWasmDeferredImports(String webRoot) {
  final File mainJs = File(p.join(webRoot, 'main.dart.js'));
  if (!mainJs.existsSync()) {
    return const DVWasmDeferredImports(
        problem: 'The build wrote no main.dart.js to read the deferred '
            'imports from.');
  }
  // dart2js writes its maps in <project>/.dart_tool/flutter_build/<hash>/
  // and Flutter copies them here unchanged, so their relative paths are
  // from there; dart2wasm's are absolute file: URIs.
  final String dart2jsMapDirectory = p.join(p.dirname(p.dirname(webRoot)),
      '.dart_tool', 'flutter_build', 'build');
  Set<String>? librariesOf(String file) {
    final File map = File(p.join(webRoot, '$file.map'));
    if (!map.existsSync()) return null;
    return dvSourceMapLibraries(
        map.readAsStringSync(),
        file.endsWith('.js')
            ? p.join(dart2jsMapDirectory, '$file.map')
            : map.path);
  }

  final Map<String, List<String>> jsParts =
      dvDeferredParts(mainJs.readAsStringSync());
  final List<String> missing = <String>[];
  final Map<String, Set<String>> partLibraries = <String, Set<String>>{};
  for (final String part in <String>{
    for (final List<String> parts in jsParts.values) ...parts,
  }) {
    final Set<String>? libraries = librariesOf(part);
    if (libraries == null) {
      missing.add(part);
    } else {
      partLibraries[part] = libraries;
    }
  }
  final Set<String>? mainLibraries = librariesOf('main.dart.js');
  if (mainLibraries == null) missing.add('main.dart.js');
  final Map<String, Set<String>> moduleLibraries = <String, Set<String>>{};
  for (final FileSystemEntity entity in Directory(webRoot).listSync()) {
    final String name = p.basename(entity.path);
    if (entity is! File || !_modulePattern.hasMatch(name)) continue;
    final Set<String>? libraries = librariesOf(name);
    if (libraries == null) {
      missing.add(name);
    } else {
      moduleLibraries[name] = libraries;
    }
  }
  if (missing.isNotEmpty) {
    missing.sort();
    return DVWasmDeferredImports(
        problem: 'No source map for ${missing.join(', ')}, so which modules '
            'each page needs cannot be told.');
  }
  return DVWasmDeferredImports(
    byImport: dvInferWasmModules(
      jsParts: jsParts,
      jsPartLibraries: partLibraries,
      jsMainLibraries: mainLibraries!,
      wasmModuleLibraries: moduleLibraries,
    ),
  );
}

/// Whether [name] is a file the dart2js or dart2wasm compile wrote.
bool _compiledApp(String name) =>
    name == 'main.dart.js' ||
    name == 'main.dart.mjs' ||
    name == 'main.dart.wasm' ||
    _modulePattern.hasMatch(name) ||
    RegExp(r'^main\.dart\.js_\d+\.part\.js$').hasMatch(name);

final RegExp _jsSourceMapComment =
    RegExp(r'\n?//# sourceMappingURL=[^\n]*\n?$');

/// Deletes the source maps the compilers wrote into [webRoot] and what names
/// them: the `//# sourceMappingURL` line of each script and the
/// `sourceMappingURL` section of each wasm file. flutter.js's own map stays,
/// as Flutter ships it with every build.
void dvRemoveCompilerSourceMaps(String webRoot) {
  final Directory web = Directory(webRoot);
  if (!web.existsSync()) return;
  for (final FileSystemEntity entity in web.listSync()) {
    if (entity is! File) continue;
    final String name = p.basename(entity.path);
    if (name.endsWith('.map') &&
        _compiledApp(name.substring(0, name.length - '.map'.length))) {
      entity.deleteSync();
    } else if (_compiledApp(name) && name.endsWith('.wasm')) {
      final Uint8List bytes = entity.readAsBytesSync();
      final Uint8List stripped = dvWithoutWasmSourceMapUrl(bytes);
      if (stripped.length != bytes.length) entity.writeAsBytesSync(stripped);
    } else if (_compiledApp(name)) {
      final String source = entity.readAsStringSync();
      final RegExpMatch? comment = _jsSourceMapComment.firstMatch(source);
      if (comment == null) continue;
      // The newline before the comment is the script's own last one when it
      // had one, and is kept.
      final String kept = source.substring(0, comment.start);
      entity.writeAsStringSync(
          comment.group(0)!.endsWith('\n') && comment.group(0)!.startsWith('\n')
              ? '$kept\n'
              : kept);
    }
  }
}

/// [wasm] without its `sourceMappingURL` custom section, every other byte
/// as it was. Anything that does not parse as a wasm module comes back
/// unchanged.
Uint8List dvWithoutWasmSourceMapUrl(Uint8List wasm) {
  const List<int> header = <int>[0, 0x61, 0x73, 0x6d, 1, 0, 0, 0];
  if (wasm.length < header.length) return wasm;
  for (int i = 0; i < header.length; i++) {
    if (wasm[i] != header[i]) return wasm;
  }
  int at = header.length;
  (int, int)? leb() {
    int value = 0, shift = 0;
    while (at < wasm.length && shift < 35) {
      final int byte = wasm[at++];
      value |= (byte & 0x7f) << shift;
      if (byte < 0x80) return (value, at);
      shift += 7;
    }
    return null;
  }

  final BytesBuilder out = BytesBuilder(copy: false)..add(header);
  bool removed = false;
  while (at < wasm.length) {
    final int start = at;
    final int id = wasm[at++];
    final (int, int)? size = leb();
    if (size == null || size.$2 + size.$1 > wasm.length) return wasm;
    final int end = size.$2 + size.$1;
    if (id == 0) {
      final (int, int)? nameLength = leb();
      if (nameLength == null || nameLength.$2 + nameLength.$1 > end) return wasm;
      final String name = utf8.decode(
          wasm.sublist(nameLength.$2, nameLength.$2 + nameLength.$1),
          allowMalformed: true);
      if (name == 'sourceMappingURL') {
        removed = true;
        at = end;
        continue;
      }
    }
    out.add(Uint8List.sublistView(wasm, start, end));
    at = end;
  }
  return removed ? out.takeBytes() : wasm;
}

/// Takes the WebAssembly app out of the site in [webRoot], leaving the
/// dart2js and CanvasKit app every browser can run: the dart2wasm entry
/// leaves the build config flutter.js chooses from, and its files go.
///
/// For a build that must not ship the wasm app as it stands -- one whose
/// Studio modules cannot be told apart from public ones.
void dvDropWasmApp(String webRoot) {
  final File bootstrap = File(p.join(webRoot, 'flutter_bootstrap.js'));
  if (bootstrap.existsSync()) {
    final String source = bootstrap.readAsStringSync();
    final RegExp configLine =
        RegExp(r'_flutter\.buildConfig\s*=\s*(\{[^\n]*\})\s*;');
    final RegExpMatch? match = configLine.firstMatch(source);
    if (match != null) {
      final Object? config = jsonDecode(match.group(1)!);
      if (config is Map && config['builds'] is List) {
        final Map<Object?, Object?> kept = <Object?, Object?>{
          ...config,
          'builds': <Object?>[
            for (final Object? build in config['builds'] as List)
              if (build is Map && build['compileTarget'] != 'dart2wasm') build,
          ],
        };
        bootstrap.writeAsStringSync(source.replaceRange(match.start, match.end,
            '_flutter.buildConfig = ${jsonEncode(kept)};'));
      }
    }
  }
  final Directory web = Directory(webRoot);
  if (!web.existsSync()) return;
  for (final FileSystemEntity entity in web.listSync()) {
    if (entity is! File) continue;
    final String name = p.basename(entity.path);
    final String stem =
        name.endsWith('.map') ? name.substring(0, name.length - 4) : name;
    if (stem == 'main.dart.wasm' ||
        stem == 'main.dart.mjs' ||
        _modulePattern.hasMatch(stem)) {
      entity.deleteSync();
    }
  }
}
