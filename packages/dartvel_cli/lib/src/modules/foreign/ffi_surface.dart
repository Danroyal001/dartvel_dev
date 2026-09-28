/// What a C library or a Rust crate offers across the C ABI.
///
/// C and Rust are one binding kind, `DVFfiBinding`: both reach Dart across
/// the C ABI, so both are read into the same [DVFfiSurface] -- functions
/// with their native signature and the Dart operation that forwards to
/// them. C is read from its headers, Rust from its `extern "C"` functions,
/// both lexically and deterministically.
///
/// Values cross by copy: integers, floating point and booleans. A string
/// crosses in only, as a `const char *` the module allocates for the call
/// and frees after it. Every other pointer -- a returned `char *`, an out
/// parameter, a buffer -- has an owner the signature does not name, and a
/// generator that guessed would ship a leak or a use-after-free. Those are
/// left out with DV-BIND-003, which is the specification's answer to
/// ambiguous ownership: an error, never a default.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'dart_surface.dart';

/// One native function and the Dart operation that calls it.
class DVFfiFunction {
  const DVFfiFunction({
    required this.name,
    required this.nativeSignature,
    required this.operation,
    required this.stringParams,
  });

  /// The symbol.
  final String name;

  /// The `NativeFunction` type argument: `Int32 Function(Int32, Int32)`.
  final String nativeSignature;

  /// The operation a module exposes, typed in Dart.
  final DVModuleOperation operation;

  /// The parameters passed as a `const char *`, converted per call.
  final Set<String> stringParams;
}

/// The functions a native source exports, and the sources that build it.
class DVFfiSurface {
  const DVFfiSurface({
    required this.language,
    required this.name,
    required this.version,
    required this.directory,
    required this.functions,
    required this.skipped,
    this.sources = const <String>[],
    this.headers = const <String>[],
  });

  /// `c` or `rust`.
  final String language;
  final String name;
  final String version;
  final String directory;
  final List<DVFfiFunction> functions;
  final Map<String, String> skipped;

  /// C sources to compile, relative to [directory].
  final List<String> sources;

  /// Headers read, relative to [directory].
  final List<String> headers;
}

/// A native type: its `dart:ffi` name and the Dart type it arrives as.
typedef _Native = (String ffi, String dart);

const Map<String, _Native> _cTypes = <String, _Native>{
  'void': ('Void', 'void'),
  'bool': ('Bool', 'bool'),
  '_Bool': ('Bool', 'bool'),
  'char': ('Int8', 'int'),
  'signed char': ('Int8', 'int'),
  'unsigned char': ('Uint8', 'int'),
  'short': ('Short', 'int'),
  'unsigned short': ('UnsignedShort', 'int'),
  'int': ('Int', 'int'),
  'unsigned int': ('UnsignedInt', 'int'),
  'unsigned': ('UnsignedInt', 'int'),
  'long': ('Long', 'int'),
  'unsigned long': ('UnsignedLong', 'int'),
  'long long': ('LongLong', 'int'),
  'unsigned long long': ('UnsignedLongLong', 'int'),
  'int8_t': ('Int8', 'int'),
  'int16_t': ('Int16', 'int'),
  'int32_t': ('Int32', 'int'),
  'int64_t': ('Int64', 'int'),
  'uint8_t': ('Uint8', 'int'),
  'uint16_t': ('Uint16', 'int'),
  'uint32_t': ('Uint32', 'int'),
  'uint64_t': ('Uint64', 'int'),
  'size_t': ('Size', 'int'),
  'intptr_t': ('IntPtr', 'int'),
  'float': ('Float', 'double'),
  'double': ('Double', 'double'),
};

const Map<String, _Native> _rustTypes = <String, _Native>{
  'bool': ('Bool', 'bool'),
  'i8': ('Int8', 'int'),
  'i16': ('Int16', 'int'),
  'i32': ('Int32', 'int'),
  'i64': ('Int64', 'int'),
  'u8': ('Uint8', 'int'),
  'u16': ('Uint16', 'int'),
  'u32': ('Uint32', 'int'),
  'u64': ('Uint64', 'int'),
  'isize': ('IntPtr', 'int'),
  'usize': ('Size', 'int'),
  'f32': ('Float', 'double'),
  'f64': ('Double', 'double'),
};

