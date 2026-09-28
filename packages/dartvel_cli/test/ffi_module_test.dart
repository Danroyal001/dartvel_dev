// A C library and a Rust crate become modules whose build hook compiles
// them for the target being built.
//
// Proven the way an application would meet them: the generated module is
// resolved by pub in a project of its own, and `dart run` builds it -- the
// hook compiles the C sources, or runs cargo on the crate -- and calls it.
// dartvel_core is stood in for by a stub with the one class the web carrier
// imports, so the run builds this module's native code and nobody else's.
import 'dart:io';

import 'package:dartvel_cli/src/modules/described_api.dart';
import 'package:dartvel_cli/src/modules/foreign/ffi_module.dart';
import 'package:dartvel_cli/src/modules/foreign/ffi_surface.dart';
import 'package:dartvel_cli/src/modules/foreign/module_writer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Directory scratch() {
  final Directory dir = Directory.systemTemp.createTempSync('dv_ffi_module_');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

/// A project depending on [module], with a stub dartvel_core.
Future<ProcessResult> runProbe(
    Directory root, DVGeneratedModule module, String probe) async {
  final Directory into = Directory(p.join(root.path, module.packageName));
  for (final MapEntry<String, String> f in module.files.entries) {
    File(p.join(into.path, f.key))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(f.value);
  }
  final Directory stub = Directory(p.join(root.path, 'dartvel_core'));
  File(p.join(stub.path, 'pubspec.yaml'))
    ..createSync(recursive: true)
    ..writeAsStringSync('name: dartvel_core\nversion: 9.9.9\n'
        'environment:\n  sdk: ">=3.13.0 <4.0.0"\n');
  File(p.join(stub.path, 'lib', 'dartvel.dart'))
    ..createSync(recursive: true)
    ..writeAsStringSync('enum DVModuleEnvironment { native, web, backend }\n'
        'class DVModuleUnavailable implements Exception {\n'
        '  const DVModuleUnavailable(this.module, this.operation, this.environment);\n'
        '  final String module; final String operation;\n'
        '  final DVModuleEnvironment environment;\n}\n');
  final Directory app = Directory(p.join(root.path, 'app'));
  File(p.join(app.path, 'pubspec.yaml'))
    ..createSync(recursive: true)
    ..writeAsStringSync('''
name: probe_app
environment:
  sdk: ">=3.13.0 <4.0.0"
dependencies:
  ${module.packageName}:
    path: ../${module.packageName}
dependency_overrides:
  dartvel_core:
    path: ../dartvel_core
''');
  File(p.join(app.path, 'bin', 'probe.dart'))
    ..createSync(recursive: true)
    ..writeAsStringSync(probe);
  final ProcessResult got = await Process.run(
      Platform.resolvedExecutable, <String>['pub', 'get'],
      workingDirectory: app.path);
  expect(got.exitCode, 0, reason: '${got.stdout}${got.stderr}');
  return Process.run(Platform.resolvedExecutable, <String>['run', 'bin/probe.dart'],
      workingDirectory: app.path);
}

void main() {
  test('a C library is compiled by the module\'s hook and called', () async {
    final Directory root = scratch();
    final Directory c = Directory(p.join(root.path, 'mathkit'))..createSync();
    File(p.join(c.path, 'mathkit.h')).writeAsStringSync('''
#include <stdint.h>
int32_t mk_add(int32_t a, int32_t b);
uint32_t mk_length(const char *text);
double mk_half(double x);
''');
    File(p.join(c.path, 'mathkit.c')).writeAsStringSync('''
#include <string.h>
#include "mathkit.h"
int32_t mk_add(int32_t a, int32_t b) { return a + b; }
uint32_t mk_length(const char *text) { return (uint32_t) strlen(text); }
double mk_half(double x) { return x / 2; }
''');
    final DVGeneratedModule module = dvWriteForeignModule(dvFfiModuleSpec(
      id: 'mathkit',
      source: 'c:mathkit',
      surface: dvScanC(c.path),
    ));
    expect(module.files['pubspec.yaml'], contains('''
      mkAdd:
        native: real
        web: unavailable
        backend: real'''));

    final ProcessResult run = await runProbe(root, module, '''
import 'package:${module.packageName}/${module.packageName}.dart';

void main() {
  const MathkitModule m = MathkitModule();
  print(m.mkAdd(40, 2));
  print(m.mkLength('héllo'));
  print(m.mkHalf(5));
}
''');
    expect('${run.stdout}', contains('42\n6\n2.5'),
        reason: '${run.stdout}${run.stderr}');
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('a Rust crate is built by cargo in the module\'s hook and called',
      () async {
    ProcessResult? cargo;
    try {
      cargo = await Process.run('cargo', <String>['--version']);
    } on ProcessException {
      cargo = null;
    }
    if (cargo == null || cargo.exitCode != 0) {
      markTestSkipped('no cargo');
      return;
    }
    final Directory root = scratch();
    final Directory crate = Directory(p.join(root.path, 'fastmath'))..createSync();
    File(p.join(crate.path, 'Cargo.toml')).writeAsStringSync('''
[package]
name = "fastmath"
version = "0.4.1"
edition = "2021"

[lib]
crate-type = ["cdylib"]
''');
    File(p.join(crate.path, 'src', 'lib.rs'))
      ..createSync(recursive: true)
      ..writeAsStringSync(r'''
use std::ffi::CStr;
use std::os::raw::c_char;

#[no_mangle]
pub extern "C" fn fm_mul(a: i64, b: i64) -> i64 { a * b }

#[no_mangle]
pub extern "C" fn fm_len(text: *const c_char) -> u32 {
    unsafe { CStr::from_ptr(text) }.to_bytes().len() as u32
}
''');
    final DVGeneratedModule module = dvWriteForeignModule(dvFfiModuleSpec(
      id: 'fastmath',
      source: 'cargo:fastmath',
      surface: dvScanRust(crate.path),
    ));
    final ProcessResult run = await runProbe(root, module, '''
import 'package:${module.packageName}/${module.packageName}.dart';

void main() {
  const FastmathModule m = FastmathModule();
  print(m.fmMul(6, 7));
  print(m.fmLen('rust'));
}
''');
    expect('${run.stdout}', contains('42\n4'),
        reason: '${run.stdout}${run.stderr}');
  }, timeout: const Timeout(Duration(minutes: 8)));
}
