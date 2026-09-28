/// The public surface of an npm package, from its package.json and its
/// TypeScript declarations.
///
/// The declarations are what make a typed Dart surface possible at all: a
/// JavaScript file says what it exports and nothing about the values. A
/// package with none is refused (`DV-MODULE-010`) rather than wrapped in
/// `Object?`, which would compile and tell a caller nothing.
///
/// Every operation is asynchronous in Dart whatever TypeScript says. In a
/// browser the package is loaded by the first call, and on the backend it
/// runs in Node, so there is no environment in which the answer is there
/// when the call returns.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'dart_surface.dart';

/// What an npm package offers, and where it can run.
class DVNpmSurface {
  const DVNpmSurface({
    required this.name,
    required this.version,
    required this.directory,
    required this.entry,
    required this.operations,
    required this.skipped,
    required this.web,
    required this.node,
    required this.hasDependencies,
  });

  final String name;
  final String version;
  final String directory;

  /// The file a browser or Node loads, relative to [directory].
  final String entry;

  final List<DVModuleOperation> operations;
  final Map<String, String> skipped;

  /// Whether a browser can run it: it reaches for no Node built-in.
  final bool web;

  /// Whether Node can run it: it is not a browser-only build.
  final bool node;

  /// Whether it imports other packages, which a browser cannot resolve by
  /// name, so it has to be bundled before it is served.
  final bool hasDependencies;
}

const Set<String> _nodeBuiltins = <String>{
  'fs', 'path', 'os', 'child_process', 'net', 'tls', 'http', 'https', 'crypto',
  'stream', 'zlib', 'worker_threads', 'cluster', 'dgram', 'dns', 'readline',
  'module', 'process', 'buffer', 'url', 'util', 'vm',
};

/// Reads the npm package at [dir].
DVNpmSurface dvScanNpmPackage(String dir) {
  final File manifestFile = File(p.join(dir, 'package.json'));
  if (!manifestFile.existsSync()) {
    throw DVDartSurfaceRefused('$dir has no package.json.');
  }
  final Map<String, Object?> manifest =
      jsonDecode(manifestFile.readAsStringSync()) as Map<String, Object?>;
  final String name = '${manifest['name'] ?? ''}';
  final String version = '${manifest['version'] ?? '0.0.0'}';
  final String? entry = _entry(manifest);
  if (entry == null || !File(p.join(dir, entry)).existsSync()) {
    throw DVDartSurfaceRefused('$name names no file to load: package.json '
        'has no browser, module, exports or main entry that exists '
        '(DV-MODULE-010).');
  }
  final String? types = _types(manifest, dir, entry);
  if (types == null) {
    throw DVDartSurfaceRefused('$name ships no TypeScript declarations, so '
        'nothing says what its functions take and return. A module with an '
        'untyped surface is not generated (DV-MODULE-010).');
  }

  final List<DVModuleOperation> operations = <DVModuleOperation>[];
  final Map<String, String> skipped = <String, String>{};
  final String declarations = _withoutComments(
      File(p.join(dir, types)).readAsStringSync(),
      keepJsDoc: true);
  final RegExp function = RegExp(
      r'(?:/\*\*([\s\S]*?)\*/\s*)?export\s+(?:declare\s+)?function\s+([A-Za-z_$][\w$]*)\s*(<[^>(]*>)?\s*\(([^)]*(?:\([^)]*\)[^)]*)*)\)\s*:\s*((?:\{[^}]*\}|[^;{])+);');
  for (final RegExpMatch m in function.allMatches(declarations)) {
    final String fn = m.group(2)!;
    if (operations.any((DVModuleOperation o) => o.name == fn)) continue;
    if (m.group(3) != null) {
      skipped[fn] = 'is generic';
      continue;
    }
    final String? why = _whyNot(m.group(4)!, m.group(5)!.trim());
    if (why != null) {
      skipped[fn] = why;
      continue;
    }
    final List<DVModuleParam> params = <DVModuleParam>[];
    for (final String raw in _splitTop(m.group(4)!)) {
      final RegExpMatch? pm =
          RegExp(r'^\s*([A-Za-z_$][\w$]*)(\?)?\s*:\s*(.+?)\s*$').firstMatch(raw);
      final bool optional = pm!.group(2) != null;
      final String type = _dart(pm.group(3)!)!;
      params.add(DVModuleParam(
        name: pm.group(1)!,
        type: optional && !type.endsWith('?') ? '$type?' : type,
        required: !optional,
      ));
    }
    String result = m.group(5)!.trim();
    final RegExpMatch? promise = RegExp(r'^Promise<(.+)>$').firstMatch(result);
    if (promise != null) result = promise.group(1)!;
    final String dartResult = _dart(result)!;
    operations.add(DVModuleOperation(
      name: fn,
      returnType: 'Future<$dartResult>',
      params: params,
      doc: (m.group(1) ?? '')
          .split('\n')
          .map((String l) => l.replaceFirst(RegExp(r'^\s*\*\s?'), '').trim())
          .where((String l) => l.isNotEmpty && !l.startsWith('@'))
          .join(' '),
    ));
  }
  operations.sort(
      (DVModuleOperation a, DVModuleOperation b) => a.name.compareTo(b.name));

  final String code = File(p.join(dir, entry)).readAsStringSync();
  final bool usesNode = RegExp(
          r'''(?:require\(\s*|from\s+|import\(\s*)['"](node:[\w/]+|[\w_]+)['"]''')
      .allMatches(code)
      .map((RegExpMatch m) => m.group(1)!)
      .any((String s) => s.startsWith('node:') || _nodeBuiltins.contains(s));
  final Object? deps = manifest['dependencies'];
  final bool browserOnly =
      manifest['browser'] != null && manifest['main'] == null &&
          manifest['module'] == null && manifest['exports'] == null;

  return DVNpmSurface(
    name: name,
    version: version,
    directory: dir,
    entry: entry,
    operations: operations,
    skipped: skipped,
    web: !usesNode,
    node: !browserOnly,
    hasDependencies: deps is Map && deps.isNotEmpty,
  );
}

