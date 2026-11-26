// SSR-first in the app's own look, the build's side: which widths the
// document is laid out for, the fonts it draws with, the boxes of the links,
// buttons and fields read off the semantics host, and the captured HTML each
// route ships with.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/build/chrome_launch.dart';
import 'package:dartvel_cli/src/build/native_splash.dart';
import 'package:dartvel_cli/src/build/ssr_first_capture.dart';
import 'package:path/path.dart' as p;
import 'package:puppeteer/puppeteer.dart';
import 'package:test/test.dart';

void main() {
  group('dartvel.web.ssrFirst', () {
    DVSplash splash(Object? value) => DVSplash.fromConfig(<String, Object?>{
          'web': <String, Object?>{'ssrFirst': value},
        }, root: Directory.systemTemp.path);

    test('true lays the document out at the default widths', () {
      expect(splash(true).ssrFirst, isTrue);
      expect(splash(true).ssrFirstWidths, dvSsrFirstDefaultWidths);
      expect(dvSsrFirstDefaultWidths, containsAll(<int>[390, 1024, 1366]));
    });

    test('a map names its own widths, sorted, and is on', () {
      final DVSplash configured = splash(<String, Object?>{'widths': <Object?>[1366, 390, 'x', 1024]});
      expect(configured.ssrFirst, isTrue);
      expect(configured.ssrFirstWidths, <int>[390, 1024, 1366]);
    });

    test('a map can still turn it off', () {
      expect(splash(<String, Object?>{'enabled': false}).ssrFirst, isFalse);
      expect(splash(false).ssrFirst, isFalse);
      expect(splash(false).ssrFirstWidths, isEmpty);
    });
  });

  test('each width is captured at a screen height of its kind', () {
    expect(dvSsrFirstHeight(390), 844);
    expect(dvSsrFirstHeight(1024), 768);
    expect(dvSsrFirstHeight(1366), 900);
    expect(dvSsrFirstHeight(1920), 1080);
  });

  test('the fonts are FontManifest.json, by family, as the build wrote it', () {
    final Directory web = Directory.systemTemp.createTempSync('dv_fonts');
    addTearDown(() => web.deleteSync(recursive: true));
    Directory(p.join(web.path, 'assets')).createSync();
    File(p.join(web.path, 'assets', 'FontManifest.json')).writeAsStringSync(jsonEncode(<Object?>[
      <String, Object?>{
        'family': 'Inter',
        'fonts': <Object?>[
          <String, Object?>{'asset': 'assets/fonts/Inter.abc.woff2'},
        ],
      },
      <String, Object?>{
        'family': 'Space Grotesk',
        'fonts': <Object?>[
          <String, Object?>{'asset': 'fonts/sg-700.woff2', 'weight': 700},
          <String, Object?>{'asset': 'fonts/sg-it.woff2', 'style': 'italic'},
        ],
      },
    ]));
    final fonts = dvLayoutFonts(web.path);
    expect(fonts['Inter']!.single.url, 'assets/assets/fonts/Inter.abc.woff2');
    expect(fonts['Inter']!.single.weight, isNull);
    expect(fonts['Space Grotesk']!.map((f) => f.weight), <int?>[700, null]);
    expect(fonts['Space Grotesk']!.last.style, 'italic');
    expect(dvLayoutFonts(p.join(web.path, 'missing')), isEmpty);
  });

  test('the layout is written beside the route\'s tree and laid onto its HTML', () {
    final Directory root = Directory.systemTemp.createTempSync('dv_layout');
    addTearDown(() => root.deleteSync(recursive: true));
    final String path = dvLayoutCapturePathFor(root.path, '/pricing');
    expect(p.basename(path), 'pricing.layout.json');
    const String html = '<h1>Pricing</h1>';
    expect(dvApplySsrFirstLayout(root.path, '/pricing', html, const {}), html,
        reason: 'nothing captured: the document as it was');
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(<String, Object?>{
        'widths': <Object?>[
          <String, Object?>{
            'width': 390,
            'height': 844,
            'light': <String, Object?>{
              'items': <Object?>[
                <String, Object?>{
                  'k': 't', 'r': <num>[16, 80, 200, 40], 'z': 0, 's': true, 'text': 'Pricing',
                  'runs': <Object?>[<String, Object?>{'t': 'Pricing', 'f': 'Inter', 'fs': 32, 'fw': 700, 'c': '#000000'}],
                  'al': 'left', 'lines': 1, 'lh': 40, 'nw': true,
                },
              ],
            },
            'controls': <Object?>[],
          },
        ],
      }));
    final String laid = dvApplySsrFirstLayout(root.path, '/pricing', html, const {});
    expect(laid, startsWith('<div class="dvl">'));
    expect(laid, contains('Pricing</span></h1>'));
  });

  // ChopDesk's menu at /r/<slug>: a page the build cannot capture, served by
  // the web-server binary from the data. The shell carries the app's look,
  // worked out from the pages that were captured, for such a page.
  test("the web-server shell carries the app's look for the pages it could not capture", () {
    final Directory root = Directory.systemTemp.createTempSync('dv_theme');
    addTearDown(() => root.deleteSync(recursive: true));
    const String shell = '<!DOCTYPE html><html><head><title>x</title></head><body></body></html>';
    const Map<String, String> pages = <String, String>{'/pricing': '<h1>Pricing</h1>'};
    expect(dvWithSsrFirstTheme(root.path, shell, pages, const {}), shell,
        reason: 'nothing captured: no theme');
    File(dvLayoutCapturePathFor(root.path, '/pricing'))
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(<String, Object?>{
        'widths': <Object?>[
          <String, Object?>{
            'width': 390,
            'height': 844,
            'light': <String, Object?>{
              'items': <Object?>[
                <String, Object?>{
                  'k': 't', 'r': <num>[16, 80, 200, 40], 'z': 0, 's': true, 'text': 'Pricing',
                  'runs': <Object?>[<String, Object?>{'t': 'Pricing', 'f': 'Inter', 'fs': 32, 'fw': 700, 'c': '#000000'}],
                  'al': 'left', 'lines': 1, 'lh': 40, 'nw': true,
                },
              ],
            },
            'controls': <Object?>[],
          },
        ],
      }));
    final String themed = dvWithSsrFirstTheme(root.path, shell, pages, const {});
    expect(themed, contains('<style id="dv-ssr-theme">'));
    expect(themed.indexOf('<style id="dv-ssr-theme">'), lessThan(themed.indexOf('</head>')));
    expect(themed, contains('.dvt h1{font:700 32px/40px'));
    // Built again: one theme, the new one.
    expect(RegExp('id="dv-ssr-theme"').allMatches(dvWithSsrFirstTheme(root.path, themed, pages, const {})),
        hasLength(1));
  });

  group('a slow scheme switch', _laggingSchemeTests);
  group('an app that says when it is idle', _idleTests);

  group('in a browser', () {
    late Browser browser;
    setUpAll(() async {
      browser = await puppeteer.launch(executablePath: await dvChromeExecutable(), args: dvChromeLaunchArgs);
    });
    tearDownAll(() => browser.close());

    test('links, buttons, fields and the eye are read off the semantics host with their boxes', () async {
      final Page page = await browser.newPage();
      await page.setContent('<!DOCTYPE html><html><body style="margin:0"><flt-semantics-host>'
          '<flt-semantics style="position:absolute;left:0;top:0;width:400px;height:900px">'
          '<a href="/pricing" style="position:absolute;left:10px;top:20px;width:80px;height:30px">Pricing</a>'
          '<flt-semantics role="button" aria-label="Get in touch" style="position:absolute;left:200px;top:20px;width:120px;height:40px"></flt-semantics>'
          '<flt-semantics style="position:absolute;left:10px;top:100px;width:300px;height:56px"><input aria-label="Email" style="width:100%;height:100%"></flt-semantics>'
          '<flt-semantics flt-semantics-identifier="dartvel:reveal" role="button" aria-label="Show password" style="position:absolute;left:320px;top:100px;width:48px;height:48px"></flt-semantics>'
          '<a href="/hidden" style="position:absolute;left:0;top:0;width:0;height:0"></a>'
          '</flt-semantics></flt-semantics-host></body></html>');
      final List<Object?> controls =
          jsonDecode(await page.evaluate<String>(dvLayoutControlsScript)) as List<Object?>;
      await page.close();
      expect(controls, <Object?>[
        <String, Object?>{'k': 'a', 'href': '/pricing', 'name': 'Pricing', 'r': <Object?>[10, 20, 80, 30]},
        <String, Object?>{'k': 'b', 'name': 'Get in touch', 'r': <Object?>[200, 20, 120, 40]},
        <String, Object?>{'k': 'f', 'name': 'Email', 'r': <Object?>[10, 100, 300, 56]},
        <String, Object?>{'k': 'r', 'name': 'Show password', 'r': <Object?>[320, 100, 48, 48]},
      ]);
    });
  });
}

