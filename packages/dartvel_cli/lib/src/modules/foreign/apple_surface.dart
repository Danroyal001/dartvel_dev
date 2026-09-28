/// What a Swift package or an Objective-C pod offers across the C ABI.
///
/// Apple sources reach Dart the way C does, as `DVFfiBinding`: Swift and
/// Objective-C both export to the C ABI, the first through `@_cdecl`, the
/// second through a C function wrapping a message send. The module generates
/// those exports itself -- a shim compiled with the package -- so it owns
/// both sides of every value that crosses, and a returned string can have a
/// named owner: the shim copies it with `strdup`, and the Dart side reads
/// the copy and frees it through the shim's own free function. That is the
/// one pointer whose ownership is decided here rather than guessed, which
/// is why a Swift function returning `String` crosses and a C function
/// returning `char *` does not.
///
/// What crosses otherwise: the integer types, `Double`, `Float`, `Bool` and
/// `String` in, from public top-level functions and public static functions
/// of public types. A function that throws, is async, is generic or takes a
/// closure is left out with the reason.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'dart_surface.dart';

/// One function the shim exports.
class DVAppleFunction {
  const DVAppleFunction({
    required this.symbol,
    required this.owner,
    required this.name,
    required this.params,
    required this.returns,
    required this.operation,
  });

  /// The C symbol the shim exports it as.
  final String symbol;

  /// The type it is a static member of, or null for a top-level function.
  final String? owner;

  /// Its own name.
  final String name;

  /// Label (null for `_`), name and type, in order.
  final List<(String?, String, String)> params;

  /// The Swift or Objective-C return type; `Void` for none.
  final String returns;

  final DVModuleOperation operation;
}

class DVAppleSurface {
  const DVAppleSurface({
    required this.language,
    required this.name,
    required this.directory,
    required this.sources,
    required this.functions,
    required this.skipped,
  });

  /// `swift` or `objc`.
  final String language;
  final String name;
  final String directory;

  /// Source files, relative to [directory].
  final List<String> sources;
  final List<DVAppleFunction> functions;
  final Map<String, String> skipped;
}

/// Swift types that cross, with their C-ABI Swift spelling, the dart:ffi
/// type and the Dart type.
const Map<String, (String, String, String)> _swiftTypes =
    <String, (String, String, String)>{
  'Int': ('Int', 'Int64', 'int'),
  'Int8': ('Int8', 'Int8', 'int'),
  'Int16': ('Int16', 'Int16', 'int'),
  'Int32': ('Int32', 'Int32', 'int'),
  'Int64': ('Int64', 'Int64', 'int'),
  'UInt8': ('UInt8', 'Uint8', 'int'),
  'UInt16': ('UInt16', 'Uint16', 'int'),
  'UInt32': ('UInt32', 'Uint32', 'int'),
  'UInt64': ('UInt64', 'Uint64', 'int'),
  'Double': ('Double', 'Double', 'double'),
  'Float': ('Float', 'Float', 'double'),
  'Bool': ('Bool', 'Bool', 'bool'),
  'String': ('UnsafePointer<CChar>', 'Pointer<Utf8>', 'String'),
  'Void': ('Void', 'Void', 'void'),
};

/// The dart:ffi type of a crossing Swift type.
String dvSwiftFfi(String type) => _swiftTypes[type]!.$2;

/// Reads the Swift package at [dir].
DVAppleSurface dvScanSwiftPackage(String dir) {
  final File manifest = File(p.join(dir, 'Package.swift'));
  if (!manifest.existsSync()) {
    throw DVDartSurfaceRefused('$dir has no Package.swift.');
  }
  final String text = manifest.readAsStringSync();
  final String name =
      RegExp(r'name:\s*"([^"]+)"').firstMatch(text)?.group(1) ?? p.basename(dir);
  if (RegExp(r'\.package\s*\(').hasMatch(text)) {
    throw DVDartSurfaceRefused('$name depends on other Swift packages, and the '
        'module compiles the package on its own. A package with dependencies '
        'is not generated yet (DV-MODULE-017).');
  }
  final Directory sources = Directory(p.join(dir, 'Sources'));
  return dvScanSwiftSources(dir, name, <String>[
    for (final FileSystemEntity e in (sources.existsSync() ? sources : Directory(dir))
        .listSync(recursive: true))
      if (e is File && e.path.endsWith('.swift') && p.basename(e.path) != 'Package.swift')
        p.relative(e.path, from: dir).replaceAll('\\', '/'),
  ]..sort());
}

