/// Whether a Dartvel web build compiles to WebAssembly: `dartvel.web.wasm`.
///
/// On by default. A wasm build is `flutter build web --wasm`: two apps in one
/// build. Chromium browsers with WasmGC (Chrome, Edge and Chrome for Android
/// 119+), Safari 26.2+ (and every iOS browser on that WebKit) and Firefox
/// 147+ run dart2wasm with the skwasm renderer; every other browser gets the
/// dart2js and CanvasKit app. flutter.js chooses per browser, at load, from
/// the allow list the build writes into its bootstrap
/// ([dvBootstrapWithLoaderConfig]). Nothing about the page around it
/// changes: the same prerendered HTML and splash come first, and the app
/// takes over in place.
///
/// `dartvel.web.wasm: false` builds the dart2js and CanvasKit app alone;
/// `dartvel.web.wasm: {safari: false, firefox: false}` keeps those on
/// dart2js (either key alone does one).
library;

import 'dart:convert';

import 'package:dartvel_core/dartvel.dart' show DVWasmEngines, dvWebkitWasmGateJs;

/// `dartvel.web.wasm` read from pubspec: true unless it is false.
///
/// Anything but a boolean or a map of browsers is a [FormatException], so
/// `wasm: "no"` stops the build rather than quietly building wasm.
bool dvWebWasm(Object? value) => dvWebWasmEngines(value) != null;

/// The engines besides Chromium `dartvel.web.wasm` lets run the wasm app,
/// or null for `false` (no wasm app).
///
/// `true` or nothing is [DVWasmEngines.all]; a map takes `safari` and
/// `firefox`, each true (the default) or false. Anything else -- another
/// key, a value that is not a boolean -- is a [FormatException].
DVWasmEngines? dvWebWasmEngines(Object? value) {
  if (value == null || value == true) return DVWasmEngines.all;
  if (value == false) return null;
  if (value is Map) {
    bool engine(String key) {
      final Object? setting = value[key];
      if (setting == null) return true;
      if (setting is bool) return setting;
      throw FormatException('dartvel.web.wasm.$key is true (the default) or '
          'false, not "$setting".');
    }

    for (final Object? key in value.keys) {
      if (key != 'safari' && key != 'firefox') {
        throw FormatException('dartvel.web.wasm has no "$key". It takes '
            'safari and firefox, each true (the default) or false; Chromium '
            'browsers run the wasm app whenever it is built.');
      }
    }
    return DVWasmEngines(webkit: engine('safari'), gecko: engine('firefox'));
  }
  throw FormatException('dartvel.web.wasm is true (the default), false, or '
      'a map of safari and firefox, not "$value". false builds the dart2js '
      'and CanvasKit app alone; true adds the WebAssembly app that Chromium, '
      'Safari 26.2+ and Firefox 147+ run.');
}

/// Marks what the build adds to `flutter_bootstrap.js`
/// ([dvBootstrapWithLoaderConfig]), so a second build replaces it.
const String dvLoaderConfigMarker = '/* dartvel: loader config */';

final RegExp _loaderConfig = RegExp(
    '\\n?${RegExp.escape(dvLoaderConfigMarker)}\\n[^\\n]*\\n');

final RegExp _buildConfigLine =
    RegExp(r'_flutter\.buildConfig\s*=\s*\{[^\n]*\}\s*;[^\n]*\n?');

