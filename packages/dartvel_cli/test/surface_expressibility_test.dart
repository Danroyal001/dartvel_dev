// DV-BIND-001: a source's surface that cannot be expressed across the
// chosen boundary is named with the code, per operation, in what the module
// skips -- so the README and `dartvel add` say which rule left it out
// rather than only that something did. Ownership (DV-BIND-003) and callback
// arity (DV-BIND-004) are their own codes and are not folded into this one.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/modules/foreign/apple_surface.dart';
import 'package:dartvel_cli/src/modules/foreign/ffi_surface.dart';
import 'package:dartvel_cli/src/modules/foreign/npm_surface.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Directory source(Map<String, String> files) {
  final Directory dir = Directory.systemTemp.createTempSync('dv_express_');
  addTearDown(() => dir.deleteSync(recursive: true));
  for (final MapEntry<String, String> f in files.entries) {
    File(p.join(dir.path, f.key))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(f.value);
  }
  return dir;
}

void main() {
  test('C: a type with no Dart counterpart is DV-BIND-001; a pointer is '
      'still DV-BIND-003', () {
    final DVFfiSurface surface = dvScanC(source(<String, String>{
      'geo.h': '''
#include <stdint.h>
struct point { int32_t x; int32_t y; };
int32_t geo_add(int32_t a, int32_t b);
struct point geo_origin(void);
int32_t geo_norm(struct point p);
void geo_fill(int32_t *out);
''',
    }).path);
    expect(surface.skipped['geo_origin'], contains('DV-BIND-001'));
    expect(surface.skipped['geo_norm'], contains('DV-BIND-001'));
    expect(surface.skipped['geo_fill'],
        allOf(contains('DV-BIND-003'), isNot(contains('DV-BIND-001'))));
  });

  test('Rust: a type with no Dart counterpart is DV-BIND-001', () {
    final DVFfiSurface surface = dvScanRust(source(<String, String>{
      'Cargo.toml': '[package]\nname = "geo"\nversion = "0.1.0"\n',
      'src/lib.rs': r'''
#[no_mangle]
pub extern "C" fn geo_add(a: i32, b: i32) -> i32 { a + b }
#[no_mangle]
pub extern "C" fn geo_origin() -> Point { Point::default() }
''',
    }).path);
    expect(surface.skipped['geo_origin'], contains('DV-BIND-001'));
  });

  test('TypeScript: object, union, generic and function-returning '
      'declarations are DV-BIND-001; a callback is DV-BIND-004', () {
    final Directory dir = source(<String, String>{
      'package.json': jsonEncode(<String, Object?>{
        'name': 'geo',
        'version': '1.0.0',
        'module': 'index.mjs',
        'types': 'index.d.ts',
      }),
      'index.mjs': 'export function add(a, b) { return a + b; }\n',
      'index.d.ts': '''
export declare function add(a: number, b: number): number;
export declare function parse(text: string): { ok: boolean };
export declare function pick(value: string | number): string;
export declare function first<T>(items: T[]): T;
export declare function make(): () => void;
export declare function when(value: Date): string;
export declare function each(visit: (s: string) => void): void;
''',
    });
    final DVNpmSurface surface = dvScanNpmPackage(dir.path);
    for (final String fn in <String>['parse', 'pick', 'first', 'make', 'when']) {
      expect(surface.skipped[fn], contains('DV-BIND-001'), reason: fn);
    }
    expect(surface.skipped['each'],
        allOf(contains('DV-BIND-004'), isNot(contains('DV-BIND-001'))));
  });

  test('Swift: generic, async, throwing and unbridged types are DV-BIND-001; '
      'a closure parameter is DV-BIND-004', () {
    final Directory dir = source(<String, String>{
      'Package.swift': '// swift-tools-version:5.9\n'
          'import PackageDescription\n'
          'let package = Package(name: "Geo", targets: [.target(name: "Geo")])\n',
      'Sources/Geo/Geo.swift': '''
public func add(_ a: Int32, _ b: Int32) -> Int32 { a + b }
public func first<T>(_ items: [T]) -> T { items[0] }
public func fetch() async -> Int { 1 }
public func parse(_ s: String) throws -> Int { 1 }
public func all() -> [Int] { [] }
public func take(_ xs: [Int]) -> Int { 0 }
public func each(_ visit: (Int) -> Void) {}
''',
    });
    final DVAppleSurface surface = dvScanSwiftPackage(dir.path);
    for (final String fn in <String>['first', 'fetch', 'parse', 'all', 'take']) {
      expect(surface.skipped[fn], contains('DV-BIND-001'), reason: fn);
    }
    expect(surface.skipped['each'],
        allOf(contains('DV-BIND-004'), contains('visit')));
  });
}
