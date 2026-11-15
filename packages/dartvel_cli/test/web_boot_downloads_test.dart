// Every file a page boots from is downloaded once.
//
// sigmadev.digital's logs, Meta ad visitors on Android: the page preloaded
// `main.dart.mjs` and `main.dart.wasm` by their plain names while
// flutter_bootstrap.js asked for `main.dart.mjs?v=<build>` and
// `main.dart.wasm?v=<build>`. Two URLs are two cache keys, so every Chromium
// visitor downloaded the 1 MB app twice, and on a slow phone the second copy
// queued behind the first.
//
// The page's own scripts are run under node with a browser's navigator and a
// document that records the links they add, and the loader's URLs are read
// from the bootstrap the build writes. A preload that does not name a URL the
// loader asks for is a second download.
import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/build/native_splash.dart';
import 'package:dartvel_cli/src/build/pwa_service_worker.dart';
import 'package:test/test.dart';

const String _index = '''
<!DOCTYPE html>
<html>
<head>
  <base href="/">
  <meta charset="UTF-8">
  <title>app</title>
</head>
<body>
  <script src="flutter_bootstrap.js" async></script>
</body>
</html>
''';

const String _bootstrap = '_flutter.buildConfig = {"engineRevision":"e","builds":['
    '{"compileTarget":"dart2wasm","renderer":"skwasm","mainWasmPath":"main.dart.wasm",'
    '"jsSupportRuntimePath":"main.dart.mjs"},'
    '{"compileTarget":"dart2js","renderer":"canvaskit","mainJsPath":"main.dart.js"}]};\n'
    '_flutter.loader.load({config: {canvasKitBaseUrl: "canvaskit/"}});';

/// Android WebView in Facebook's in-app browser: Blink, so the loader picks
/// the wasm build.
const String _facebookAndroid =
    'Mozilla/5.0 (Linux; Android 16; SM-A155F Build/BP4A.251205.006; wv) '
    'AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/156.0.8078.47 '
    'Mobile Safari/537.36[FBAN/EMA;FBLC/en_GB;FBAV/538.0.0.10.110;FBCX/modulariab;]';

const String _safari =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 '
    '(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1';

void main() {
  if (_node() == null) {
    test('the page scripts run', () {},
        skip: 'node is not on PATH, so the page scripts cannot be run');
    return;
  }

  final DVSplash splash = DVSplash.fromConfig(const <String, Object?>{}, root: '.');
  final String page = dvVersionIndexHtml(
      dvWebSplashApply(_index, splash, wasm: true), 'b7');
  final Map<String, Object?> config = _buildConfig(dvVersionBootstrap(_bootstrap, 'b7'));
  final List<Map<String, Object?>> builds =
      (config['builds']! as List<Object?>).cast<Map<String, Object?>>();
  final Map<String, Object?> wasmBuild =
      builds.firstWhere((Map<String, Object?> b) => b['compileTarget'] == 'dart2wasm');
  final Map<String, Object?> jsBuild =
      builds.firstWhere((Map<String, Object?> b) => b['compileTarget'] == 'dart2js');

  test('a phone on Blink preloads the wasm app at the URLs the loader asks for', () {
    final List<String> preloaded = _appPreloads(page, vendor: 'Google Inc.', userAgent: _facebookAndroid);
    // The page did ask for the app early: an empty list would pass anything.
    expect(preloaded, isNotEmpty);
    final Set<String> loader = <String>{
      wasmBuild['mainWasmPath']! as String,
      wasmBuild['jsSupportRuntimePath']! as String,
    };
    for (final String href in preloaded) {
      expect(loader, contains(href),
          reason: 'the page preloads $href but the loader asks for $loader: '
              'two URLs, two downloads');
    }
  });

  test('a browser without WasmGC preloads main.dart.js at the URL the loader asks for', () {
    final List<String> preloaded = _appPreloads(page, vendor: 'Apple Computer, Inc.', userAgent: _safari);
    expect(preloaded, <String>[jsBuild['mainJsPath']! as String]);
  });

  test('a page rebuilt over its own output names the new build only', () {
    final String again = dvVersionIndexHtml(page, 'b8');
    final List<String> preloaded = _appPreloads(again, vendor: 'Google Inc.', userAgent: _facebookAndroid);
    expect(preloaded, isNotEmpty);
    for (final String href in preloaded) {
      expect(href, endsWith('?v=b8'));
    }
  });

  test('text on the page that mentions main.dart.js is not rewritten', () {
    // A docs page explaining the build output is content, not a preload.
    const String docs = '<html><head><meta charset="UTF-8"></head><body>'
        '<p>The compiler writes "main.dart.js" and "main.dart.wasm".</p></body></html>';
    expect(dvVersionIndexHtml(docs, 'b7'), docs);
  });
}

