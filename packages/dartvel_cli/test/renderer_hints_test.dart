// The renderer is the largest thing a Flutter web page downloads -- CanvasKit
// is 7 MB, skwasm 3.5 MB -- and nothing asked for it until
// flutter_bootstrap.js had arrived and run. The page's HTML now opens the
// connection to where it lives and starts the download itself, during the
// parse.
//
// A guess here is not cheap. Preloading the renderer the loader will not use
// is megabytes for nothing, so the page chooses exactly as the loader does --
// skwasm or CanvasKit, and which build of each -- and the build writes no
// hint at all when the application's loader configuration could make it
// choose differently.
import 'package:dartvel_cli/src/build/renderer_hints.dart';
import 'package:test/test.dart';

const String revision = '83675ed27633283e7fc296c8bca22e841224c096';

/// The tail of the flutter_bootstrap.js `flutter build web` writes.
const String defaultBootstrap = '''
(function(){/* flutter.js, minified: ...useLocalCanvasKit?I("https://www.gstatic.com/flutter-canvaskit",e.engineRevision):"canvaskit"... */})();
if (!window._flutter) {
  window._flutter = {};
}
_flutter.buildConfig = {"engineRevision":"$revision","builds":[{"compileTarget":"dart2js","renderer":"canvaskit","mainJsPath":"main.dart.js"},{}]};

_flutter.loader.load({
  serviceWorkerSettings: {
    serviceWorkerVersion: "2454317734"
  }
});
''';

/// The same from `flutter build web --wasm`.
final String wasmBootstrap = defaultBootstrap.replaceFirst(
    '"builds":[{"compileTarget":"dart2js","renderer":"canvaskit","mainJsPath":"main.dart.js"},{}]',
    '"builds":[{"compileTarget":"dart2wasm","renderer":"skwasm","mainWasmPath":"main.dart.wasm","jsSupportRuntimePath":"main.dart.mjs"},'
        '{"compileTarget":"dart2js","renderer":"canvaskit","mainJsPath":"main.dart.js"}]');

String withLoad(String bootstrap, String config) => bootstrap.replaceFirst(
      RegExp(r'_flutter\.loader\.load\(\{[\s\S]*\}\);'),
      '_flutter.loader.load({$config});',
    );

const String shell = '<!DOCTYPE html>\n<html>\n<head>\n'
    '  <base href="/">\n  <meta charset="UTF-8">\n  <title>Site</title>\n'
    '</head>\n<body></body>\n</html>';

