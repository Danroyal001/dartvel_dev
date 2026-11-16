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
import 'dart:io';

import 'package:dartvel_cli/src/build/font_preloads.dart';
import 'package:dartvel_core/dartvel.dart' show dvAfterBootPreloadsBody;
import 'package:path/path.dart' as p;
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

  test('the head asks for the fonts once the app and renderer are in', () {
    // As plain preloads they started with the page and shared a slow line
    // with main.dart.wasm: 10 s later on Slow 3G. The same CORS fetches now
    // start the moment the app and its renderer have downloaded.
    final List<String> fonts = dvFontPreloadHrefs(manifest);
    final String html = dvApplyFontPreloads(page, fonts);
    expect(html, contains(dvAfterBootPreloadsBody(fonts)));
    expect(html, isNot(contains('<link rel="preload"')),
        reason: 'a link would start downloading with the page');
    expect(html.indexOf('InterVariable'), lessThan(html.indexOf('</head>')));
  });

  test('a second build replaces the first one\'s list instead of adding to it', () {
    final String once = dvApplyFontPreloads(page, dvFontPreloadHrefs(manifest));
    final String twice = dvApplyFontPreloads(once, <String>['assets/a.woff2']);
    expect(RegExp('dvAfterBoot\\(go\\)').allMatches(twice), hasLength(1));
    expect(twice, contains('assets/a.woff2'));
    expect(twice, isNot(contains('InterVariable')));
  });

  test('no fonts leaves the page exactly as it was', () {
    expect(dvApplyFontPreloads(page, const <String>[]), page);
  });

  test('a page with no head is left alone', () {
    const String bare = '<p>no head</p>';
    expect(dvApplyFontPreloads(bare, <String>['assets/a.woff2']), bare);
  });

  // The two manifests the engine reads before it can ask for anything else:
  // FontManifest.json, which names the fonts, and AssetManifest.bin.json, which
  // an AssetImage reads to pick its file. Each was a round trip after the app
  // started (0.6 s apiece on Fast 3G, 2 s on Slow 3G).
  group('the boot preloads of a build', () {
    late Directory web;
    setUp(() {
      web = Directory.systemTemp.createTempSync('dv_boot_preloads_');
      Directory(p.join(web.path, 'assets')).createSync();
    });
    tearDown(() => web.deleteSync(recursive: true));

    test('the two manifests first, then every font', () {
      File(p.join(web.path, 'assets', 'FontManifest.json')).writeAsStringSync(manifest);
      File(p.join(web.path, 'assets', 'AssetManifest.bin.json')).writeAsStringSync('""');
      expect(dvBootPreloadHrefs(web.path), <String>[
        'assets/FontManifest.json',
        'assets/AssetManifest.bin.json',
        ...dvFontPreloadHrefs(manifest),
      ]);
    });

    test('a manifest the build did not write is not asked for', () {
      File(p.join(web.path, 'assets', 'FontManifest.json')).writeAsStringSync('[]');
      expect(dvBootPreloadHrefs(web.path), <String>['assets/FontManifest.json']);
    });

    test('no assets folder, nothing', () {
      Directory(p.join(web.path, 'assets')).deleteSync();
      expect(dvBootPreloadHrefs(web.path), isEmpty);
    });
  });
}
