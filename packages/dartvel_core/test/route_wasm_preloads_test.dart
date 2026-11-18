// A page of the WebAssembly app names the deferred modules its route needs.
//
// Every Dartvel page is a deferred import, and with dart2wasm's deferred
// loading its code is in main.dart_module<N>.wasm files that loadLibrary()
// fetches only once main.dart.wasm has downloaded, compiled and run -- and
// then in waves, each a round trip. Measured on sigmadev.digital (Fast 3G,
// CPU 4x): the home page's 30-odd modules started 35 s into the load, in
// three waves of 0.6 s round trips each (2 s each on Slow 3G).
//
// The build knows which modules each route's import needs from the map
// dart2wasm writes, so the page asks for them while the app downloads. Only
// in a browser that will run the wasm app: everywhere else they would be
// bytes for nothing, so the decision is the same one the splash makes for
// main.dart.wasm.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const String manifest = '''
{"routes": {
  "/": {"scripts": [], "wasm": ["main.dart_module3.wasm", "main.dart_module7.wasm"], "images": []},
  "/docs": {"scripts": [], "wasm": [], "images": [{"url": "assets/a.png", "as": "fetch"}]},
  "/evil": {"scripts": [], "wasm": ["</script><script>alert(1)</script>.wasm"], "images": []}
}}
''';

/// The detector the splash uses to preload main.dart.wasm.
const String wasmDetector = '(n.vendor==="Google Inc."||n.userAgent.indexOf("Edg/")>=0)'
    '&&WebAssembly.validate(new Uint8Array([0,97,115,109,1,0,0,0,1,5,1,95,1,120,0]))';

void main() {
  final DVRoutePreloads preloads = DVRoutePreloads.parse(manifest);

  test('a route\'s modules are named, behind the wasm decision', () {
    final String links = preloads.linksFor('/');
    expect(links, contains('main.dart_module3.wasm'));
    expect(links, contains('main.dart_module7.wasm'));
    // Not as plain links: a browser running dart2js would download them.
    expect(links, isNot(contains('<link rel="preload" href="main.dart_module')));
    expect(links, contains('<script>'));
    expect(links, contains(wasmDetector));
    // Fetched the way the module loader fetches them: fetch(), anonymous CORS.
    expect(links, contains('"fetch"'));
    expect(links, contains('crossOrigin="anonymous"'));
  });

  test('the same script as the static build writes', () {
    expect(preloads.linksFor('/'),
        '${dvWasmModulePreloads(<String>['main.dart_module3.wasm', 'main.dart_module7.wasm'])}\n');
  });

  test('no modules, no script', () {
    expect(preloads.linksFor('/docs'), isNot(contains('<script')));
    expect(dvWasmModulePreloads(const <String>[]), isEmpty);
  });

  test('a module name cannot end the script it is in', () {
    final String links = preloads.linksFor('/evil');
    expect(RegExp('</script', caseSensitive: false).allMatches(links), hasLength(1));
  });
  test('they start only once the app and the renderer have downloaded', () {
    // On a slow network every byte competes: preloaded modules shared the
    // line with main.dart.wasm and delayed it by 10 s on Slow 3G. The app and
    // its renderer go first; the rest follows the moment both are in.
    final String script = dvWasmModulePreloads(<String>['main.dart_module3.wasm']);
    expect(script, contains(dvAfterBootDownloadsDetector));
    expect(script.indexOf(dvAfterBootDownloadsDetector),
        lessThan(script.indexOf('main.dart_module3.wasm')));
  });

  test('the wait recognises both renderers and both app builds', () {
    for (final String name in <String>[
      'main.dart.wasm', 'main.dart.wasm?v=1', 'main.dart.js', 'main.dart.js?v=2',
    ]) {
      expect(RegExp(dvBootAppPattern).hasMatch(name), isTrue, reason: name);
    }
    for (final String name in <String>[
      'canvaskit/skwasm.wasm', 'canvaskit/skwasm_heavy.wasm',
      'canvaskit/canvaskit.wasm', 'canvaskit/chromium/canvaskit.wasm',
    ]) {
      expect(RegExp(dvBootRendererPattern).hasMatch(name), isTrue, reason: name);
    }
    expect(RegExp(dvBootAppPattern).hasMatch('main.dart_module3.wasm'), isFalse);
    expect(RegExp(dvBootAppPattern).hasMatch('main.dart.mjs'), isFalse);
  });
}