/// An app whose theme follows the browser's scheme a while after it changes,
/// as a real one does.
const String _laggingApp = '''<!DOCTYPE html><html><body><flt-semantics-host></flt-semantics-host><script>
let told = matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
matchMedia('(prefers-color-scheme: dark)').addEventListener('change', (event) => {
  setTimeout(() => { told = event.matches ? 'dark' : 'light'; }, 600);
});
globalThis.__dartvelCapture = { snapshot: () => JSON.stringify({
  width: innerWidth, height: innerHeight, brightness: told,
  items: [{k: 'b', r: [0, 0, innerWidth, innerHeight], z: 0, s: false, bg: told === 'dark' ? '#000000' : '#ffffff'}],
}) };
</script></body></html>''';

void _laggingSchemeTests() {
  late Browser browser;
  setUpAll(() async {
    browser = await puppeteer.launch(executablePath: await dvChromeExecutable(), args: dvChromeLaunchArgs);
  });
  tearDownAll(() => browser.close());

  test('each width is read in the scheme it is for, though the app is slow to switch', () async {
    final Page page = await browser.newPage();
    await page.setContent(_laggingApp);
    final Directory root = Directory.systemTemp.createTempSync('dv_scheme');
    addTearDown(() => root.deleteSync(recursive: true));
    final String path = p.join(root.path, 'x.layout.json');
    expect(await dvCaptureLayout(page, <int>[390, 1024, 1366], path: path), isTrue);
    await page.close();
    final Map<String, Object?> written = jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
    for (final Object? width in written['widths']! as List<Object?>) {
      final Map<String, Object?> entry = width! as Map<String, Object?>;
      String background(String scheme) =>
          (((entry[scheme]! as Map<String, Object?>)['items']! as List<Object?>).first! as Map<String, Object?>)['bg']! as String;
      expect(background('light'), '#ffffff', reason: 'light at ${entry['width']}');
      expect(background('dark'), '#000000', reason: 'dark at ${entry['width']}');
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}

/// An app that says when it is idle: the capture reads each picture once,
/// when the app has nothing left to draw, instead of until three reads agree.
const String _idleApp = '''<!DOCTYPE html><html><body><flt-semantics-host></flt-semantics-host><script>
let told = 'light';
let busyUntil = 0;
globalThis.__snapshots = 0;
matchMedia('(prefers-color-scheme: dark)').addEventListener('change', (event) => {
  busyUntil = Date.now() + 500;
  setTimeout(() => { told = event.matches ? 'dark' : 'light'; }, 300);
});
// The app hears about a resize late, and says it is idle meanwhile: what
// a loaded machine does to a real one.
let seenWidth = innerWidth;
const lag = globalThis.__resizeLag || 0;
addEventListener('resize', () => {
  busyUntil = Date.now() + 300;
  const now = innerWidth;
  if (lag === 0) { seenWidth = now; return; }
  setTimeout(() => { seenWidth = now; }, lag);
});
globalThis.__dartvelCapture = {
  idle: () => Date.now() > busyUntil,
  brightness: () => told,
  snapshot: () => { globalThis.__snapshots++; return JSON.stringify({
    width: seenWidth, height: innerHeight, brightness: told,
    items: [{k: 'b', r: [0, 0, seenWidth, innerHeight], z: 0, s: false, bg: told === 'dark' ? '#000000' : '#ffffff'}],
  }); },
};
</script></body></html>''';

void _idleTests() {
  late Browser browser;
  setUpAll(() async {
    browser = await puppeteer.launch(executablePath: await dvChromeExecutable(), args: dvChromeLaunchArgs);
  });
  tearDownAll(() => browser.close());

  test('an app that says when it is idle is read once per width and scheme', () async {
    final Page page = await browser.newPage();
    await page.setContent(_idleApp);
    final Directory root = Directory.systemTemp.createTempSync('dv_idle');
    addTearDown(() => root.deleteSync(recursive: true));
    final String path = p.join(root.path, 'x.layout.json');
    expect(await dvCaptureLayout(page, <int>[390, 1024, 1366], path: path), isTrue);
    // Light and dark at each width, and light again at a second screen
    // height (the layout does not change with the scheme).
    expect(await page.evaluate<int>('() => globalThis.__snapshots'), 9);
    await page.close();
    final Map<String, Object?> written = jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
    for (final Object? width in written['widths']! as List<Object?>) {
      final Map<String, Object?> entry = width! as Map<String, Object?>;
      String background(String scheme) =>
          (((entry[scheme]! as Map<String, Object?>)['items']! as List<Object?>).first! as Map<String, Object?>)['bg']! as String;
      expect(background('light'), '#ffffff');
      expect(background('dark'), '#000000');
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('each width is read again at a taller screen, for what is sized to the screen', () async {
    final Page page = await browser.newPage();
    await page.setContent(_idleApp);
    final Directory root = Directory.systemTemp.createTempSync('dv_tall');
    addTearDown(() => root.deleteSync(recursive: true));
    final String path = p.join(root.path, 'x.layout.json');
    expect(await dvCaptureLayout(page, <int>[390, 1366], path: path), isTrue);
    await page.close();
    final Map<String, Object?> written = jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
    for (final Object? width in written['widths']! as List<Object?>) {
      final Map<String, Object?> entry = width! as Map<String, Object?>;
      final Map<String, Object?> tall = entry['tall']! as Map<String, Object?>;
      final int height = entry['height']! as int;
      expect(tall['height'], dvSsrFirstTallHeight(height));
      expect(tall['height'] as int, greaterThan(height));
      // The app's own screen-sized box, read at that height.
      final Map<String, Object?> box = (tall['items']! as List<Object?>).first! as Map<String, Object?>;
      expect((box['r']! as List<Object?>)[3], tall['height']);
      expect(tall['controls'], isA<List<Object?>>());
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a resize that reaches the app late is waited for', () async {
    final Page page = await browser.newPage();
    await page.setContent(_idleApp.replaceFirst('globalThis.__resizeLag || 0', '1200'));
    final Directory root = Directory.systemTemp.createTempSync('dv_resize');
    addTearDown(() => root.deleteSync(recursive: true));
    final String path = p.join(root.path, 'x.layout.json');
    expect(await dvCaptureLayout(page, <int>[390, 1024, 1366], path: path), isTrue);
    await page.close();
    final Map<String, Object?> written = jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
    for (final Object? width in written['widths']! as List<Object?>) {
      final Map<String, Object?> entry = width! as Map<String, Object?>;
      // Read at its own width, not the one before the resize reached the app.
      for (final String scheme in <String>['light', 'dark']) {
        expect(((entry[scheme]! as Map<String, Object?>)['width']! as num).toInt(), entry['width'],
            reason: '$scheme at ${entry['width']}');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
