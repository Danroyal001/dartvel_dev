// `dartvel.web.renderer: wasm` builds the web app twice: dart2wasm with the
// skwasm renderer for browsers that have WasmGC, and dart2js with CanvasKit
// for the rest, and flutter.js picks one per browser. What goes wrong
// silently is the page around it: a preload for the wrong file is megabytes
// downloaded for nothing, and code a static build must not carry could end up
// in a module nobody checks.
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
  group('dartvel.web.renderer', () {
    test('is CanvasKit unless the application asks for wasm', () {
      expect(dvWebRenderer(null), DVWebRenderer.canvasKit);
      expect(dvWebRenderer('canvaskit'), DVWebRenderer.canvasKit);
      expect(dvWebRenderer('wasm'), DVWebRenderer.wasm);
      expect(dvWebRenderer('WASM'), DVWebRenderer.wasm);
    });

    test('a value it does not know stops the build instead of being ignored', () {
      // "skwasm" or a typo quietly building CanvasKit would look like wasm
      // made no difference.
      expect(() => dvWebRenderer('skwasm'), throwsFormatException);
      expect(() => dvWebRenderer('html'), throwsFormatException);
      expect(() => dvWebRenderer(true), throwsFormatException);
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

  group('what wasm cannot carry yet', () {
    test('a build that serves Studio is refused before anything compiles', () {
      // Studio's screens are kept out of the public web root by moving the
      // dart2js parts only Studio loads. dart2wasm writes one module, so
      // Studio's code would be in main.dart.wasm, served to every visitor.
      final String? refusal = dvWasmRefusal(servesStudio: true);
      expect(refusal, isNotNull);
      expect(refusal, contains('Studio'));
      expect(dvWasmRefusal(servesStudio: false), isNull);
    });
  });
}
