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
