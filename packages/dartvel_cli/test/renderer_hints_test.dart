// The renderer is the largest thing a Flutter web page downloads -- CanvasKit
// is 7 MB -- and nothing asked for it until flutter_bootstrap.js had arrived
// and run. The page's HTML now opens the connection to where it lives and
// starts the download itself, during the parse.
//
// A guess here is not cheap. Preloading the variant the loader will not use
// is a 7 MB download for nothing, so the page chooses exactly as the loader
// does, and the build writes no hint at all when the application's loader
// configuration could make it choose differently.
import 'package:dartvel_cli/src/build/renderer_hints.dart';
import 'package:test/test.dart';

/// The tail of the flutter_bootstrap.js `flutter build web` writes.
const String defaultBootstrap = '''
(function(){/* flutter.js, minified: ...useLocalCanvasKit?I("https://www.gstatic.com/flutter-canvaskit",e.engineRevision):"canvaskit"... */})();
if (!window._flutter) {
  window._flutter = {};
}
_flutter.buildConfig = {"engineRevision":"83675ed27633283e7fc296c8bca22e841224c096","builds":[{"compileTarget":"dart2js","renderer":"canvaskit","mainJsPath":"main.dart.js"},{}]};

_flutter.loader.load({
  serviceWorkerSettings: {
    serviceWorkerVersion: "2454317734"
  }
});
''';

String withLoad(String config) => defaultBootstrap.replaceFirst(
      RegExp(r'_flutter\.loader\.load\(\{[\s\S]*\}\);'),
      '_flutter.loader.load({$config});',
    );

const String shell = '<!DOCTYPE html>\n<html>\n<head>\n'
    '  <base href="/">\n  <meta charset="UTF-8">\n  <title>Site</title>\n'
    '</head>\n<body></body>\n</html>';

void main() {
  group('which renderer the build can name', () {
    test('the engine revision of a default CanvasKit build', () {
      expect(dvCanvasKitRevision(defaultBootstrap),
          '83675ed27633283e7fc296c8bca22e841224c096');
    });

    test('none for a build that is not CanvasKit on dart2js', () {
      // A --wasm build loads skwasm, from other files.
      expect(
        dvCanvasKitRevision(defaultBootstrap.replaceFirst(
            '"compileTarget":"dart2js","renderer":"canvaskit"',
            '"compileTarget":"dart2wasm","renderer":"skwasm"')),
        isNull,
      );
    });

    test('none without a build configuration to read', () {
      expect(dvCanvasKitRevision('_flutter.loader.load({});'), isNull);
    });

    test('none when the loader is told where CanvasKit lives or which kind',
        () {
      // Each of these moves the file the loader fetches away from the one a
      // hint would name.
      for (final String config in <String>[
        'canvasKitBaseUrl: "/ck/"',
        'config: { canvasKitVariant: "full" }',
        'config: { useLocalCanvasKit: true }',
        'config: { renderer: "skwasm" }',
      ]) {
        expect(dvCanvasKitRevision(withLoad(config)), isNull, reason: config);
      }
    });

    test('the loader\'s own code mentioning those names does not count', () {
      // flutter.js itself reads useLocalCanvasKit; only the application's
      // call to load() can set it.
      expect(defaultBootstrap, contains('useLocalCanvasKit'));
      expect(dvCanvasKitRevision(defaultBootstrap), isNotNull);
    });
  });

  group('the hints', () {
    final String block =
        dvRendererHints('83675ed27633283e7fc296c8bca22e841224c096');

    test('open the connection to where CanvasKit is served', () {
      expect(block,
          contains('<link rel="preconnect" href="https://www.gstatic.com" '
              'crossorigin>'));
    });

    test('name this build\'s revision', () {
      expect(
          block,
          contains('https://www.gstatic.com/flutter-canvaskit/'
              '83675ed27633283e7fc296c8bca22e841224c096/'));
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
