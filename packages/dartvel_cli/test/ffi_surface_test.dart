// What a C library or a Rust crate offers a module across the C ABI.
//
// Read from the C headers, or from a crate's `extern "C"` functions. The
// silent failure this guards is memory: a function returning a `char *`
// could hand back a buffer the caller must free, one it must not, or one
// that is freed on the next call, and nothing in the signature says which.
// A generator that guessed would produce a leak or a use-after-free that
// shows up under load on one platform, so such a function is left out with
// DV-BIND-003 rather than wrapped.
import 'dart:io';

import 'package:dartvel_cli/src/modules/foreign/dart_surface.dart';
import 'package:dartvel_cli/src/modules/foreign/ffi_surface.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Directory source(Map<String, String> files) {
  final Directory dir = Directory.systemTemp.createTempSync('dv_ffi_');
  addTearDown(() => dir.deleteSync(recursive: true));
  for (final MapEntry<String, String> f in files.entries) {
    File(p.join(dir.path, f.key))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(f.value);
  }
  return dir;
}

Map<String, DVFfiFunction> byName(DVFfiSurface s) =>
    <String, DVFfiFunction>{for (final DVFfiFunction f in s.functions) f.name: f};

void main() {
  test('C prototypes become operations with their C types', () {
    final DVFfiSurface surface = dvScanC(source(<String, String>{
      'mathkit.h': '''
#ifndef MATHKIT_H
#define MATHKIT_H
#include <stdint.h>
#include <stdbool.h>

/* Adds two numbers. */
int32_t mk_add(int32_t a, int32_t b);
double mk_scale(double value, float factor);
bool mk_is_even(int64_t n);
void mk_reset(void);
uint32_t mk_length(const char *text);
const char *mk_name(void);
void mk_fill(int32_t *out, size_t count);
static inline int mk_inline(int x) { return x; }
#define MK_MAX 10
#endif
''',
      'mathkit.c': '#include "mathkit.h"\nint32_t mk_add(int32_t a, int32_t b) { return a + b; }\n',
    }).path);

    expect(surface.language, 'c');
    expect(surface.sources, <String>['mathkit.c']);
    final Map<String, DVFfiFunction> fns = byName(surface);
    expect(fns.keys, containsAll(<String>['mk_add', 'mk_scale', 'mk_is_even', 'mk_reset', 'mk_length']));
    expect(fns['mk_add']!.operation.parameterList, 'int a, int b');
    expect(fns['mk_add']!.operation.returnType, 'int');
    expect(fns['mk_add']!.nativeSignature, 'Int32 Function(Int32, Int32)');
    expect(fns['mk_scale']!.nativeSignature, 'Double Function(Double, Float)');
    expect(fns['mk_is_even']!.operation.returnType, 'bool');
    expect(fns['mk_reset']!.nativeSignature, 'Void Function()');
    expect(fns['mk_length']!.operation.parameterList, 'String text');
    expect(fns['mk_length']!.nativeSignature, 'Uint32 Function(Pointer<Utf8>)');
    expect(surface.skipped['mk_name'], contains('DV-BIND-003'));
    expect(surface.skipped['mk_fill'], contains('DV-BIND-003'));
    expect(fns.containsKey('mk_inline'), isFalse);
  });

  test('a crate\'s extern "C" functions become operations', () {
    final DVFfiSurface surface = dvScanRust(source(<String, String>{
      'Cargo.toml': '[package]\nname = "fastmath"\nversion = "0.4.1"\n',
      'src/lib.rs': r'''
use std::ffi::CStr;
use std::os::raw::c_char;

/// Multiplies two numbers.
#[no_mangle]
pub extern "C" fn fm_mul(a: i64, b: i64) -> i64 { a * b }

#[unsafe(no_mangle)]
pub extern "C" fn fm_half(x: f64) -> f64 { x / 2.0 }

#[no_mangle]
pub extern "C" fn fm_len(text: *const c_char) -> u32 {
    unsafe { CStr::from_ptr(text) }.to_bytes().len() as u32
}

#[no_mangle]
pub extern "C" fn fm_buffer() -> *mut u8 { std::ptr::null_mut() }

pub fn not_exported(x: i32) -> i32 { x }
''',
    }).path);

    expect(surface.language, 'rust');
    expect(surface.name, 'fastmath');
    expect(surface.version, '0.4.1');
    final Map<String, DVFfiFunction> fns = byName(surface);
    expect(fns.keys, unorderedEquals(<String>['fm_mul', 'fm_half', 'fm_len']));
    expect(fns['fm_mul']!.nativeSignature, 'Int64 Function(Int64, Int64)');
    expect(fns['fm_mul']!.operation.doc, 'Multiplies two numbers.');
    expect(fns['fm_len']!.operation.parameterList, 'String text');
    expect(surface.skipped['fm_buffer'], contains('DV-BIND-003'));
  });

  test('a source with nothing to call is DV-MODULE-010', () {
    expect(
      () => dvScanC(source(<String, String>{'empty.h': '#define X 1\n'}).path),
      throwsA(isA<DVDartSurfaceRefused>().having(
          (DVDartSurfaceRefused e) => e.message, 'message', contains('DV-MODULE-010'))),
    );
  });
}