/// Reads the public functions in the Swift [files] under [dir], for a
/// package or a pod named [name].
DVAppleSurface dvScanSwiftSources(String dir, String name, List<String> files) {
  final List<DVAppleFunction> functions = <DVAppleFunction>[];
  final Map<String, String> skipped = <String, String>{};
  final String prefix = 'dv_${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}_';
  for (final String file in files) {
    final String code = _stripSwiftComments(File(p.join(dir, file)).readAsStringSync());
    // Public types, so a static function can be named with its owner.
    final List<(String, int, int)> types = <(String, int, int)>[];
    for (final RegExpMatch t in RegExp(
            r'public\s+(?:final\s+)?(?:enum|struct|class)\s+([A-Za-z_]\w*)[^{]*\{')
        .allMatches(code)) {
      types.add((t.group(1)!, t.end - 1, _matching(code, t.end - 1)));
    }
    for (final RegExpMatch m in RegExp(
            r'public\s+(static\s+)?func\s+([A-Za-z_]\w*)\s*(<[^>]*>)?\s*\(([^)]*)\)\s*((?:async\s*)?(?:throws\s*)?)(?:->\s*([^{\n]+?))?\s*\{')
        .allMatches(code)) {
      final bool isStatic = m.group(1) != null;
      final String fn = m.group(2)!;
      String? owner;
      for (final (String t, int open, int close) in types) {
        if (m.start > open && m.start < close) owner = t;
      }
      if (isStatic != (owner != null)) continue; // an instance method
      final String label = owner == null ? fn : '$owner.$fn';
      if (m.group(3) != null) {
        skipped[label] = 'is generic';
        continue;
      }
      if (m.group(5)!.trim().isNotEmpty) {
        skipped[label] = 'is ${m.group(5)!.trim()}, and neither crosses the '
            'C ABI';
        continue;
      }
      final String returns = (m.group(6) ?? 'Void').trim();
      final List<(String?, String, String)> params = <(String?, String, String)>[];
      String? why;
      for (final String raw in m.group(4)!.split(',')) {
        if (raw.trim().isEmpty) continue;
        final RegExpMatch? pm = RegExp(
                r'^\s*(?:([A-Za-z_]\w*)\s+)?([A-Za-z_]\w*)\s*:\s*([^=]+?)\s*(?:=.*)?$')
            .firstMatch(raw);
        if (pm == null) {
          why = 'has a parameter this cannot read';
          break;
        }
        final String type = pm.group(3)!.trim();
        if (!_swiftTypes.containsKey(type) || type == 'Void') {
          why = 'takes $type, which does not cross the C ABI';
          break;
        }
        final String? l = pm.group(1);
        params.add((l == '_' ? null : (l ?? pm.group(2)), pm.group(2)!, type));
      }
      if (why == null && !_swiftTypes.containsKey(returns)) {
        why = 'returns $returns, which does not cross the C ABI';
      }
      if (why != null) {
        skipped[label] = why;
        continue;
      }
      final String opName = owner == null
          ? fn
          : '${owner[0].toLowerCase()}${owner.substring(1)}'
              '${fn[0].toUpperCase()}${fn.substring(1)}';
      functions.add(DVAppleFunction(
        symbol: '$prefix${_snake(opName)}',
        owner: owner,
        name: fn,
        params: params,
        returns: returns,
        operation: DVModuleOperation(
          name: opName,
          returnType: _swiftTypes[returns]!.$3,
          params: <DVModuleParam>[
            for (final (String? _, String n, String t) in params)
              DVModuleParam(name: n, type: _swiftTypes[t]!.$3),
          ],
          doc: '`$label` in $name.',
        ),
      ));
    }
  }
  if (functions.isEmpty) {
    throw DVDartSurfaceRefused('$name has no public function a module can '
        'export across the C ABI (DV-MODULE-010).');
  }
  functions.sort((DVAppleFunction a, DVAppleFunction b) =>
      a.operation.name.compareTo(b.operation.name));
  return DVAppleSurface(
    language: 'swift',
    name: name,
    directory: dir,
    sources: files,
    functions: functions,
    skipped: skipped,
  );
}

