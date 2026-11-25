// What a Dartvel build adds to the flutter_bootstrap.js Flutter writes.
//
// Two things flutter.js 3.50 does not do by default. Its deferred-module
// loader fetches a module every time it is asked for one: every page library
// names the shared modules it needs as well as its own, so preloading the
// links on tools.sigmadev.digital downloaded, compiled and instantiated the
// same modules once per page (812 requests in three seconds of scrolling).
// And its wasm allow list leaves Safari and Firefox on dart2js, though Safari
// 26.2 and Firefox 147 run the wasm app.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/build/web_renderer.dart';
import 'package:dartvel_core/dartvel.dart' show DVWasmEngines;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// What `flutter build web --wasm` writes.
const String flutterBootstrap = '''
(()=>{var _flutter = window._flutter = {}; /* flutter.js */})();
_flutter.buildConfig = {"engineRevision":"4d35714800","builds":[{"compileTarget":"dart2wasm","renderer":"skwasm","mainWasmPath":"main.dart.wasm","jsSupportRuntimePath":"main.dart.mjs"},{"compileTarget":"dart2js","renderer":"canvaskit","mainJsPath":"main.dart.js"}]};
_flutter.loader.load({
  serviceWorkerSettings: {
    serviceWorkerVersion: "123"
  }
});
''';

const String safari262 =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.2 Safari/605.1.15';
const String safari261 =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.1 Safari/605.1.15';

/// Runs [bootstrap] in node with a fake flutter.js that records what
/// `_flutter.loader.load` was given, then [after] (JavaScript, with `given`
/// the options), and returns what [after] printed.
Future<String> run(String bootstrap,
    {String userAgent = safari262, String after = ''}) async {
  final Directory temp = Directory.systemTemp.createTempSync('dv_bootstrap_');
  try {
    // Flutter's own first line defines window._flutter; the fake loader
    // stands in for the rest of flutter.js.
    final String withFakeLoader = bootstrap.replaceFirst('/* flutter.js */',
        'window._flutter.loader = {load(options) { globalThis.given = options; }};');
    File(p.join(temp.path, 'run.mjs')).writeAsStringSync('''
globalThis.window = globalThis;
Object.defineProperty(globalThis, "navigator", {value: ${jsonEncode(<String, String>{'vendor': 'Apple Computer, Inc.', 'userAgent': userAgent})}, configurable: true});
globalThis.document = { baseURI: 'https://shop.example/app/' };
${withFakeLoader.replaceAll('_flutter.buildConfig', 'window._flutter.buildConfig')}
$after
''');
    final ProcessResult result = await Process.run(
        'node', <String>['run.mjs'], workingDirectory: temp.path);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    return result.stdout.toString().trim();
  } finally {
    temp.deleteSync(recursive: true);
  }
}

