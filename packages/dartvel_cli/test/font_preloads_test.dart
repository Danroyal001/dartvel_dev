// The fonts a Flutter web page draws with are asked for only after the app
// has booted: main.dart.wasm (or .js) downloads, compiles and runs, reads
// FontManifest.json, and only then fetches every font in it -- and the engine
// waits for all of them before its first frame. Measured on sigmadev.digital,
// Fast 3G, 4x slower CPU: the fonts started 25 s into the load and the first
// frame waited another 5 s for them.
//
// The build knows the manifest, so every page names the fonts in its head and
// they download beside the app instead of after it. At low priority, so the
// app's own code keeps the network first; asked for exactly as the engine
// asks (fetch(), a CORS request even to its own site), or the browser does not
// hand the preload over and the font downloads twice.
import 'package:dartvel_cli/src/build/font_preloads.dart';
import 'package:test/test.dart';

const String manifest = '[{"family":"MaterialIcons","fonts":[{"asset":"dartvel/fonts/MaterialIcons-Regular.ee49.woff2"}]},'
    '{"family":"InterVariable","fonts":[{"asset":"dartvel/fonts/InterVariable.4146.woff2"}]},'
    '{"family":"Inter","fonts":[{"asset":"dartvel/fonts/InterVariable.4146.woff2"}]},'
    '{"family":"SpaceGrotesk","fonts":[{"weight":300,"asset":"dartvel/fonts/SpaceGrotesk Light.woff2"},{"asset":"dartvel/fonts/SpaceGrotesk-Regular.woff2"}]}]';

const String page = '<!DOCTYPE html><html><head><base href="/"><meta charset="UTF-8">'
    '<title>Home</title></head><body><p>Hi</p></body></html>';

void main() {
  test('every font the manifest lists, once, at the address the engine asks for', () {
    expect(dvFontPreloadHrefs(manifest), <String>[
      'assets/dartvel/fonts/MaterialIcons-Regular.ee49.woff2',
      'assets/dartvel/fonts/InterVariable.4146.woff2',
      'assets/dartvel/fonts/SpaceGrotesk%20Light.woff2',
      'assets/dartvel/fonts/SpaceGrotesk-Regular.woff2',
    ]);
  });

  test('an unreadable manifest names nothing', () {
    expect(dvFontPreloadHrefs('not json'), isEmpty);
    expect(dvFontPreloadHrefs('{"family":"x"}'), isEmpty);
  });

  test('the head asks for each font as a low-priority CORS fetch', () {
    final String html =
        dvApplyFontPreloads(page, dvFontPreloadHrefs(manifest));
    final Iterable<String> links = RegExp(r'<link rel="preload"[^>]*>')
        .allMatches(html)
        .map((Match m) => m[0]!);
    expect(links, hasLength(4));
    for (final String link in links) {
      expect(link, contains('as="fetch"'));
      expect(link, contains('crossorigin="anonymous"'));
      expect(link, contains('fetchpriority="low"'));
    }
    expect(html.indexOf('InterVariable'), lessThan(html.indexOf('</head>')));
  });

  test('a second build replaces the first one\'s list instead of adding to it', () {
    final String once = dvApplyFontPreloads(page, dvFontPreloadHrefs(manifest));
    final String twice = dvApplyFontPreloads(once, <String>['assets/a.woff2']);
    expect(RegExp('rel="preload"').allMatches(twice), hasLength(1));
    expect(twice, contains('assets/a.woff2'));
  });

  test('no fonts leaves the page exactly as it was', () {
    expect(dvApplyFontPreloads(page, const <String>[]), page);
  });

  test('a page with no head is left alone', () {
    const String bare = '<p>no head</p>';
    expect(dvApplyFontPreloads(bare, <String>['assets/a.woff2']), bare);
  });
}
