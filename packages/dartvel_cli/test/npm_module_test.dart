// An npm package becomes a module that runs in a browser and in Node.
//
// Both carriers are run, not read. The backend one on the VM, which starts
// Node for the call. The web one compiled with dart2js into a page, served
// with the package among the page's assets, and loaded in headless Chrome,
// whose DOM is where the probe writes what the call returned. A device has
// no JavaScript engine, so there the module is unavailable, and the web
// build of the same module never carries the Node runner.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/modules/described_api.dart';
import 'package:dartvel_cli/src/modules/foreign/module_writer.dart';
import 'package:dartvel_cli/src/modules/foreign/npm_module.dart';
import 'package:dartvel_cli/src/modules/foreign/npm_surface.dart';
import 'package:dartvel_core/dartvel.dart'
    show DVModuleEnvironment, DVModuleOutcome;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Directory scratch() {
  final Directory dir = Directory(p.join(Directory.current.path, '.dart_tool',
      'dv_npm_module_probe', 'p${DateTime.now().microsecondsSinceEpoch}'))
    ..createSync(recursive: true);
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

Directory npmPackage(Directory root) {
  final Directory dir = Directory(p.join(root.path, 'text-kit'))..createSync();
  File(p.join(dir.path, 'package.json')).writeAsStringSync(jsonEncode(<String, Object?>{
    'name': '@acme/text-kit',
    'version': '3.1.0',
    'module': 'index.mjs',
    'types': 'index.d.ts',
  }));
  File(p.join(dir.path, 'index.mjs')).writeAsStringSync('''
export function slug(text, separator = '-') {
  return text.trim().toLowerCase().split(/\\s+/).join(separator);
}
export async function words(text) { return text.split(' '); }
''');
  File(p.join(dir.path, 'index.d.ts')).writeAsStringSync('''
export declare function slug(text: string, separator?: string): string;
export declare function words(text: string): Promise<string[]>;
''');
  return dir;
}

Future<DVGeneratedModule> generate(Directory root) async {
  final DVNpmSurface surface = dvScanNpmPackage(npmPackage(root).path);
  return dvWriteForeignModule(dvNpmModuleSpec(
    id: 'textKit',
    source: 'npm:@acme/text-kit@3.1.0',
    surface: surface,
    bundles: await dvBundleNpm(surface),
  ));
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
  final File config = File(p.join(root.path, 'package_config.json'))
    ..writeAsStringSync(jsonEncode(<String, Object?>{
      'configVersion': 2,
      'packages': <Object?>[
        for (final Object? e in own['packages']! as List<Object?>)
          <String, Object?>{
            ...(e! as Map<String, Object?>),
            'rootUri': base.resolve((e as Map<String, Object?>)['rootUri']! as String).toString(),
          },
        <String, Object?>{
          'name': module.packageName,
          'rootUri': into.uri.toString(),
          'packageUri': 'lib/',
          'languageVersion': '3.13',
        },
      ],
    }));
  return config.path;
}

void main() {
  test('it runs in a browser and in Node, and is unavailable on a device',
      () async {
    final DVGeneratedModule module = await generate(scratch());
    expect(module.files['pubspec.yaml'], contains('''
      slug:
        native: unavailable
        web: real
        backend: real'''));
    expect(module.files['pubspec.yaml'], contains('    - assets/npm/'));
    expect(module.files.keys, contains('assets/npm/acme_text_kit.mjs'));
    expect(module.files['lib/src/carrier_web.dart'], isNot(contains('node')));
  });

  test('the backend carrier calls the package in Node', () async {
    final Directory root = scratch();
    final String config = install(root, await generate(root));
    final File probe = File(p.join(root.path, 'probe.dart'))
      ..writeAsStringSync('''
import 'package:dv_text_kit_module/dv_text_kit_module.dart';

Future<void> main() async {
  const TextKitModule m = TextKitModule();
  print(await m.slug('  Hello Big World '));
  print(await m.slug('Hello World', '_'));
  print((await m.words('a b c')).length);
}
''');
    final ProcessResult run = await Process.run(Platform.resolvedExecutable,
        <String>['--packages=$config', probe.path]);
    expect('${run.stdout}${run.stderr}',
        contains('hello-big-world\nhello_world\n3'),
        reason: '${run.stdout}${run.stderr}');
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('the web carrier loads the package in a browser', () async {
    final String chrome = <String>[
      '/usr/bin/google-chrome',
      '/usr/bin/chromium',
      '/usr/bin/chromium-browser',
    ].firstWhere((String c) => File(c).existsSync(), orElse: () => '');
    if (chrome.isEmpty) {
      markTestSkipped('no Chrome to load the page in');
      return;
    }
    final Directory root = scratch();
    final DVGeneratedModule module = await generate(root);
    final String config = install(root, module);
    final Directory site = Directory(p.join(root.path, 'site'))..createSync();
    File(p.join(root.path, 'main.dart')).writeAsStringSync('''
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:dv_text_kit_module/dv_text_kit_module.dart';

Future<void> main() async {
  String out;
  try {
    out = 'slug=' + await const TextKitModule().slug('Hello Big World');
  } catch (e) {
    out = 'error ' + e.toString();
  }
  final JSObject body =
      (globalContext['document']! as JSObject)['body']! as JSObject;
  body['textContent'] = out.toJS;
}
''');
    final ProcessResult compiled = await Process.run(Platform.resolvedExecutable, <String>[
      'compile', 'js', '--packages=$config', '-o',
      p.join(site.path, 'main.dart.js'), p.join(root.path, 'main.dart'),
    ]);
    expect(compiled.exitCode, 0, reason: '${compiled.stdout}${compiled.stderr}');
    File(p.join(site.path, 'index.html')).writeAsStringSync(
        '<!doctype html><html><head><base href="/"></head><body>waiting'
        '<script src="main.dart.js"></script></body></html>');
    // Where Flutter serves a package's asset.
    File(p.join(site.path, 'assets', 'packages', module.packageName, 'assets',
        'npm', 'acme_text_kit.mjs'))
      ..createSync(recursive: true)
      ..writeAsStringSync(module.files['assets/npm/acme_text_kit.mjs']!);

    final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((HttpRequest request) async {
      final String path = request.uri.path == '/' ? '/index.html' : request.uri.path;
      final File file = File(p.join(site.path, path.substring(1)));
      if (!file.existsSync()) {
        request.response.statusCode = 404;
      } else {
        request.response.headers.contentType = path.endsWith('.html')
            ? ContentType.html
            : ContentType('text', 'javascript', charset: 'utf-8');
        request.response.add(file.readAsBytesSync());
      }
      await request.response.close();
    });

    final Directory profile = Directory.systemTemp.createTempSync('dv_chrome_');
    addTearDown(() => profile.deleteSync(recursive: true));
    final ProcessResult dom = await Process.run(chrome, <String>[
      '--headless=new', '--disable-gpu', '--no-sandbox',
      '--user-data-dir=${profile.path}',
      '--virtual-time-budget=15000', '--dump-dom',
      'http://127.0.0.1:${server.port}/',
    ]);
    expect('${dom.stdout}', contains('slug=hello-big-world'),
        reason: '${dom.stdout}${dom.stderr}');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