/// Reads the C library at [dir]: every header's prototypes, and every `.c`
/// file as a source to build.
DVFfiSurface dvScanC(String dir) {
  final Directory root = Directory(dir);
  final List<String> headers = <String>[];
  final List<String> sources = <String>[];
  for (final FileSystemEntity e in root.listSync(recursive: true)) {
    if (e is! File) continue;
    final String rel = p.relative(e.path, from: dir).replaceAll('\\', '/');
    if (rel.split('/').any((String s) => s.startsWith('.'))) continue;
    if (rel.endsWith('.h')) headers.add(rel);
    if (rel.endsWith('.c')) sources.add(rel);
  }
  headers.sort();
  sources.sort();

  final List<DVFfiFunction> functions = <DVFfiFunction>[];
  final Map<String, String> skipped = <String, String>{};
  for (final String header in headers) {
    final String text = File(p.join(dir, header)).readAsStringSync();
    final String code = text
        .replaceAll(RegExp(r'^\s*#.*$', multiLine: true), '')
        .replaceAll(RegExp(r'//[^\n]*'), '')
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
    final String flat = code.replaceAll(RegExp(r'\{[^{}]*\}'), ';');
    final RegExp proto = RegExp(
        r'(?:/\*\*?([\s\S]*?)\*/\s*)?(?:^|;|\})\s*((?:extern\s+)?(?:static\s+)?(?:inline\s+)?(?:const\s+)?[A-Za-z_][\w\s\*]*?)\b([A-Za-z_]\w*)\s*\(([^()]*)\)\s*;',
        multiLine: true);
    for (final RegExpMatch m in proto.allMatches(';$flat')) {
      final String head = m.group(2)!.trim();
      final String fn = m.group(3)!;
      if (head.contains('static') || head.contains('inline')) continue;
      if (functions.any((DVFfiFunction f) => f.name == fn)) continue;
      final String returns = head.replaceFirst(RegExp(r'^extern\s+'), '').trim();
      final String doc = (m.group(1) ?? '').replaceAll(RegExp(r'\s*\*\s*'), ' ').trim();
      final Object result = _function(
        fn,
        returns,
        m.group(4)!.trim() == 'void' ? '' : m.group(4)!,
        doc,
        _cType,
        (String param) {
          final String t = param.trim();
          final RegExpMatch? named =
              RegExp(r'^(.*?[\s\*])([A-Za-z_]\w*)$').firstMatch(t);
          return named == null
              ? (t, 'arg')
              : (named.group(1)!.trim(), named.group(2)!);
        },
      );
      if (result is DVFfiFunction) {
        functions.add(result);
      } else {
        skipped[fn] = result as String;
      }
    }
  }
  return _finish('c', p.basename(dir), '0.0.0', dir, functions, skipped,
      sources: sources, headers: headers);
}

/// Reads the crate at [dir]: `#[no_mangle] pub extern "C" fn` in src/.
DVFfiSurface dvScanRust(String dir) {
  final File cargo = File(p.join(dir, 'Cargo.toml'));
  if (!cargo.existsSync()) {
    throw DVDartSurfaceRefused('$dir has no Cargo.toml, so it is not a crate.');
  }
  final String manifest = cargo.readAsStringSync();
  final String name = RegExp(r'^name\s*=\s*"([^"]+)"', multiLine: true)
          .firstMatch(manifest)
          ?.group(1) ??
      p.basename(dir);
  final String version = RegExp(r'^version\s*=\s*"([^"]+)"', multiLine: true)
          .firstMatch(manifest)
          ?.group(1) ??
      '0.0.0';
  final List<DVFfiFunction> functions = <DVFfiFunction>[];
  final Map<String, String> skipped = <String, String>{};
  final Directory src = Directory(p.join(dir, 'src'));
  final List<File> files = src.existsSync()
      ? (src.listSync(recursive: true).whereType<File>()
          .where((File f) => f.path.endsWith('.rs'))
          .toList()
        ..sort((File a, File b) => a.path.compareTo(b.path)))
      : <File>[];
  final RegExp fnDecl = RegExp(
      r'((?:[ \t]*///[^\n]*\n)*)[ \t]*#\[(?:unsafe\()?no_mangle\)?\]\s*pub\s+(?:unsafe\s+)?extern\s+"C"\s+fn\s+([A-Za-z_]\w*)\s*\(([^)]*)\)\s*(?:->\s*([^{]+?))?\s*\{');
  for (final File file in files) {
    for (final RegExpMatch m in fnDecl.allMatches(file.readAsStringSync())) {
      final String fn = m.group(2)!;
      final String doc = m
          .group(1)!
          .split('\n')
          .map((String l) => l.replaceFirst(RegExp(r'^\s*///\s?'), '').trim())
          .where((String l) => l.isNotEmpty)
          .join(' ');
      final Object result = _function(
        fn,
        (m.group(4) ?? '()').trim(),
        m.group(3)!,
        doc,
        _rustType,
        (String param) {
          final int colon = param.indexOf(':');
          return (param.substring(colon + 1).trim(),
              param.substring(0, colon).trim().replaceFirst(RegExp(r'^mut\s+'), ''));
        },
      );
      if (result is DVFfiFunction) {
        functions.add(result);
      } else {
        skipped[fn] = result as String;
      }
    }
  }
  return _finish('rust', name, version, dir, functions, skipped);
}