void main() {
  final String written =
      dvBootstrapWithLoaderConfig(flutterBootstrap, DVWasmEngines.all);

  group('the wasm allow list', () {
    test('Safari 26.2 and Firefox are on, by the build\'s own WebKit gate',
        () async {
      expect(
          await run(written,
              after: 'console.log(JSON.stringify(given.config.wasmAllowList))'),
          '{"webkit":true,"gecko":true}');
      expect(
          await run(written,
              userAgent: safari261,
              after: 'console.log(JSON.stringify(given.config.wasmAllowList))'),
          '{"webkit":false,"gecko":true}',
          reason: 'flutter.js has no WebKit version test; Safari before 26.2 '
              'stays on dart2js');
    });

    test('an engine the project turned off stays off', () async {
      final String noSafari = dvBootstrapWithLoaderConfig(
          flutterBootstrap, const DVWasmEngines(webkit: false));
      expect(
          await run(noSafari,
              after: 'console.log(JSON.stringify(given.config.wasmAllowList))'),
          '{"webkit":false,"gecko":true}');
    });

    test("the application's own load options are kept, and its own allow "
        'list wins', () async {
      final String custom = dvBootstrapWithLoaderConfig(
          flutterBootstrap.replaceFirst('_flutter.loader.load({',
              '_flutter.loader.load({config: {wasmAllowList: {gecko: false}, canvasKitBaseUrl: "ck/"},'),
          DVWasmEngines.all);
      expect(
          await run(custom,
              after: 'console.log(JSON.stringify([given.config.wasmAllowList, '
                  'given.config.canvasKitBaseUrl, '
                  'given.serviceWorkerSettings.serviceWorkerVersion]))'),
          '[{"webkit":true,"gecko":false},"ck/","123"]');
    });
  });

  group('the deferred-module loader', () {
    const String harness = '''
const fetched = {}; const loaded = {};
globalThis.fetch = async (url) => { const name = String(url).split('/').pop(); fetched[name] = (fetched[name] || 0) + 1; return 'response for ' + url; };
const loader = given.config.wasmDeferredModulesLoader;
const load = async (name) => { loaded[name] = (loaded[name] || 0) + 1; await new Promise((r) => setTimeout(r, 5)); };
await loader(['shared1.wasm', 'page_a.wasm'], load);
await Promise.all([loader(['shared1.wasm', 'page_b.wasm'], load), loader(['shared1.wasm', 'page_c.wasm'], load)]);
let failOnce = true;
await loader(['flaky.wasm'], async (name) => { if (failOnce) { failOnce = false; throw new Error('network'); } loaded[name] = (loaded[name] || 0) + 1; }).catch(() => {});
await loader(['flaky.wasm'], async (name) => { loaded[name] = (loaded[name] || 0) + 1; });
console.log(JSON.stringify({ fetched, loaded }));
''';

    test('each deferred module is fetched and instantiated once, however many '
        'pages ask for it, and one that failed is tried again', () async {
      expect(await run(written, after: harness),
          '{"fetched":{"shared1.wasm":1,"page_a.wasm":1,"page_b.wasm":1,"page_c.wasm":1,"flaky.wasm":2},"loaded":{"shared1.wasm":1,"page_a.wasm":1,"page_b.wasm":1,"page_c.wasm":1,"flaky.wasm":1}}');
    });

    test('hands dart2wasm the response, from beside the app', () async {
      // dart2wasm compiles what it is handed only if it is a Response or the
      // bytes; a pending fetch is neither, and every page failed to load.
      const String probe = '''
globalThis.fetch = async (url) => 'response for ' + url;
await given.config.wasmDeferredModulesLoader(['main.dart_module3.wasm'], async (name, response) => console.log(name + ' <- ' + response));
''';
      expect(await run(written, after: probe),
          'main.dart_module3.wasm <- response for https://shop.example/app/main.dart_module3.wasm');
      final String elsewhere = dvBootstrapWithLoaderConfig(
          flutterBootstrap.replaceFirst('_flutter.loader.load({',
              '_flutter.loader.load({config: {entrypointBaseUrl: "/static/"},'),
          DVWasmEngines.all);
      expect(await run(elsewhere, after: probe),
          'main.dart_module3.wasm <- response for https://shop.example/static/main.dart_module3.wasm',
          reason: 'flutter.js fetches the app from entrypointBaseUrl, and its '
              'modules are beside it');
    });

    test("an application's own loader is left in charge", () async {
      final String custom = dvBootstrapWithLoaderConfig(
          flutterBootstrap.replaceFirst('_flutter.loader.load({',
              '_flutter.loader.load({config: {wasmDeferredModulesLoader: function mine() {}},'),
          DVWasmEngines.all);
      expect(
          await run(custom,
              after: 'console.log(given.config.wasmDeferredModulesLoader.name)'),
          'mine');
    });
  });

  group('the bootstrap', () {
    test('says which engines it allows, for the page around it to read', () {
      expect(dvBootstrapWasmEngines(written), DVWasmEngines.all);
      expect(
          dvBootstrapWasmEngines(dvBootstrapWithLoaderConfig(
              flutterBootstrap, const DVWasmEngines(gecko: false))),
          const DVWasmEngines(gecko: false));
      // Flutter's own: only Chromium.
      expect(dvBootstrapWasmEngines(flutterBootstrap), DVWasmEngines.chromiumOnly);
    });

    test('a second build changes nothing, and a different choice replaces the '
        'first', () {
      expect(dvBootstrapWithLoaderConfig(written, DVWasmEngines.all), written);
      final String changed = dvBootstrapWithLoaderConfig(
          written, const DVWasmEngines(webkit: false));
      expect(dvBootstrapWasmEngines(changed), const DVWasmEngines(webkit: false));
      expect(RegExp(RegExp.escape(dvLoaderConfigMarker)).allMatches(changed),
          hasLength(1));
    });

    test('a bootstrap without the build config is left as it was', () {
      // flutter.js is not defined yet above it, so nothing can wrap the loader.
      const String odd = '_flutter.loader.load({});\n';
      expect(dvBootstrapWithLoaderConfig(odd, DVWasmEngines.all), odd);
    });
  });
}
