// A C library reaches the browser as WebAssembly.
//
// The placement matrix puts C and Rust on the web as WASM: the same sources
// the device links through FFI, compiled for wasm32 when the module is
// generated. Operations whose values are numbers become real in the browser,
// called synchronously as they are on a device; one that takes a string
// needs a memory layout the two sides have not agreed, and keeps its
// declared outcome there.
//
// Proven in headless Chrome, from a dart2js page.
import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_cli/src/modules/described_api.dart';
import 'package:dartvel_cli/src/modules/foreign/ffi_module.dart';
import 'package:dartvel_cli/src/modules/foreign/ffi_surface.dart';
import 'package:dartvel_cli/src/modules/foreign/ffi_wasm.dart';
import 'package:dartvel_cli/src/modules/foreign/module_writer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import 'dart_package_module_test.dart' show install, scratch;

const String _header = '''
int add(int a, int b);
double scale(double x, double k);
int count(const char *text);
''';

const String _source = '''
#include "calc.h"
int add(int a, int b) { return a + b; }
double scale(double x, double k) { return x * k; }
int count(const char *text) { int n = 0; while (text[n]) n++; return n; }
''';

Directory cLibrary(Directory root) {
  final Directory dir = Directory(p.join(root.path, 'calc'))..createSync();
  File(p.join(dir.path, 'calc.h')).writeAsStringSync(_header);
  File(p.join(dir.path, 'calc.c')).writeAsStringSync(_source);
  return dir;
}

void main() {
  test('the numeric functions compile to WebAssembly and are real on the web',
      () async {
    final Directory root = scratch();
    final DVFfiSurface surface = dvScanC(cLibrary(root).path);
    final DVFfiWasm wasm = await dvCompileFfiToWasm(surface);
    expect(wasm.bytes, isNotNull, reason: wasm.reason);
    // The magic number: \0asm.
    expect(wasm.bytes!.sublist(0, 4), <int>[0, 0x61, 0x73, 0x6d]);

    final DVGeneratedModule module = dvWriteForeignModule(
        dvFfiModuleSpec(id: 'calc', source: 'c:calc', surface: surface, wasm: wasm));
    final YamlMap ops = (loadYaml(module.files['pubspec.yaml']!)
        as YamlMap)['dartvel']['module']['operations'] as YamlMap;
    expect(ops['add']['web'], 'real');
    expect(ops['scale']['web'], 'real');
    expect(ops['count']['web'], 'unavailable');
    expect(ops['add']['native'], 'real');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('with no WebAssembly the web is what it was', () {
    final Directory root = scratch();
    final DVFfiSurface surface = dvScanC(cLibrary(root).path);
    final DVGeneratedModule module = dvWriteForeignModule(dvFfiModuleSpec(
        id: 'calc', source: 'c:calc', surface: surface,
        wasm: const DVFfiWasm.none('no wasm32 compiler')));
    final YamlMap ops = (loadYaml(module.files['pubspec.yaml']!)
        as YamlMap)['dartvel']['module']['operations'] as YamlMap;
    expect(ops['add']['web'], 'unavailable');
    expect(module.files['README.md'], contains('no wasm32 compiler'));
  });

  test('a browser calls the C functions', () async {
    final String chrome = <String>['/usr/bin/google-chrome', '/usr/bin/chromium']
        .firstWhere((String c) => File(c).existsSync(), orElse: () => '');
    if (chrome.isEmpty) {
      markTestSkipped('no Chrome');
      return;
    }
    final Directory root = scratch();
    final Directory lib = cLibrary(root);
    final DVFfiSurface surface = dvScanC(lib.path);
    final DVFfiWasm wasm = await dvCompileFfiToWasm(surface);
    expect(wasm.bytes, isA<Uint8List>(), reason: wasm.reason);
    final DVGeneratedModule module = dvWriteForeignModule(
        dvFfiModuleSpec(id: 'calc', source: 'c:calc', surface: surface, wasm: wasm));
    final String config = install(root, module, lib);
    final Directory site = Directory(p.join(root.path, 'site'))..createSync();
    File(p.join(root.path, 'main.dart')).writeAsStringSync('''
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:dv_calc_module/dv_calc_module.dart';

void main() {
  String out;
  try {
    const CalcModule m = CalcModule();
    out = 'add=\${m.add(40, 2)} scale=\${m.scale(2.5, 2)}';
  } catch (e) {
    out = 'error \$e';
  }
  ((globalContext['document']! as JSObject)['body']! as JSObject)['textContent'] = out.toJS;
}
''');
    final ProcessResult compiled = await Process.run(Platform.resolvedExecutable, <String>[
      'compile', 'js', '--packages=$config', '-o', p.join(site.path, 'main.dart.js'),
      p.join(root.path, 'main.dart'),
    ]);
    expect(compiled.exitCode, 0, reason: '${compiled.stdout}${compiled.stderr}');
    File(p.join(site.path, 'index.html')).writeAsStringSync(
        '<!doctype html><html><body>waiting<script src="main.dart.js"></script></body></html>');
    final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((HttpRequest request) async {
      final String path = request.uri.path == '/' ? '/index.html' : request.uri.path;
      final File file = File(p.join(site.path, path.substring(1)));
      if (file.existsSync()) {
        request.response.headers.contentType = path.endsWith('.html')
            ? ContentType.html
            : ContentType('text', 'javascript');
        request.response.add(file.readAsBytesSync());
      } else {
        request.response.statusCode = 404;
      }
      await request.response.close();
    });
    final Directory profile = Directory.systemTemp.createTempSync('dv_chrome_');
    addTearDown(() => profile.deleteSync(recursive: true));
    final ProcessResult dom = await Process.run(chrome, <String>[
      '--headless=new', '--disable-gpu', '--no-sandbox',
      '--user-data-dir=${profile.path}', '--virtual-time-budget=15000',
      '--dump-dom', 'http://127.0.0.1:${server.port}/',
    ]);
    expect('${dom.stdout}', contains('add=42 scale=5'),
        reason: '${dom.stdout}${dom.stderr}');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