DVFfiSurface _finish(
  String language,
  String name,
  String version,
  String dir,
  List<DVFfiFunction> functions,
  Map<String, String> skipped, {
  List<String> sources = const <String>[],
  List<String> headers = const <String>[],
}) {
  if (functions.isEmpty) {
    throw DVDartSurfaceRefused('$name exports no function a module can call '
        'across the C ABI (DV-MODULE-010)'
        '${skipped.isEmpty ? '' : ': ${skipped.entries.map((MapEntry<String, String> e) => '${e.key} ${e.value}').join('; ')}'}.');
  }
  functions.sort((DVFfiFunction a, DVFfiFunction b) => a.name.compareTo(b.name));
  return DVFfiSurface(
    language: language,
    name: name,
    version: version,
    directory: dir,
    functions: functions,
    skipped: skipped,
    sources: sources,
    headers: headers,
  );
}

/// The kind of a value crossing: a copy, a string in, or a pointer whose
/// owner nobody named.
sealed class _Crossing {}

class _Value extends _Crossing {
  _Value(this.native);
  final _Native native;
}

class _StringIn extends _Crossing {}

class _Unowned extends _Crossing {
  _Unowned(this.type);
  final String type;
}

_Crossing? _cType(String raw) {
  final String t = raw.replaceAll(RegExp(r'\s+'), ' ').replaceAll(' *', '*').trim();
  if (RegExp(r'^const (char|signed char)\*$').hasMatch(t) ||
      t == 'char const*') {
    return _StringIn();
  }
  if (t.contains('*')) return _Unowned(t);
  final _Native? n = _cTypes[t.replaceFirst(RegExp(r'^const '), '')];
  return n == null ? null : _Value(n);
}

_Crossing? _rustType(String raw) {
  final String t = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t == '()') return _Value(('Void', 'void'));
  if (RegExp(r'^\*const (std::os::raw::|core::ffi::|std::ffi::)?c_char$').hasMatch(t)) {
    return _StringIn();
  }
  if (t.startsWith('*') || t.startsWith('&')) return _Unowned(t);
  final _Native? n = _rustTypes[t];
  return n == null ? null : _Value(n);
}

/// A [DVFfiFunction], or the reason there is none.
Object _function(
  String name,
  String returns,
  String params,
  String doc,
  _Crossing? Function(String) type,
  (String, String) Function(String) split,
) {
  final _Crossing? result = type(returns);
  if (result == null) return 'returns $returns, which has no Dart type here';
  if (result is _Unowned || result is _StringIn) {
    return 'returns ${result is _Unowned ? result.type : 'a char pointer'}, '
        'and nothing says who frees it (DV-BIND-003)';
  }
  final List<String> nativeParams = <String>[];
  final List<DVModuleParam> dartParams = <DVModuleParam>[];
  final Set<String> strings = <String>{};
  int i = 0;
  for (final String raw in params.split(',')) {
    if (raw.trim().isEmpty) continue;
    final (String t, String n) = split(raw);
    final String paramName = n == 'arg' ? 'arg${i++}' : n;
    final _Crossing? c = type(t);
    if (c == null) return 'takes $t, which has no Dart type here';
    if (c is _Unowned) {
      return 'takes ${c.type}, and nothing says who owns it (DV-BIND-003)';
    }
    if (c is _StringIn) {
      nativeParams.add('Pointer<Utf8>');
      dartParams.add(DVModuleParam(name: paramName, type: 'String'));
      strings.add(paramName);
    } else {
      final _Native n0 = (c as _Value).native;
      nativeParams.add(n0.$1);
      dartParams.add(DVModuleParam(name: paramName, type: n0.$2));
    }
  }
  final _Native r = (result as _Value).native;
  return DVFfiFunction(
    name: name,
    nativeSignature: '${r.$1} Function(${nativeParams.join(', ')})',
    operation: DVModuleOperation(
      name: _camel(name),
      returnType: r.$2,
      params: dartParams,
      doc: doc,
    ),
    stringParams: strings,
  );
}

/// `mk_add` as a Dart member: `mkAdd`.
String _camel(String symbol) {
  final List<String> parts =
      symbol.split('_').where((String s) => s.isNotEmpty).toList();
  if (parts.isEmpty) return symbol;
  return parts.first +
      parts.skip(1).map((String s) => s[0].toUpperCase() + s.substring(1)).join();
}
