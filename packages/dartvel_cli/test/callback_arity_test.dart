// DV-BIND-004: a foreign callback whose arity the generator cannot
// determine is left out with the diagnostic rather than guessed.
//
// A callback that fires once is a Future and one that fires many times is a
// Stream. Nothing in a C function pointer, a Rust `extern "C" fn` parameter
// or a TypeScript function type says which, so the operation is left out
// with DV-BIND-004 and the reason, never wrapped as one or the other. The
// silent failure guarded here is worse than a wrong guess: the C and Rust
// readers used to drop such a function without a word, because a
// parenthesis inside the parameter list broke the match, so the README did
// not even say it was missing.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/modules/foreign/ffi_surface.dart';
import 'package:dartvel_cli/src/modules/foreign/npm_surface.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Directory source(Map<String, String> files) {
  final Directory dir = Directory.systemTemp.createTempSync('dv_arity_');
  addTearDown(() => dir.deleteSync(recursive: true));
  for (final MapEntry<String, String> f in files.entries) {
    File(p.join(dir.path, f.key))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(f.value);
  }
  return dir;
}

void main() {
  test('a C function taking a function pointer is DV-BIND-004, named in '
      'skipped, and the rest of the header still reads', () {
    final DVFfiSurface surface = dvScanC(source(<String, String>{
      'ticker.h': '''
#include <stdint.h>
typedef void (*tk_listener)(int32_t value);
int32_t tk_add(int32_t a, int32_t b);
void tk_every(int32_t ms, void (*tick)(int32_t count));
void tk_listen(tk_listener listener);
''',
    }).path);

    expect(surface.functions.map((DVFfiFunction f) => f.name), <String>['tk_add']);
    expect(surface.skipped['tk_every'],
        allOf(contains('DV-BIND-004'), contains('tick')));
    expect(surface.skipped['tk_listen'],
        allOf(contains('DV-BIND-004'), contains('listener')));
  });

  test('a Rust extern "C" fn taking a callback is DV-BIND-004', () {
    final DVFfiSurface surface = dvScanRust(source(<String, String>{
      'Cargo.toml': '[package]\nname = "ticker"\nversion = "0.1.0"\n',
      'src/lib.rs': r'''
#[no_mangle]
pub extern "C" fn tk_add(a: i32, b: i32) -> i32 { a + b }

#[no_mangle]
pub extern "C" fn tk_every(ms: u32, tick: extern "C" fn(u32)) {}

#[no_mangle]
pub extern "C" fn tk_maybe(tick: Option<extern "C" fn(u32) -> bool>) -> i32 { 0 }
''',
    }).path);

    expect(surface.functions.map((DVFfiFunction f) => f.name), <String>['tk_add']);
    expect(surface.skipped['tk_every'],
        allOf(contains('DV-BIND-004'), contains('tick')));
    expect(surface.skipped['tk_maybe'], contains('DV-BIND-004'));
  });

  test('a TypeScript function taking a callback is DV-BIND-004; one '
      'returning a function is not a callback', () {
    final Directory dir = source(<String, String>{
      'package.json': jsonEncode(<String, Object?>{
        'name': 'ticker',
        'version': '1.0.0',
        'module': 'index.mjs',
        'types': 'index.d.ts',
      }),
      'index.mjs': 'export function add(a, b) { return a + b; }\n',
      'index.d.ts': '''
export declare function add(a: number, b: number): number;
export declare function every(ms: number, tick: (count: number) => void): void;
export declare function make(): () => void;
''',
    });
    final DVNpmSurface surface = dvScanNpmPackage(dir.path);
    expect(surface.skipped['every'],
        allOf(contains('DV-BIND-004'), contains('tick')));
    expect(surface.skipped['make'], isNot(contains('DV-BIND-004')));
  });
}
