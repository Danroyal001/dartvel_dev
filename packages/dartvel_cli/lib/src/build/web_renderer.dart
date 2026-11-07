/// Which renderer a Dartvel web build compiles for: `dartvel.web.renderer`.
///
/// `canvaskit` (the default) is one app: dart2js with the CanvasKit
/// renderer, on every browser.
///
/// `wasm` is `flutter build web --wasm`: two apps in one build. A Chromium
/// browser with WasmGC (Chrome, Edge and Chrome for Android 119+) runs
/// dart2wasm with the skwasm renderer; Firefox and Safari, which flutter.js
/// leaves off its default wasm allow list, and every older browser get the
/// dart2js and CanvasKit app they would have got anyway. flutter.js chooses
/// per browser, at load. Nothing about the page around it changes: the same
/// prerendered HTML, first-frame pictures and splash come first, and the
/// app takes over in place.
library;

import 'dart:convert';

/// The renderers `dartvel.web.renderer` names.
enum DVWebRenderer {
  /// dart2js and CanvasKit, everywhere.
  canvasKit,

  /// dart2wasm and skwasm where the browser has WasmGC, dart2js and
  /// CanvasKit elsewhere.
  wasm,
}

/// `dartvel.web.renderer` read from pubspec: null is the default.
///
/// Anything else is a [FormatException], so a misspelling stops the build
/// rather than quietly building CanvasKit.
DVWebRenderer dvWebRenderer(Object? value) {
  if (value == null) return DVWebRenderer.canvasKit;
  if (value is String) {
    switch (value.trim().toLowerCase()) {
      case 'canvaskit':
        return DVWebRenderer.canvasKit;
      case 'wasm':
        return DVWebRenderer.wasm;
    }
  }
  throw FormatException('dartvel.web.renderer is canvaskit (the default) or '
      'wasm, not "$value". wasm compiles a WebAssembly app for browsers with '
      'WasmGC and keeps the CanvasKit app for the rest.');
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

/// Why this build cannot compile to wasm, or null when it can.
///
/// Studio's screens are a deferred library, and a web-server build keeps
/// them out of the public web root by moving the dart2js parts only Studio
/// loads. dart2wasm does not split a deferred library into a module of its
/// own, so Studio's code would be inside main.dart.wasm, which every
/// visitor downloads.
String? dvWasmRefusal({required bool servesStudio}) {
  if (!servesStudio) return null;
  return 'dartvel.web.renderer: wasm cannot be used by a build that serves '
      "Studio yet: dart2wasm compiles Studio's screens into main.dart.wasm, "
      'which every visitor downloads, where dart2js keeps them in parts only '
      'a signed-in session is sent. Build with the default renderer, or turn '
      'Studio off (dartvel.admin.enabled: false) for this site.';
}
