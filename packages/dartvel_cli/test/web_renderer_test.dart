// A Dartvel web build is WebAssembly by default: dart2wasm with the skwasm
// renderer for browsers that have WasmGC, and dart2js with CanvasKit for the
// rest, from one build, and flutter.js picks one per browser.
// `dartvel.web.wasm: false` builds dart2js alone. What goes wrong silently is
// the page around it: a preload for the wrong file is megabytes downloaded
// for nothing, and code a static build must not carry could end up in a
// module nobody checks.
import 'package:dartvel_cli/src/build/web_renderer.dart';
import 'package:dartvel_cli/src/commands/build_command.dart';
import 'package:test/test.dart';

/// What `flutter build web --wasm` writes into flutter_bootstrap.js.
const String wasmBootstrap = '''
(function(){/* flutter.js */})();
_flutter.buildConfig = {"engineRevision":"af7e796e16","builds":[{"compileTarget":"dart2wasm","renderer":"skwasm","mainWasmPath":"main.dart.wasm","jsSupportRuntimePath":"main.dart.mjs"},{"compileTarget":"dart2js","renderer":"canvaskit","mainJsPath":"main.dart.js"}]};
_flutter.loader.load({config: {canvasKitBaseUrl: "canvaskit/"}});
''';

/// And what a plain `flutter build web` writes.
const String jsBootstrap = '''
(function(){/* flutter.js mentions dart2wasm and skwasm too */})();
_flutter.buildConfig = {"engineRevision":"af7e796e16","builds":[{"compileTarget":"dart2js","renderer":"canvaskit","mainJsPath":"main.dart.js"},{}]};
_flutter.loader.load({});
''';

void main() {
  group('dartvel.web.wasm', () {
    test('is on unless the application turns it off', () {
      expect(dvWebWasm(null), isTrue);
      expect(dvWebWasm(true), isTrue);
      expect(dvWebWasm(false), isFalse);
    });

    test('a value that is not true or false stops the build', () {
      // "no" or "off" quietly building wasm would look like the opt-out
      // made no difference.
      expect(() => dvWebWasm('no'), throwsFormatException);
      expect(() => dvWebWasm('false'), throwsFormatException);
      expect(() => dvWebWasm(0), throwsFormatException);
    });
  });

  group('the Flutter build', () {
    test('asks for --wasm on web and web-server only when wasm is chosen', () {
      for (final String platform in <String>['web', 'web-server']) {
        expect(
            resolveFlutterBuildArguments(
                platform: platform, buildMode: '--release', wasm: true),
            contains('--wasm'),
            reason: platform);
        expect(
            resolveFlutterBuildArguments(
                platform: platform, buildMode: '--release'),
            isNot(contains('--wasm')),
            reason: platform);
      }
      // Nothing but the web compiles to WebAssembly here.
      expect(
          resolveFlutterBuildArguments(
              platform: 'android', buildMode: '--release', wasm: true),
          isNot(contains('--wasm')));
    });
  });

  group('reading what the build produced', () {
    test('a --wasm build is recognised from its build config', () {
      expect(dvBuildCompilesToWasm(wasmBootstrap), isTrue);
    });

    test('a dart2js build is not, though flutter.js names dart2wasm', () {
      expect(dvBuildCompilesToWasm(jsBootstrap), isFalse);
      expect(dvBuildCompilesToWasm(''), isFalse);
      expect(dvBuildCompilesToWasm('_flutter.buildConfig = {not json};'),
          isFalse);
    });
  });
}