String? _entry(Map<String, Object?> manifest) {
  final Object? browser = manifest['browser'];
  if (browser is String) return _clean(browser);
  final Object? exports = manifest['exports'];
  if (exports is String) return _clean(exports);
  if (exports is Map) {
    final Object? dot = exports['.'] ?? exports;
    if (dot is String) return _clean(dot);
    if (dot is Map) {
      for (final String key in <String>['browser', 'import', 'default', 'require']) {
        final Object? value = dot[key];
        if (value is String) return _clean(value);
        if (value is Map && value['default'] is String) {
          return _clean(value['default']! as String);
        }
      }
    }
  }
  for (final String key in <String>['module', 'main']) {
    if (manifest[key] is String) return _clean(manifest[key]! as String);
  }
  return 'index.js';
}

String? _types(Map<String, Object?> manifest, String dir, String entry) {
  for (final String key in <String>['types', 'typings']) {
    final Object? value = manifest[key];
    if (value is String && File(p.join(dir, _clean(value))).existsSync()) {
      return _clean(value);
    }
  }
  final String beside = entry.replaceFirst(RegExp(r'\.(m|c)?js$'), '.d.ts');
  if (File(p.join(dir, beside)).existsSync()) return beside;
  if (File(p.join(dir, 'index.d.ts')).existsSync()) return 'index.d.ts';
  return null;
}

String _clean(String path) => path.startsWith('./') ? path.substring(2) : path;

/// Why a declaration cannot be a Dart operation, or null when it can.
String? _whyNot(String params, String result) {
  if (params.contains('=>') || result.contains('=>')) {
    return 'takes or returns a function';
  }
  for (final String raw in <String>[..._splitTop(params), result]) {
    final String type = raw.contains(':') && raw != result
        ? raw.substring(raw.indexOf(':') + 1).trim()
        : raw.trim();
    final String inner = RegExp(r'^Promise<(.+)>$').firstMatch(type)?.group(1) ?? type;
    if (inner.contains('{')) return 'uses an object type Dart cannot name';
    if (_topHas(inner, '|') || _topHas(inner, '&')) {
      return 'uses a union or an intersection Dart cannot name';
    }
    if (_dart(inner) == null) return 'uses $inner, which Dart has no type for';
  }
  return null;
}

/// The Dart type for a TypeScript type, or null when there is none.
String? _dart(String ts) {
  final String t = ts.trim();
  switch (t) {
    case 'string':
      return 'String';
    case 'number':
      return 'num';
    case 'boolean':
      return 'bool';
    case 'void':
    case 'undefined':
      return 'void';
    case 'any':
    case 'unknown':
      return 'Object?';
    case 'null':
      return 'Null';
  }
  if (t.endsWith('[]')) {
    final String? inner = _dart(t.substring(0, t.length - 2));
    return inner == null ? null : 'List<$inner>';
  }
  final RegExpMatch? array = RegExp(r'^(?:Readonly)?Array<(.+)>$').firstMatch(t);
  if (array != null) {
    final String? inner = _dart(array.group(1)!);
    return inner == null ? null : 'List<$inner>';
  }
  final RegExpMatch? record =
      RegExp(r'^Record<\s*string\s*,\s*(.+)>$').firstMatch(t);
  if (record != null) {
    final String? inner = _dart(record.group(1)!);
    return inner == null ? null : 'Map<String, $inner>';
  }
  return null;
}

bool _topHas(String text, String char) {
  int depth = 0;
  for (int i = 0; i < text.length; i++) {
    final String c = text[i];
    if ('<([{'.contains(c)) depth++;
    if ('>)]}'.contains(c)) depth--;
    if (depth == 0 && c == char) return true;
  }
  return false;
}

List<String> _splitTop(String text) {
  final List<String> out = <String>[];
  int depth = 0;
  int start = 0;
  for (int i = 0; i < text.length; i++) {
    final String c = text[i];
    if ('<([{'.contains(c)) depth++;
    if ('>)]}'.contains(c)) depth--;
    if (depth == 0 && c == ',') {
      out.add(text.substring(start, i));
      start = i + 1;
    }
  }
  out.add(text.substring(start));
  return out.where((String s) => s.trim().isNotEmpty).toList();
}

String _withoutComments(String code, {bool keepJsDoc = false}) {
  final StringBuffer out = StringBuffer();
  int i = 0;
  while (i < code.length) {
    if (code.startsWith('/**', i) && keepJsDoc) {
      final int end = code.indexOf('*/', i);
      final int stop = end < 0 ? code.length : end + 2;
      out.write(code.substring(i, stop));
      i = stop;
      continue;
    }
    if (code.startsWith('/*', i)) {
      final int end = code.indexOf('*/', i + 2);
      i = end < 0 ? code.length : end + 2;
      continue;
    }
    if (code.startsWith('//', i)) {
      final int end = code.indexOf('\n', i);
      i = end < 0 ? code.length : end;
      continue;
    }
    out.write(code[i]);
    i++;
  }
  return out.toString();
}
