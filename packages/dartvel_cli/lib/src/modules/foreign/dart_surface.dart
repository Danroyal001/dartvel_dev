/// The public surface of a plain Dart package, read from its source.
///
/// A Dart package added as a module is wrapped rather than rewritten: the
/// module calls the package, and what the module exposes is the part of the
/// package's public API that can cross every environment the module is
/// called from. That part is found here, lexically -- the CLI carries no
/// analyzer, and the declarations a wrapper needs are the top-level function
/// signatures of the package's own library and the files it exports, which a
/// scanner that knows Dart's comments, strings and brackets reads exactly.
///
/// What is left out is said, with the reason, rather than dropped: a
/// generic function, a parameter that is itself a function, a type from the
/// package that the environments without the package could not name. The
/// generated README lists each, so a reader looking for `parse` learns why
/// it is not on `DV.Modules.<id>` and where to reach it instead.
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// One parameter of an operation.
class DVModuleParam {
  const DVModuleParam({
    required this.name,
    required this.type,
    this.named = false,
    this.required = true,
    this.defaultValue,
  });

  final String name;

  /// The type as written, whitespace removed: `List<String>?`.
  final String type;

  /// Inside `{}` in the declaration.
  final bool named;

  /// A positional parameter outside `[]`, or a named one marked `required`.
  final bool required;

  /// The default as written, when there is one. Only literals are kept: a
  /// default that names something from the package cannot be written where
  /// the package is not.
  final String? defaultValue;

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'type': type,
        'named': named,
        'required': required,
        if (defaultValue != null) 'default': defaultValue,
      };
}

/// One call a module exposes.
class DVModuleOperation {
  const DVModuleOperation({
    required this.name,
    required this.returnType,
    required this.params,
    this.doc = '',
  });

  final String name;
  final String returnType;
  final List<DVModuleParam> params;

  /// The declaration's own doc comment, without the slashes.
  final String doc;

  /// Whether the call already answers later: a `Future` or a `Stream`.
  bool get isAsync =>
      returnType.startsWith('Future<') ||
      returnType == 'Future' ||
      returnType.startsWith('Stream<');

  /// The parameter list as a declaration writes it.
  String get parameterList {
    final List<String> positional = <String>[];
    final List<String> optional = <String>[];
    final List<String> named = <String>[];
    for (final DVModuleParam param in params) {
      final String withDefault = param.defaultValue == null
          ? '${param.type} ${param.name}'
          : '${param.type} ${param.name} = ${param.defaultValue}';
      if (param.named) {
        named.add(param.required ? 'required ${param.type} ${param.name}' : withDefault);
      } else if (param.required) {
        positional.add('${param.type} ${param.name}');
      } else {
        optional.add(withDefault);
      }
    }
    return <String>[
      ...positional,
      if (optional.isNotEmpty) '[${optional.join(', ')}]',
      if (named.isNotEmpty) '{${named.join(', ')}}',
    ].join(', ');
  }

  /// The arguments a forwarding call passes.
  String get argumentList => <String>[
        for (final DVModuleParam param in params)
          param.named ? '${param.name}: ${param.name}' : param.name,
      ].join(', ');

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'returns': returnType,
        'params': <Object?>[for (final DVModuleParam p in params) p.toJson()],
      };
}

/// What a package needs from the platform it runs on, read from the
/// libraries its own files import unconditionally.
class DVDartPlatformNeeds {
  const DVDartPlatformNeeds({
    this.io = false,
    this.ffi = false,
    this.browser = false,
    this.flutter = false,
  });

  /// `dart:io` or `dart:isolate`: not in a browser.
  final bool io;

  /// `dart:ffi`: not in a browser.
  final bool ffi;

  /// `dart:html`, `dart:js_interop`, `dart:js` or `package:web`: only in a
  /// browser.
  final bool browser;

  /// `package:flutter` or `dart:ui`: not on the backend, which has no
  /// Flutter engine.
  final bool flutter;

  /// Whether a client built for a device can run it.
  bool get native => !browser;

  /// Whether a browser can run it.
  bool get web => !io && !ffi;