/// The Swift file that exports [surface] to the C ABI, compiled with it.
///
/// A string argument arrives as a C string and is copied into a Swift
/// String for the call. A string answer leaves as a `strdup` copy the Dart
/// side frees with `<prefix>free`, which is this shim's own `free`: the
/// allocator that made it is the one that releases it.
String dvSwiftShim(DVAppleSurface surface, String prefix) {
  final StringBuffer out = StringBuffer()
    ..writeln('// GENERATED by dartvel add. Exports ${surface.name} to the C ABI.')
    ..writeln('#if canImport(Darwin)')
    ..writeln('import Darwin')
    ..writeln('#else')
    ..writeln('import Glibc')
    ..writeln('#endif')
    ..writeln()
    ..writeln('@_cdecl("${prefix}free")')
    ..writeln('public func ${prefix}free(_ pointer: UnsafeMutablePointer<CChar>?) {')
    ..writeln('    free(pointer)')
    ..writeln('}');
  for (final DVAppleFunction f in surface.functions) {
    final String params = f.params
        .map(((String?, String, String) p) => '_ ${p.$2}: ${_swiftTypes[p.$3]!.$1}')
        .join(', ');
    final String args = f.params.map(((String?, String, String) p) {
      final String value = p.$3 == 'String' ? 'String(cString: ${p.$2})' : p.$2;
      return p.$1 == null ? value : '${p.$1}: $value';
    }).join(', ');
    final String call = '${f.owner == null ? '' : '${f.owner}.'}${f.name}($args)';
    final String result = f.returns == 'String'
        ? 'UnsafeMutablePointer<CChar>'
        : _swiftTypes[f.returns]!.$1;
    out
      ..writeln()
      ..writeln('@_cdecl("${f.symbol}")')
      ..writeln('public func ${f.symbol}($params) -> $result {')
      ..writeln(f.returns == 'String'
          ? '    return strdup($call)!'
          : '    return $call')
      ..writeln('}');
  }
  return out.toString();
}

String _snake(String camel) => camel
    .replaceAllMapped(RegExp('([a-z0-9])([A-Z])'), (Match m) => '${m[1]}_${m[2]}')
    .toLowerCase();

