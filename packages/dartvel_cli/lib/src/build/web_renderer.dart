/// Whether a Dartvel web build compiles to WebAssembly: `dartvel.web.wasm`.
///
/// On by default. A wasm build is `flutter build web --wasm`: two apps in one
/// build. A Chromium browser with WasmGC (Chrome, Edge and Chrome for Android
/// 119+) runs dart2wasm with the skwasm renderer; Firefox and Safari, which
/// flutter.js leaves off its default wasm allow list, and every older browser
/// get the dart2js and CanvasKit app. flutter.js chooses per browser, at load.
/// Nothing about the page around it changes: the same prerendered HTML
/// and splash come first, and the app takes over in place.
///
/// `dartvel.web.wasm: false` builds the dart2js and CanvasKit app alone.
library;

import 'dart:convert';

/// `dartvel.web.wasm` read from pubspec: true unless it is false.
///
/// Anything but a boolean is a [FormatException], so `wasm: "no"` stops the
/// build rather than quietly building wasm.
bool dvWebWasm(Object? value) {
  if (value == null) return true;
  if (value is bool) return value;
  throw FormatException('dartvel.web.wasm is true (the default) or false, not '
      '"$value". false builds the dart2js and CanvasKit app alone; true adds '
      'the WebAssembly app that browsers with WasmGC run.');
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