/// [bootstrap] (the `flutter_bootstrap.js` Flutter wrote) with the loader
/// options Dartvel adds, right after the build config, before the
/// application's own `_flutter.loader.load(...)`:
///
///  * `wasmAllowList`: WebKit (Safari 26.2+, by [dvWebkitWasmGateJs], for
///    flutter.js has no version test of its own) and Gecko (flutter.js
///    keeps Firefox before 147 off itself), as [engines] allows;
///  * `wasmDeferredModulesLoader`: fetches each deferred module once, from
///    beside the app (the loader's `entrypointBaseUrl`), and forgets one
///    that failed so the next ask tries again. flutter.js's own fetches a
///    module every time one is asked for, and every page library names the
///    shared modules it needs as well as its own.
///
/// What the application passes itself wins: its own allow-list entries and
/// its own loader. A bootstrap without a build config is returned as it was.
String dvBootstrapWithLoaderConfig(String bootstrap, DVWasmEngines engines) {
  final String cleared = bootstrap.replaceFirst(_loaderConfig, '\n');
  final RegExpMatch? config = _buildConfigLine.firstMatch(cleared);
  if (config == null) return bootstrap;
  final String line = '(()=>{const w=${jsonEncode(engines.toJson())};'
      'const l=_flutter.loader,load=l.load.bind(l);'
      'l.load=(o={})=>{const c={...(o.config||{})};'
      'c.wasmAllowList={webkit:w.webkit&&$dvWebkitWasmGateJs,gecko:w.gecko,'
      '...(c.wasmAllowList||{})};'
      'if(!c.wasmDeferredModulesLoader){'
      'const m=new Map(),b=c.entrypointBaseUrl||c.entryPointBaseUrl;'
      'c.wasmDeferredModulesLoader=(names,instantiate)=>Promise.all('
      'names.map((n)=>{if(!m.has(n)){'
      r'const u=new URL(b?b.replace(/\/+$/,"")+"/"+n:n,document.baseURI);'
      'm.set(n,(async()=>instantiate(n,await fetch(u)))()'
      '.catch((e)=>{m.delete(n);throw e;}));}'
      'return m.get(n);}));}'
      'return load({...o,config:c});};})();';
  final String head = cleared.substring(0, config.end);
  final String separator = head.endsWith('\n') ? '' : '\n';
  final String result = '$head$separator$dvLoaderConfigMarker\n$line\n'
      '${cleared.substring(config.end)}';
  return result == bootstrap ? bootstrap : result;
}

/// The engines a build's [bootstrap] lets run the wasm app, as
/// [dvBootstrapWithLoaderConfig] wrote them; [DVWasmEngines.chromiumOnly]
/// (flutter.js's own default) for a bootstrap it did not touch.
DVWasmEngines dvBootstrapWasmEngines(String bootstrap) {
  final RegExpMatch? match = RegExp(
          '${RegExp.escape(dvLoaderConfigMarker)}\\n\\(\\(\\)=>\\{const w=(\\{[^}]*\\});')
      .firstMatch(bootstrap);
  if (match == null) return DVWasmEngines.chromiumOnly;
  try {
    return DVWasmEngines.fromJson(jsonDecode(match.group(1)!));
  } on FormatException {
    return DVWasmEngines.chromiumOnly;
  }
}

/// Whether the flutter_bootstrap.js a build wrote has a dart2wasm build in
/// it. Only the build config is read: flutter.js itself names every
/// compile target.
bool dvBuildCompilesToWasm(String bootstrapJs) {
  final RegExpMatch? config =
      RegExp(r'_flutter\.buildConfig\s*=\s*(\{[^\n]*\})\s*;')
          .firstMatch(bootstrapJs);
  if (config == null) return false;
  final Object? json;
  try {
    json = jsonDecode(config.group(1)!);
  } on FormatException {
    return false;
  }
  if (json is! Map) return false;
  final Object? builds = json['builds'];
  if (builds is! List) return false;
  return builds.any(
      (Object? build) => build is Map && build['compileTarget'] == 'dart2wasm');
}

/// `dartvel.web.deprecatedJsInterop` read from pubspec: false unless it is
/// true.
///
/// False builds the dart2js app with `--no-deprecated-js-interop`, so
/// `dart:html`, `dart:js` and `dart:js_util` are a compile error there as they
/// always are in the WebAssembly app: code that imports one fails the build
/// instead of working in Firefox's dart2js app and failing in Chrome's wasm
/// one. True leaves the compiler's default, for a project whose dependencies
/// still import them. Anything but a boolean is a [FormatException].
bool dvWebDeprecatedJsInterop(Object? value) {
  if (value == null) return false;
  if (value is bool) return value;
  throw FormatException('dartvel.web.deprecatedJsInterop is false (the '
      'default) or true, not "$value". false refuses dart:html, dart:js and '
      'dart:js_util in the dart2js app; true allows them.');
}