  /// Whether the backend can run it.
  bool get backend => !flutter && !browser;

  List<String> get reasons => <String>[
        if (io) 'imports dart:io',
        if (ffi) 'imports dart:ffi',
        if (browser) 'imports a browser library',
        if (flutter) 'imports Flutter',
      ];
}

/// The package's surface: what can be exposed, what cannot and why, and what
/// it needs from a platform.
class DVDartSurface {
  const DVDartSurface({
    required this.packageName,
    required this.version,
    required this.library,
    required this.operations,
    required this.skipped,
    required this.needs,
  });

  final String packageName;
  final String version;

  /// The library the operations come from: `package:<name>/<name>.dart`.
  final String library;

  final List<DVModuleOperation> operations;

  /// Public functions that are not exposed, by name, with the reason.
  final Map<String, String> skipped;

  final DVDartPlatformNeeds needs;
}

/// Thrown when a directory is not a Dart package this can read.
class DVDartSurfaceRefused implements Exception {
  const DVDartSurfaceRefused(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The types every environment can name without importing the package.
const Set<String> _portableLeaves = <String>{
  'void',
  'dynamic',
  'Object',
  'bool',
  'int',
  'double',
  'num',
  'String',
  'DateTime',
  'Duration',
  'Uri',
  'BigInt',
  'Null',
  'Uint8List',
};

const Set<String> _portableGenerics = <String>{
  'List',
  'Iterable',
  'Set',
  'Map',
  'Future',
  'Stream',
};

/// Whether [type] is made only of types every environment has.
bool dvIsPortableType(String type) {
  String t = type.replaceAll(' ', '');
  if (t.endsWith('?')) t = t.substring(0, t.length - 1);
  final int lt = t.indexOf('<');
  if (lt < 0) return _portableLeaves.contains(t);
  if (!t.endsWith('>')) return false;
  final String head = t.substring(0, lt);
  if (!_portableGenerics.contains(head)) return false;
  final List<String> args = _splitTop(t.substring(lt + 1, t.length - 1), ',');
  if (args.isEmpty) return false;
  return args.every(dvIsPortableType);
}

/// Reads the public surface of the Dart package at [dir].
DVDartSurface dvScanDartPackage(String dir) {
  final File pubspec = File(p.join(dir, 'pubspec.yaml'));
  if (!pubspec.existsSync()) {
    throw DVDartSurfaceRefused('$dir has no pubspec.yaml, so it is not a '
        'Dart package.');
  }
  final Object? doc = loadYaml(pubspec.readAsStringSync());
  if (doc is! Map || doc['name'] is! String) {
    throw DVDartSurfaceRefused('$dir/pubspec.yaml names no package.');
  }
  final String name = doc['name'] as String;
  final String version = '${doc['version'] ?? '0.0.0'}';
  final File entry = File(p.join(dir, 'lib', '$name.dart'));
  if (!entry.existsSync()) {
    throw DVDartSurfaceRefused('$name has no lib/$name.dart, the library a '
        'package is imported by, so there is no public surface to wrap '
        '(DV-MODULE-010).');
  }

  final List<DVModuleOperation> operations = <DVModuleOperation>[];
  final Map<String, String> skipped = <String, String>{};
  final Set<String> seen = <String>{};
  _collect(entry.path, p.join(dir, 'lib'), name, null, operations, skipped,
      seen, <String>{});
  operations.sort((DVModuleOperation a, DVModuleOperation b) =>
      a.name.compareTo(b.name));

  return DVDartSurface(
    packageName: name,
    version: version,
    library: 'package:$name/$name.dart',
    operations: operations,
    skipped: Map<String, String>.fromEntries(skipped.entries.toList()
      ..sort((MapEntry<String, String> a, MapEntry<String, String> b) =>
          a.key.compareTo(b.key))),
    needs: _needs(p.join(dir, 'lib')),
  );
}

/// A combinator on an export: which names pass.
class _Filter {
  const _Filter({this.show, this.hide});
  final Set<String>? show;
  final Set<String>? hide;
  bool passes(String name) =>
      (show == null || show!.contains(name)) &&
      (hide == null || !hide!.contains(name));
  _Filter and(_Filter? inner) => inner == null
      ? this
      : _Filter(
          show: show == null
              ? inner.show
              : (inner.show == null ? show : show!.intersection(inner.show!)),
          hide: <String>{...?hide, ...?inner.hide},
        );
}

void _collect(
  String file,
  String libDir,
  String packageName,
  _Filter? filter,
  List<DVModuleOperation> operations,
  Map<String, String> skipped,
  Set<String> seen,
  Set<String> visiting,
) {
  final String key = '${p.normalize(file)}|${filter?.show}|${filter?.hide}';
  if (!visiting.add(key)) return;
  final String source = File(file).readAsStringSync();
  final String code = _stripComments(source, keepDocs: true);

  for (final _Declaration declaration in _declarations(code)) {
    final String name = declaration.name;
    if (name.startsWith('_') || seen.contains(name)) continue;
    if (filter != null && !filter.passes(name)) continue;
    seen.add(name);
    final String? why = declaration.skip;
    if (why != null) {
      skipped[name] = why;
      continue;
    }
    final DVModuleOperation op = declaration.operation!;
    final List<String> types = <String>[
      op.returnType,
      for (final DVModuleParam param in op.params) param.type,
    ];
    final String? foreign = types.cast<String?>().firstWhere(
        (String? t) => !dvIsPortableType(t!),
        orElse: () => null);
    if (foreign != null) {
      skipped[name] = 'uses $foreign, which only the package itself can '
          'name; import package:$packageName to reach it';
      continue;
    }
    if (op.params.any((DVModuleParam p) =>
        p.defaultValue != null && !_isLiteral(p.defaultValue!))) {
      skipped[name] = 'has a default value that is not a literal';
      continue;
    }
    operations.add(op);
  }

  // Exports, in the order written: a name the entry declares itself wins
  // over one an export brings in, as it does in Dart.
  for (final RegExpMatch match in _exportDirective.allMatches(code)) {
    final String uri = match.group(1)!;
    final String? target = _resolve(uri, file, libDir, packageName);
    if (target == null || !File(target).existsSync()) continue;
    final _Filter here = _Filter(
      show: _names(match.group(2), 'show'),
      hide: _names(match.group(2), 'hide'),
    );
    _collect(target, libDir, packageName,
        filter == null ? here : filter.and(here), operations, skipped, seen,
        visiting);
  }
}

final RegExp _exportDirective =
    RegExp(r'''export\s+['"]([^'"]+)['"]([^;]*);''');

Set<String>? _names(String? combinators, String keyword) {
  if (combinators == null) return null;
  final RegExpMatch? m =
      RegExp('\\b$keyword\\s+([A-Za-z0-9_\$,\\s]+?)(?=\\b(?:show|hide)\\b|\$)')
          .firstMatch(combinators.trim());
  if (m == null) return null;
  return m
      .group(1)!
      .split(',')
      .map((String s) => s.trim())
      .where((String s) => s.isNotEmpty)
      .toSet();
}

String? _resolve(String uri, String from, String libDir, String packageName) {
  if (uri.startsWith('dart:')) return null;
  if (uri.startsWith('package:')) {
    final String prefix = 'package:$packageName/';
    if (!uri.startsWith(prefix)) return null;
    return p.join(libDir, uri.substring(prefix.length));
  }
  return p.normalize(p.join(p.dirname(from), uri));
}

/// Whether a default value can be written anywhere: a number, a string, a
/// boolean, null, or an empty const collection.
bool _isLiteral(String value) {
  final String v = value.trim();
  return RegExp(r'^-?\d+(\.\d+)?$').hasMatch(v) ||
      RegExp(r'''^(['"]).*\1$''').hasMatch(v) ||
      v == 'true' ||
      v == 'false' ||
      v == 'null' ||
      RegExp(r'^(const\s*)?(<[^>]*>\s*)?(\[\s*\]|\{\s*\})$').hasMatch(v);
}

/// What the package's own files import unconditionally.
DVDartPlatformNeeds _needs(String libDir) {
  bool io = false, ffi = false, browser = false, flutter = false;
  final Directory lib = Directory(libDir);
  for (final FileSystemEntity entity in lib.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final String code = _stripComments(entity.readAsStringSync());
    for (final RegExpMatch m in RegExp(
            r'''(?:import|export)\s+['"]([^'"]+)['"]([^;]*);''')
        .allMatches(code)) {
      // A conditional import picks a library per platform: the package has
      // arranged for each, so none of them is a requirement.
      if (RegExp(r'\bif\s*\(').hasMatch(m.group(2)!)) continue;
      final String uri = m.group(1)!;
      if (uri == 'dart:io' || uri == 'dart:isolate') io = true;
      if (uri == 'dart:ffi') ffi = true;
      if (uri == 'dart:html' ||
          uri == 'dart:js_interop' ||
          uri == 'dart:js' ||
          uri == 'dart:js_util' ||
          uri.startsWith('package:web/')) {
        browser = true;
      }
      if (uri == 'dart:ui' || uri.startsWith('package:flutter/')) {
        flutter = true;
      }
    }
  }
  return DVDartPlatformNeeds(io: io, ffi: ffi, browser: browser, flutter: flutter);
}

/// A top-level declaration: a function the module could expose, or the
/// reason it cannot.
class _Declaration {
  _Declaration(this.name, {this.operation, this.skip});
  final String name;
  final DVModuleOperation? operation;
  final String? skip;
}

/// Every top-level function declaration in [code], in order.
///
/// Classes, mixins, enums, extensions and typedefs are stepped over whole;
/// variables, getters and setters are not functions; what is left is a
/// header followed by a body, `=>`, or `;` for an external function.
List<_Declaration> _declarations(String code) {
  final List<_Declaration> out = <_Declaration>[];
  final String masked = _maskStrings(code);
  int i = 0;
  final StringBuffer header = StringBuffer();
  int headerStart = 0;
  int paren = 0;
  String doc = '';
  while (i < masked.length) {
    final String c = masked[i];
    if (header.isEmpty && RegExp(r'\s').hasMatch(c)) {
      i++;
      continue;
    }
    if (header.isEmpty) {
      headerStart = i;
      // A doc comment kept by the stripper sits before the declaration.
      if (masked.startsWith('///', i)) {
        final int end = masked.indexOf('\n', i);
        final String line = masked.substring(i + 3, end < 0 ? masked.length : end).trim();
        doc = doc.isEmpty ? line : '$doc $line';
        i = end < 0 ? masked.length : end + 1;
        continue;
      }
      final Match? kw = RegExp(
              r'(?:(?:abstract|base|final|interface|sealed|mixin)\s+)*(class|mixin|enum|extension|typedef)\b')
          .matchAsPrefix(masked, i);
      if (kw != null) {
        i = _skipDeclaration(masked, i);
        doc = '';
        continue;
      }
      if (masked.startsWith('import', i) ||
          masked.startsWith('export', i) ||
          masked.startsWith('part', i) ||
          masked.startsWith('library', i)) {
        final int end = masked.indexOf(';', i);
        i = end < 0 ? masked.length : end + 1;
        doc = '';
        continue;
      }
    }
    if (c == '(') paren++;
    if (c == ')') paren--;
    if (paren == 0 && c == '{') {
      out.addAll(_readHeader(
          code.substring(headerStart, i).trim(), doc));
      i = _matching(masked, i) + 1;
      header.clear();
      doc = '';
      continue;
    }
    if (paren == 0 && masked.startsWith('=>', i)) {
      out.addAll(_readHeader(
          code.substring(headerStart, i).trim(), doc));
      i = _endOfStatement(masked, i) + 1;
      header.clear();
      doc = '';
      continue;
    }
    if (paren == 0 && c == ';') {
      final String h = code.substring(headerStart, i).trim();
      if (RegExp(r'^(?:@\S+\s+)*external\b').hasMatch(h)) {
        out.addAll(_readHeader(h, doc));
      }
      i++;
      header.clear();
      doc = '';
      continue;
    }
    header.write(c);
    i++;
  }
  return out;
}

final RegExp _headerShape = RegExp(
  r'^(?:@[\w.]+(?:\([^)]*\))?\s+)*(?:external\s+)?(.*?)\s*\b([A-Za-z_$][\w$]*)\s*(<[^()]*>)?\s*\(([\s\S]*)\)\s*(async\*?|sync\*)?$',
);

Iterable<_Declaration> _readHeader(String header, String doc) sync* {
  final String h = header.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (RegExp(r'(^|\s)(get|set|operator)\s').hasMatch(h)) return;
  final RegExpMatch? m = _headerShape.firstMatch(h);
  if (m == null) return;
  final String name = m.group(2)!;
  if (name == 'main') return;
  final String returnType =
      m.group(1)!.isEmpty ? 'dynamic' : m.group(1)!.replaceAll(' ', '');
  if (RegExp(r'^(var|final|const|late|static)\b').hasMatch(returnType)) return;
  if (m.group(3) != null) {
    yield _Declaration(name, skip: 'is generic');
    return;
  }
  final String? async = m.group(5);
  if (async == 'sync*' || async == 'async*') {
    // A generator: the declared type is already Iterable or Stream.
  }
  final List<DVModuleParam>? params = _readParams(m.group(4)!);
  if (params == null) {
    yield _Declaration(name,
        skip: 'takes a function, a record or a field parameter');
    return;
  }
  yield _Declaration(
    name,
    operation: DVModuleOperation(
      name: name,
      returnType: returnType,
      params: params,
      doc: doc,
    ),
  );
}

/// The parameters in [list], or null when one is a kind a wrapper cannot
/// forward: a function type, a record, `this.` or `super.`.
List<DVModuleParam>? _readParams(String list) {
  final String body = list.trim();
  if (body.isEmpty) return const <DVModuleParam>[];
  final List<DVModuleParam> out = <DVModuleParam>[];
  // Split into the three sections: positional, [optional], {named}.
  String positional = body;
  String optional = '';
  String named = '';
  final int bracket = _topIndex(body, '[');
  final int brace = _topIndex(body, '{');
  if (bracket >= 0) {
    positional = body.substring(0, bracket);
    optional = body.substring(bracket + 1, body.lastIndexOf(']'));
  } else if (brace >= 0) {
    positional = body.substring(0, brace);
    named = body.substring(brace + 1, body.lastIndexOf('}'));
  }
  for (final (String part, bool isNamed, bool isOptional) in <(String, bool, bool)>[
    (positional, false, false),
    (optional, false, true),
    (named, true, false),
  ]) {
    for (final String raw in _splitTop(part, ',')) {
      final String param = raw.trim();
      if (param.isEmpty) continue;
      if (param.contains('Function') ||
          param.contains('(') ||
          RegExp(r'\b(this|super)\.').hasMatch(param)) {
        return null;
      }
      final bool marked = param.startsWith('required ');
      final String rest = param.replaceFirst(RegExp(r'^(required|covariant)\s+'), '');
      final int eq = _topIndex(rest, '=');
      final String decl = (eq < 0 ? rest : rest.substring(0, eq)).trim();
      final String? value = eq < 0 ? null : rest.substring(eq + 1).trim();
      final RegExpMatch? d = RegExp(r'^(.*?)\s*\b([A-Za-z_$][\w$]*)$').firstMatch(decl);
      if (d == null) return null;
      final String type = d.group(1)!.replaceAll(' ', '');
      out.add(DVModuleParam(
        name: d.group(2)!,
        type: type.isEmpty ? 'dynamic' : type,
        named: isNamed,
        required: isNamed ? marked : !isOptional,
        defaultValue: value,
      ));
    }
  }
  return out;
}

/// [text] split on [separator] where it is not nested in brackets.
List<String> _splitTop(String text, String separator) {
  final List<String> out = <String>[];
  int depth = 0;
  int start = 0;
  for (int i = 0; i < text.length; i++) {
    final String c = text[i];
    if ('<([{'.contains(c)) depth++;
    if ('>)]}'.contains(c)) depth--;
    if (depth == 0 && c == separator) {
      out.add(text.substring(start, i));
      start = i + 1;
    }
  }
  out.add(text.substring(start));
  return out.where((String s) => s.trim().isNotEmpty).toList();
}

/// The first [char] in [text] not nested in brackets, or -1.
int _topIndex(String text, String char) {
  int depth = 0;
  for (int i = 0; i < text.length; i++) {
    final String c = text[i];
    if (c == char && depth == 0) return i;
    if ('<([{'.contains(c)) depth++;
    if ('>)]}'.contains(c)) depth--;
  }
  return -1;
}

int _matching(String text, int open) {
  final String o = text[open];
  final String close = o == '{' ? '}' : (o == '(' ? ')' : ']');
  int depth = 0;
  for (int i = open; i < text.length; i++) {
    if (text[i] == o) depth++;
    if (text[i] == close) {
      depth--;
      if (depth == 0) return i;
    }
  }
  return text.length - 1;
}

int _endOfStatement(String text, int from) {
  int depth = 0;
  for (int i = from; i < text.length; i++) {
    final String c = text[i];
    if ('([{'.contains(c)) depth++;
    if (')]}'.contains(c)) depth--;
    if (c == ';' && depth == 0) return i;
  }
  return text.length - 1;
}

/// Steps over a class, mixin, enum, extension or typedef starting at [i].
int _skipDeclaration(String text, int i) {
  int paren = 0;
  for (int j = i; j < text.length; j++) {
    final String c = text[j];
    if (c == '(') paren++;
    if (c == ')') paren--;
    if (paren == 0 && c == ';') return j + 1;
    if (paren == 0 && c == '{') return _matching(text, j) + 1;
  }
  return text.length;
}

/// [code] with every string literal's contents replaced by spaces, so a
/// brace or a semicolon in a string is not read as structure. Lengths are
/// kept, so offsets into the result are offsets into [code].
String _maskStrings(String code) {
  final StringBuffer out = StringBuffer();
  int i = 0;
  while (i < code.length) {
    final String c = code[i];
    if (c == "'" || c == '"') {
      final bool triple = code.startsWith(c * 3, i);
      final String quote = triple ? c * 3 : c;
      final bool raw = i > 0 && code[i - 1] == 'r';
      out.write(quote);
      int j = i + quote.length;
      while (j < code.length && !code.startsWith(quote, j)) {
        if (!raw && code[j] == r'\') {
          out.write('  ');
          j += 2;
          continue;
        }
        out.write(code[j] == '\n' ? '\n' : ' ');
        j++;
      }
      out.write(quote);
      i = j + quote.length;
      continue;
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

/// [code] without comments. Doc comments are kept when [keepDocs], as the
/// line they are on, so a declaration's documentation travels with it.
String _stripComments(String code, {bool keepDocs = false}) {
  final StringBuffer out = StringBuffer();
  int i = 0;
  while (i < code.length) {
    final String c = code[i];
    if (c == "'" || c == '"') {
      final bool triple = code.startsWith(c * 3, i);
      final String quote = triple ? c * 3 : c;
      final bool raw = i > 0 && code[i - 1] == 'r';
      int j = i + quote.length;
      while (j < code.length && !code.startsWith(quote, j)) {
        if (!raw && code[j] == r'\') j++;
        j++;
      }
      out.write(code.substring(i, (j + quote.length).clamp(0, code.length)));
      i = j + quote.length;
      continue;
    }
    if (code.startsWith('//', i)) {
      final int end = code.indexOf('\n', i);
      final String line = code.substring(i, end < 0 ? code.length : end);
      if (keepDocs && line.startsWith('///')) out.write(line);
      i = end < 0 ? code.length : end;
      continue;
    }
    if (code.startsWith('/*', i)) {
      final int end = code.indexOf('*/', i + 2);
      i = end < 0 ? code.length : end + 2;
      continue;
    }
    out.write(c);
    i++;
  }
  return out.toString();
}