Map<String, Object?> _buildConfig(String bootstrap) {
  final RegExpMatch match =
      RegExp(r'_flutter\.buildConfig\s*=\s*(\{[^\n]*\})\s*;').firstMatch(bootstrap)!;
  return (jsonDecode(match.group(1)!) as Map<Object?, Object?>).cast<String, Object?>();
}

/// The app-code URLs (main.dart.*) the inline scripts in [html]'s head add
/// preload links for, in a browser with [vendor] and [userAgent].
List<String> _appPreloads(String html, {required String vendor, required String userAgent}) {
  final String head = html.substring(0, html.indexOf('</head>'));
  final List<String> scripts = <String>[
    for (final RegExpMatch m in RegExp(r'<script>([\s\S]*?)</script>').allMatches(head)) m.group(1)!,
  ];
  // Static links count as well: they are preloads the browser makes itself.
  final List<String> staticLinks = <String>[
    for (final RegExpMatch m in RegExp(r'''<link\b[^>]*\brel="(?:module)?preload"[^>]*\bhref="([^"]+)"''')
        .allMatches(head))
      m.group(1)!,
  ];
  final Directory dir = Directory.systemTemp.createTempSync('dv-boot-');
  try {
    final File script = File('${dir.path}/run.mjs')
      ..writeAsStringSync('''
const links = [];
const head = { appendChild(l) { links.push(l.href); } };
Object.defineProperty(globalThis, "navigator", { configurable: true, value: { vendor: ${jsonEncode(vendor)}, userAgent: ${jsonEncode(userAgent)} } });
globalThis.document = {
  head,
  documentElement: { setAttribute() {}, removeAttribute() {} },
  createElement() { return {}; },
  getElementById() { return null; },
};
globalThis.addEventListener = () => {};
globalThis.matchMedia = () => ({ matches: false });
globalThis.ImageDecoder = function () {};
if (${jsonEncode(vendor)} !== 'Google Inc.') {
  // WasmGC is what tells the loader to pick wasm; a browser without it.
  WebAssembly.validate = () => false;
}
for (const source of ${jsonEncode(scripts)}) {
  try { (0, eval)(source); } catch (e) { console.error(String(e)); }
}
console.log(JSON.stringify(links));
''');
    final ProcessResult result = Process.runSync(_node()!, <String>[script.path]);
    if (result.exitCode != 0) fail('the page scripts did not run:\n${result.stderr}');
    final List<String> added =
        (jsonDecode('${result.stdout}'.trim().split('\n').last) as List<Object?>).cast<String>();
    return <String>[
      for (final String href in <String>[...staticLinks, ...added])
        if (RegExp(r'(^|/)main\.dart\.(js|mjs|wasm)(\?|$)').hasMatch(href)) href,
    ];
  } finally {
    dir.deleteSync(recursive: true);
  }
}

String? _node() {
  for (final String candidate in const <String>['node', 'nodejs']) {
    try {
      if (Process.runSync(candidate, const <String>['--version']).exitCode == 0) return candidate;
    } on ProcessException {
      continue;
    }
  }
  return null;
}
