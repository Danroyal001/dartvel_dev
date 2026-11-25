// Which browsers run the WebAssembly app.
//
// flutter.js 3.50 leaves Safari and Firefox off its default wasm allow list.
// Firefox 147 fixed the SpiderMonkey bug that broke dart2wasm builds, and
// flutter.js gates older Firefox itself; Safari 26.2 runs them, and
// flutter.js has no version gate for WebKit at all. A Dartvel build turns
// both on (each can be turned off) and every script in the page that guesses
// which app the loader will pick -- the splash's preload of the app, the
// renderer hints, a route's modules -- has to guess the same way, or the
// page downloads megabytes of the app it will not run.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const String chrome =
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/155.0.0.0 Safari/537.36';
const String edge =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/155.0.0.0 Safari/537.36 Edg/155.0.0.0';
String safari(String version) =>
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/$version Safari/605.1.15';
String chromeOnIos(String os) =>
    'Mozilla/5.0 (iPhone; CPU iPhone OS $os like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/155.0.0.0 Mobile/15E148 Safari/604.1';
String firefox(int version) =>
    'Mozilla/5.0 (X11; Linux x86_64; rv:$version.0) Gecko/20100101 Firefox/$version.0';

/// What [expression] evaluates to in a page whose navigator says [vendor]
/// and [userAgent], with WebAssembly's feature tests answering [features].
Future<bool> evaluate(String expression,
    {required String vendor,
    required String userAgent,
    bool features = true}) async {
  final Directory temp = Directory.systemTemp.createTempSync('dv_wasm_engines_');
  try {
    File('${temp.path}/run.js').writeAsStringSync('''
Object.defineProperty(globalThis, "navigator", {value: ${jsonEncode(<String, String>{'vendor': vendor, 'userAgent': userAgent})}, configurable: true});
globalThis.WebAssembly = { validate: (bytes, options) => options ? !$features : $features };
console.log(JSON.stringify($expression));
''');
    final ProcessResult run =
        await Process.run('node', <String>['run.js'], workingDirectory: temp.path);
    expect(run.exitCode, 0, reason: '${run.stderr}');
    return jsonDecode(run.stdout.toString().trim()) as bool;
  } finally {
    temp.deleteSync(recursive: true);
  }
}

void main() {
  group('the decision', () {
    final String both = dvWasmAppRunsHereJs(DVWasmEngines.all);

    test('Chromium browsers run it, as they always did', () async {
      expect(await evaluate(both, vendor: 'Google Inc.', userAgent: chrome), isTrue);
      expect(await evaluate(both, vendor: 'Google Inc.', userAgent: edge), isTrue);
    });

    test('Safari from 26.2, and not before', () async {
      const String apple = 'Apple Computer, Inc.';
      expect(await evaluate(both, vendor: apple, userAgent: safari('26.2')), isTrue);
      expect(await evaluate(both, vendor: apple, userAgent: safari('26.3.1')), isTrue);
      expect(await evaluate(both, vendor: apple, userAgent: safari('27.0')), isTrue);
      expect(await evaluate(both, vendor: apple, userAgent: safari('26.1')), isFalse);
      expect(await evaluate(both, vendor: apple, userAgent: safari('18.6')), isFalse);
    });

    test('every other iOS browser is WebKit, and goes by the iOS version',
        () async {
      const String apple = 'Apple Computer, Inc.';
      expect(await evaluate(both, vendor: apple, userAgent: chromeOnIos('26_2')),
          isTrue);
      expect(await evaluate(both, vendor: apple, userAgent: chromeOnIos('26_1_1')),
          isFalse);
    });

    test('Firefox from 147, and not before', () async {
      expect(await evaluate(both, vendor: '', userAgent: firefox(147)), isTrue);
      expect(await evaluate(both, vendor: '', userAgent: firefox(150)), isTrue);
      expect(await evaluate(both, vendor: '', userAgent: firefox(146)), isFalse);
    });

    test('a browser it does not recognise does not', () async {
      expect(await evaluate(both, vendor: 'Opera Software', userAgent: 'Presto/2.12'),
          isFalse);
    });

    test('nothing runs it without the WebAssembly features dart2wasm needs',
        () async {
      expect(
          await evaluate(both,
              vendor: 'Google Inc.', userAgent: chrome, features: false),
          isFalse);
      expect(
          await evaluate(both,
              vendor: 'Apple Computer, Inc.',
              userAgent: safari('26.2'),
              features: false),
          isFalse);
    });

    test('Safari or Firefox turned off keeps that engine on dart2js', () async {
      final String noSafari =
          dvWasmAppRunsHereJs(const DVWasmEngines(webkit: false));
      expect(
          await evaluate(noSafari,
              vendor: 'Apple Computer, Inc.', userAgent: safari('26.2')),
          isFalse);
      expect(await evaluate(noSafari, vendor: '', userAgent: firefox(147)), isTrue);
      final String noFirefox =
          dvWasmAppRunsHereJs(const DVWasmEngines(gecko: false));
      expect(await evaluate(noFirefox, vendor: '', userAgent: firefox(147)), isFalse);
      expect(
          await evaluate(noFirefox,
              vendor: 'Apple Computer, Inc.', userAgent: safari('26.2')),
          isTrue);
      final String chromiumOnly = dvWasmAppRunsHereJs(DVWasmEngines.chromiumOnly);
      expect(
          await evaluate(chromiumOnly, vendor: 'Google Inc.', userAgent: chrome),
          isTrue);
    });

    test('the WebKit gate on its own answers the same', () async {
      expect(
          await evaluate(dvWebkitWasmGateJs,
              vendor: 'Apple Computer, Inc.', userAgent: safari('26.2')),
          isTrue);
      expect(
          await evaluate(dvWebkitWasmGateJs,
              vendor: 'Apple Computer, Inc.', userAgent: safari('26.1')),
          isFalse);
    });
  });

  group('the build says which engines it allows', () {
    test('as JSON, read back the same', () {
      for (final DVWasmEngines engines in <DVWasmEngines>[
        DVWasmEngines.all,
        DVWasmEngines.chromiumOnly,
        const DVWasmEngines(webkit: false),
        const DVWasmEngines(gecko: false),
      ]) {
        expect(DVWasmEngines.fromJson(jsonDecode(jsonEncode(engines.toJson()))),
            engines);
      }
    });

    test('and a manifest that does not say means Chromium only', () {
      // What flutter.js itself allows, and what a build from before this
      // release did.
      expect(DVWasmEngines.fromJson(null), DVWasmEngines.chromiumOnly);
      expect(DVWasmEngines.fromJson('strange'), DVWasmEngines.chromiumOnly);
    });

    test("a server names a route's modules behind the build's own decision",
        () {
      final DVRoutePreloads preloads = DVRoutePreloads.parse('''
{"wasmEngines": {"webkit": true, "gecko": false},
 "routes": {"/": {"wasm": ["main.dart_module3.wasm"]}}}
''');
      expect(
          preloads.linksFor('/'),
          '${dvWasmModulePreloads(<String>['main.dart_module3.wasm'], const DVWasmEngines(gecko: false))}\n');
    });
  });
}