void main() {
  group('where the renderer comes from', () {
    test('a default CanvasKit build loads it from gstatic, by revision', () {
      final DVRendererSource? source = dvRendererSource(defaultBootstrap);
      expect(source?.base,
          'https://www.gstatic.com/flutter-canvaskit/$revision/');
      expect(source?.wasm, isFalse);
    });

    test('a --wasm build has skwasm to name as well', () {
      final DVRendererSource? source = dvRendererSource(wasmBootstrap);
      expect(source?.base,
          'https://www.gstatic.com/flutter-canvaskit/$revision/');
      expect(source?.wasm, isTrue);
    });

    test('a site serving the renderer itself is named where it serves it', () {
      // canvasKitBaseUrl is where both the loader and the hint look.
      final DVRendererSource? source = dvRendererSource(
          withLoad(wasmBootstrap, 'config: { canvasKitBaseUrl: "canvaskit/" }'));
      expect(source?.base, 'canvaskit/');
      expect(source?.wasm, isTrue);
    });

    test('none without a build configuration to read', () {
      expect(dvRendererSource('_flutter.loader.load({});'), isNull);
    });

    test('none when the loader is told which kind or a place it cannot read', () {
      // Each of these moves the file the loader fetches away from the one a
      // hint would name.
      for (final String config in <String>[
        'config: { canvasKitBaseUrl: base }',
        'config: { canvasKitVariant: "full" }',
        'config: { useLocalCanvasKit: true }',
        'config: { renderer: "skwasm" }',
        'config: { wasmAllowList: { gecko: true } }',
      ]) {
        expect(dvRendererSource(withLoad(wasmBootstrap, config)), isNull,
            reason: config);
      }
    });

    test('the loader\'s own code mentioning those names does not count', () {
      // flutter.js itself reads useLocalCanvasKit; only the application's
      // call to load() can set it.
      expect(defaultBootstrap, contains('useLocalCanvasKit'));
      expect(dvRendererSource(defaultBootstrap), isNotNull);
    });
  });

  group('the hints for CanvasKit', () {
    final String block = dvRendererHints(const DVRendererSource(
        base: 'https://www.gstatic.com/flutter-canvaskit/$revision/',
        wasm: false));

    test('open the connection to where CanvasKit is served', () {
      expect(block,
          contains('<link rel="preconnect" href="https://www.gstatic.com" '
              'crossorigin>'));
    });

    test('name this build\'s revision', () {
      expect(block,
          contains('https://www.gstatic.com/flutter-canvaskit/$revision/'));
    });

    test('choose the variant with the loader\'s own test', () {
      // Blink by vendor or Edge's UA, ImageDecoder, and both ICU break
      // iterators: the conditions flutter.js checks before it takes the
      // smaller chromium build.
      for (final String check in <String>[
        'Google Inc.',
        'Edg/',
        'ImageDecoder',
        'v8BreakIterator',
        'Segmenter',
        'chromium/',
      ]) {
        expect(block, contains(check), reason: check);
      }
    });

    test('ask for each file the way the loader will', () {
      // The .wasm through fetch() and the .js through import(): a preload
      // requested any other way is not reused, and the file downloads twice.
      expect(block, contains('"modulepreload"'));
      expect(block, contains('canvaskit.js'));
      expect(block, contains('"fetch"'));
      expect(block, contains('canvaskit.wasm'));
      expect(block, contains('crossOrigin="anonymous"'));
    });

    test('a CanvasKit-only build never names skwasm', () {
      expect(block, isNot(contains('skwasm')));
    });
  });

  group('the hints for a --wasm build', () {
    final String block = dvRendererHints(
        const DVRendererSource(base: 'canvaskit/', wasm: true));

    test('name skwasm where the loader will run it, CanvasKit elsewhere', () {
      // Blink with WasmGC runs skwasm (the loader's default allow list and
      // its own detector bytes); every other browser falls back to CanvasKit.
      expect(block, contains('WebAssembly.validate'));
      expect(block, contains('skwasm'));
      expect(block, contains('canvaskit.wasm'));
    });

    test('choose skwasm or skwasm_heavy by the same test as the loader', () {
      // skwasm_heavy carries its own codecs and break iterators, for a
      // browser that lacks ImageDecoder or the ICU iterators.
      expect(block, contains('skwasm_heavy'));
      expect(block, contains('ImageDecoder'));
    });

    test('a site serving the renderer itself opens no other connection', () {
      expect(block, isNot(contains('preconnect')));
      expect(block, contains('"canvaskit/"'));
    });
  });

  group('the page', () {
    const String block = '<!-- dartvel:renderer -->\n<x>\n<!-- /dartvel:renderer -->';

    test('gets the hints right after its charset', () {
      // Not at the top of <head>: the charset has to be within the first
      // 1024 bytes, and the hints would push it past them.
      final String html = dvApplyRendererHints(shell, block);
      expect(html.indexOf('<x>'),
          greaterThan(html.indexOf('<meta charset="UTF-8">')));
      expect(html.indexOf('<x>'), lessThan(html.indexOf('<title>')));
    });

    test('a second build replaces the first one\'s hints', () {
      final String once = dvApplyRendererHints(shell, block);
      final String twice = dvApplyRendererHints(once, block);
      expect(twice, once);
    });

    test('no hints leaves the page as it was, and clears old ones', () {
      expect(dvApplyRendererHints(shell, null), shell);
      expect(dvApplyRendererHints(dvApplyRendererHints(shell, block), null),
          shell);
    });

    test('a page with no charset gets them at the top of its head', () {
      const String bare = '<html><head><title>x</title></head></html>';
      final String html = dvApplyRendererHints(bare, block);
      expect(html.indexOf('<x>'), greaterThan(html.indexOf('<head>')));
      expect(html.indexOf('<x>'), lessThan(html.indexOf('<title>')));
    });
  });
}