int _matching(String code, int open) {
  int depth = 0;
  for (int i = open; i < code.length; i++) {
    if (code[i] == '{') depth++;
    if (code[i] == '}') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return code.length;
}

String _stripSwiftComments(String code) => code
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

/// Objective-C types that cross: the C spelling, the dart:ffi type, the
/// Dart type.
const Map<String, (String, String, String)> _objcTypes =
    <String, (String, String, String)>{
  'int': ('int32_t', 'Int32', 'int'),
  'NSInteger': ('int64_t', 'Int64', 'int'),
  'NSUInteger': ('uint64_t', 'Uint64', 'int'),
  'long': ('int64_t', 'Int64', 'int'),
  'int32_t': ('int32_t', 'Int32', 'int'),
  'int64_t': ('int64_t', 'Int64', 'int'),
  'double': ('double', 'Double', 'double'),
  'float': ('float', 'Float', 'double'),
  'CGFloat': ('double', 'Double', 'double'),
  'BOOL': ('bool', 'Bool', 'bool'),
  'NSString*': ('const char *', 'Pointer<Utf8>', 'String'),
  'void': ('void', 'Void', 'void'),
};

/// The dart:ffi type of a crossing Objective-C type.
String dvObjcFfi(String type) => _objcTypes[type]!.$2;

/// Reads the class methods declared in the Objective-C headers under [dir].
///
/// A class method (`+`) needs no object, so it is the Objective-C
/// counterpart of a static function; an instance method (`-`) is left out
/// for the same reason a JVM instance method is.
DVAppleSurface dvScanObjcHeaders(String dir, String name,
    {List<String>? files}) {
  final List<String> all = files ??
      <String>[
        for (final FileSystemEntity e in Directory(dir).listSync(recursive: true))
          if (e is File && (e.path.endsWith('.h') || e.path.endsWith('.m')))
            p.relative(e.path, from: dir).replaceAll('\\', '/'),
      ]
    ..sort();
  final String prefix = 'dv_${name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_')}_';
  final List<DVAppleFunction> functions = <DVAppleFunction>[];
  final Map<String, String> skipped = <String, String>{};
  for (final String header in all.where((String f) => f.endsWith('.h'))) {
    final String code = _stripSwiftComments(File(p.join(dir, header)).readAsStringSync());
    for (final RegExpMatch c in RegExp(r'@interface\s+([A-Za-z_]\w*)[^\n]*\n([\s\S]*?)@end')
        .allMatches(code)) {
      final String cls = c.group(1)!;
      for (final RegExpMatch m in RegExp(r'^\s*([+-])\s*\(([^)]+)\)\s*([^;]+);', multiLine: true)
          .allMatches(c.group(2)!)) {
        final String ret = m.group(2)!.replaceAll(' ', '');
        final String body = m.group(3)!.trim();
        final List<RegExpMatch> parts =
            RegExp(r'([A-Za-z_]\w*)\s*:\s*\(([^)]+)\)\s*([A-Za-z_]\w*)').allMatches(body).toList();
        final String selector = parts.isEmpty
            ? body
            : parts.map((RegExpMatch x) => '${x.group(1)}:').join();
        final String first = parts.isEmpty ? body : parts.first.group(1)!;
        final String label = '$cls.$selector';
        if (m.group(1) == '-') {
          skipped[label] = 'is an instance method, and its object would be '
              'one the module owns across calls';
          continue;
        }
        final List<(String?, String, String)> params = <(String?, String, String)>[
          for (final RegExpMatch x in parts)
            (x.group(1), x.group(3)!, x.group(2)!.replaceAll(' ', '')),
        ];
        final String? bad = <String>[ret, ...params.map(((String?, String, String) x) => x.$3)]
            .cast<String?>()
            .firstWhere((String? t) => !_objcTypes.containsKey(t) || (t == 'void' && t != ret),
                orElse: () => null);
        if (bad != null) {
          skipped[label] = 'uses $bad, which does not cross the C ABI';
          continue;
        }
        final String op = '${cls[0].toLowerCase()}${cls.substring(1)}'
            '${first[0].toUpperCase()}${first.substring(1)}';
        functions.add(DVAppleFunction(
          symbol: '$prefix${_snake(op)}',
          owner: cls,
          name: selector,
          params: params,
          returns: ret,
          operation: DVModuleOperation(
            name: op,
            returnType: _objcTypes[ret]!.$3,
            params: <DVModuleParam>[
              for (final (String? _, String n, String t) in params)
                DVModuleParam(name: n, type: _objcTypes[t]!.$3),
            ],
            doc: '`+[$cls $selector]` in $name.',
          ),
        ));
      }
    }
  }
  if (functions.isEmpty) {
    throw DVDartSurfaceRefused('$name declares no class method a module can '
        'export across the C ABI (DV-MODULE-010).');
  }
  functions.sort((DVAppleFunction a, DVAppleFunction b) =>
      a.operation.name.compareTo(b.operation.name));
  return DVAppleSurface(
    language: 'objc',
    name: name,
    directory: dir,
    sources: all,
    functions: functions,
    skipped: skipped,
  );
}

/// The Objective-C file that exports [surface]'s class methods as C
/// functions, compiled with the pod's own sources.
String dvObjcShim(DVAppleSurface surface, String prefix) {
  final StringBuffer out = StringBuffer()
    ..writeln('// GENERATED by dartvel add. Exports ${surface.name} to the C ABI.')
    ..writeln('#import <Foundation/Foundation.h>')
    ..writeln('#include <stdbool.h>')
    ..writeln('#include <stdint.h>')
    ..writeln('#include <stdlib.h>')
    ..writeln('#include <string.h>');
  for (final String h in surface.sources.where((String s) => s.endsWith('.h'))) {
    out.writeln('#import "$h"');
  }
  out
    ..writeln()
    ..writeln('void ${prefix}free(char *pointer) { free(pointer); }');
  for (final DVAppleFunction f in surface.functions) {
    final String params = f.params.isEmpty
        ? 'void'
        : f.params.map(((String?, String, String) x) => '${_objcTypes[x.$3]!.$1} ${x.$2}').join(', ');
    final String send = f.params.isEmpty
        ? f.name
        : f.params.map(((String?, String, String) x) {
            final String v = x.$3 == 'NSString*'
                ? '[NSString stringWithUTF8String:${x.$2}]'
                : x.$2;
            return '${x.$1}:$v';
          }).join(' ');
    final String call = '[${f.owner} $send]';
    final String ret = f.returns == 'NSString*' ? 'char *' : _objcTypes[f.returns]!.$1;
    out
      ..writeln()
      ..writeln('$ret ${f.symbol}($params) {')
      ..writeln(switch (f.returns) {
        'void' => '  $call;',
        'NSString*' => '  return strdup([$call UTF8String]);',
        _ => '  return $call;',
      })
      ..writeln('}');
  }
  return out.toString();
}
