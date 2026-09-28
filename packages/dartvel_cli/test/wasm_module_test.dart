// A WebAssembly binary becomes a module: its exported functions, typed from
// the binary's own type section, run in a browser and on the backend.
//
// The binary here is assembled by hand -- add(i32, i32), mul64(i64, i64)
// and half(f64) -- so the test depends on no toolchain. mul64 is the one that
// matters: JavaScript passes a 64-bit WebAssembly integer as a BigInt, and
// a carrier that passed a Number would fail, or worse, round.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_cli/src/modules/described_api.dart';
import 'package:dartvel_cli/src/modules/foreign/dart_surface.dart';
import 'package:dartvel_cli/src/modules/foreign/module_writer.dart';
import 'package:dartvel_cli/src/modules/foreign/wasm_module.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Uint8List wasmBinary() => Uint8List.fromList(<int>[
      0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00, // magic, version
      // type section: (i32 i32)->i32, (i64 i64)->i64, (f64)->f64
      0x01, 0x12, 0x03,
      0x60, 0x02, 0x7f, 0x7f, 0x01, 0x7f,
      0x60, 0x02, 0x7e, 0x7e, 0x01, 0x7e,
      0x60, 0x01, 0x7c, 0x01, 0x7c,
      // function section
      0x03, 0x04, 0x03, 0x00, 0x01, 0x02,
      // export section
      0x07, 0x16, 0x03,
      0x03, 0x61, 0x64, 0x64, 0x00, 0x00,
      0x05, 0x6d, 0x75, 0x6c, 0x36, 0x34, 0x00, 0x01,
      0x04, 0x68, 0x61, 0x6c, 0x66, 0x00, 0x02,
      // code section
      0x0a, 0x20, 0x03,
      0x07, 0x00, 0x20, 0x00, 0x20, 0x01, 0x6a, 0x0b,
      0x07, 0x00, 0x20, 0x00, 0x20, 0x01, 0x7e, 0x0b,
      0x0e, 0x00, 0x20, 0x00, 0x44,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xe0, 0x3f, 0xa2, 0x0b,
    ]);

Directory scratch() {
  final Directory dir = Directory(p.join(Directory.current.path, '.dart_tool',
      'dv_wasm_probe', 'p${DateTime.now().microsecondsSinceEpoch}'))
    ..createSync(recursive: true);
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

String install(Directory root, DVGeneratedModule module) {
  final Directory into = Directory(p.join(root.path, module.packageName));
  for (final MapEntry<String, String> f in module.files.entries) {
    File(p.join(into.path, f.key))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(f.value);
  }
  final Map<String, Object?> own = jsonDecode(File(p.join(
          Directory.current.path, '.dart_tool', 'package_config.json'))
      .readAsStringSync()) as Map<String, Object?>;
  final Uri base = Directory(p.join(Directory.current.path, '.dart_tool')).uri;
  return (File(p.join(root.path, 'package_config.json'))
        ..writeAsStringSync(jsonEncode(<String, Object?>{
          'configVersion': 2,
          'packages': <Object?>[
            for (final Object? e in own['packages']! as List<Object?>)
              <String, Object?>{
                ...(e! as Map<String, Object?>),
                'rootUri': base
                    .resolve((e as Map<String, Object?>)['rootUri']! as String)
                    .toString(),
              },
            <String, Object?>{
              'name': module.packageName,
              'rootUri': into.uri.toString(),
              'packageUri': 'lib/',
              'languageVersion': '3.13',
            },
          ],
        })))
      .path;
}

void main() {
  test('exports are read from the binary with their types', () {
    final DVWasmSurface surface = dvScanWasm(wasmBinary(), name: 'calc');
    final Map<String, DVModuleOperation> ops = <String, DVModuleOperation>{
      for (final DVModuleOperation o in surface.operations) o.name: o,
    };
    expect(ops['add']!.parameterList, 'int a0, int a1');
    expect(ops['add']!.returnType, 'Future<int>');
    expect(ops['mul64']!.returnType, 'Future<int>');
    expect(surface.types['mul64'], <String>['i64', 'i64', '->', 'i64']);
    expect(ops['half']!.returnType, 'Future<double>');
  });

  test('a binary that is not WebAssembly is refused', () {
    expect(() => dvScanWasm(Uint8List.fromList(<int>[1, 2, 3, 4]), name: 'x'),
        throwsA(isA<DVDartSurfaceRefused>()));
  });

  test('the backend runs it in Node, 64-bit integers intact', () async {
    final Directory root = scratch();
    final DVGeneratedModule module = dvWriteForeignModule(dvWasmModuleSpec(
      id: 'calc',
      source: 'wasm:calc.wasm',
      bytes: wasmBinary(),
      surface: dvScanWasm(wasmBinary(), name: 'calc'),
    ));
    expect(module.files['pubspec.yaml'], contains('''
      add:
        native: real
        web: real
        backend: real'''));
    final String config = install(root, module);
    final File probe = File(p.join(root.path, 'probe.dart'))
      ..writeAsStringSync('''
import 'package:dv_calc_module/dv_calc_module.dart';

Future<void> main() async {
  const CalcModule m = CalcModule();
  print(await m.add(40, 2));
  print(await m.mul64(3037000499, 3037000499));
  print(await m.half(5));
}
''');
    final ProcessResult run = await Process.run(Platform.resolvedExecutable,
        <String>['--packages=$config', probe.path]);
    // 3037000499 squared is 9223372030926249001: past 2^53, so a Number
    // would have rounded it.
    expect('${run.stdout}', contains('42\n9223372030926249001\n2.5'),
        reason: '${run.stdout}${run.stderr}');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a browser instantiates it and calls it', () async {
    final String chrome = <String>['/usr/bin/google-chrome', '/usr/bin/chromium']
        .firstWhere((String c) => File(c).existsSync(), orElse: () => '');
    if (chrome.isEmpty) {
      markTestSkipped('no Chrome');
      return;
    }
    final Directory root = scratch();
    final DVGeneratedModule module = dvWriteForeignModule(dvWasmModuleSpec(
      id: 'calc',
      source: 'wasm:calc.wasm',
      bytes: wasmBinary(),
      surface: dvScanWasm(wasmBinary(), name: 'calc'),
    ));
    final String config = install(root, module);
    final Directory site = Directory(p.join(root.path, 'site'))..createSync();
    File(p.join(root.path, 'main.dart')).writeAsStringSync('''
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:dv_calc_module/dv_calc_module.dart';

Future<void> main() async {
  String out;
  try {
    const CalcModule m = CalcModule();
    out = 'add=\${await m.add(40, 2)} mul=\${await m.mul64(3037000499, 3037000499)} half=\${await m.half(5)}';
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
    // dart2js represents every int as a double, so the 64-bit answer is
    // exact only up to 2^53; what is checked is that it arrives, and that
    // add and half are right.
    expect('${dom.stdout}', contains('add=42'), reason: '${dom.stdout}${dom.stderr}');
    expect('${dom.stdout}', contains('half=2.5'));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
