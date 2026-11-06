// The web splash, in a browser.
//
// The unit tests pin the markup; what matters is what a person sees, and the
// markup's claims are all about rendering: that the colour paints before any
// script, that the page a reader without scripting gets is not covered, that
// Flutter's view lands on top of it, and that it follows dark mode. Each of
// those is checked here by looking at pixels, because each can be true of the
// HTML and false of the page.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_cli/src/build/chrome_launch.dart';
import 'package:dartvel_core/dartvel.dart' show dvApplyPageHtml;
import 'package:dartvel_cli/src/build/native_splash.dart';
import 'package:dartvel_cli/src/build/pwa_icons.dart';
import 'package:puppeteer/protocol/emulation.dart' as cdp;
import 'package:puppeteer/puppeteer.dart';
import 'package:test/test.dart';

// The shell a site's pages are made from. The pages themselves are built in
// setUp the way the build makes them -- the splash into the shell, then the
// route's readable content -- because the no-scripting case turns on how the
// real fallback is styled: it is an ordinary block, and a positioned splash
// sits over an ordinary block. A fixture whose fallback was itself
// positioned hid a missing guard here once, passing with the rule deleted.
const String _shell = '''
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"><title>t</title></head>
<body>
  <script>/* flutter_bootstrap.js stands in here */</script>
</body>
</html>
''';

late Browser browser;
late HttpServer server;
String html = '';

List<int> _centre(List<int> png) {
  final DVRgbaImage image = dvPngDecode(Uint8List.fromList(png));
  return image.get(image.width ~/ 2, image.height ~/ 2).sublist(0, 3);
}

Future<Page> _open({bool javascript = true, String scheme = 'light', bool inlineBlocked = false}) async {
  final Page page = await browser.newPage();
  await page.setViewport(const DeviceViewport(width: 200, height: 200));
  await page.setJavaScriptEnabled(javascript);
  // Through the protocol rather than page.emulateMediaFeatures: puppeteer's
  // MediaFeature.prefersColorsScheme sends 'prefers-colors-scheme', a name
  // Chrome does not have, so the emulation silently does nothing and a dark
  // test passes or fails on the machine's own theme.
  await page.devTools.emulation.setEmulatedMedia(features: <cdp.MediaFeature>[
    cdp.MediaFeature(name: 'prefers-color-scheme', value: scheme),
  ]);
  await page.goto('http://127.0.0.1:${server.port}/${inlineBlocked ? '?block-inline=1' : ''}', wait: Until.load);
  return page;
}

void main() {
  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((HttpRequest request) {
      request.response.headers.contentType = ContentType.html;
      if (request.uri.queryParameters['block-inline'] == '1') {
        request.response.headers.set('Content-Security-Policy',
            "script-src 'none'; style-src 'unsafe-inline'");
      }
      request.response
        ..write(html)
        ..close();
    });
    browser = await puppeteer.launch(
      executablePath: await dvChromeExecutable(),
      args: dvChromeLaunchArgs,
    );
  });

  tearDownAll(() async {
    await browser.close();
    await server.close(force: true);
  });

  setUp(() {
    html = dvApplyPageHtml(
      dvWebSplashApply(
          _shell, DVSplash(color: '#FF0000', darkColor: '#0000FF')),
      '<p>Readable text</p>',
    );
  });

  test('the colour is on screen before anything has run', () async {
    // A page with no text of its own: one that has text shows the text
    // over the splash until the first frame.
    html = dvWebSplashApply(
        _shell, DVSplash(color: '#FF0000', darkColor: '#0000FF'));
    final Page page = await _open();
    expect(_centre(await page.screenshot()), <int>[255, 0, 0]);
    await page.close();
  });

  test('and in dark mode it is the dark one', () async {
    html = dvWebSplashApply(
        _shell, DVSplash(color: '#FF0000', darkColor: '#0000FF'));
    final Page page = await _open(scheme: 'dark');
    expect(_centre(await page.screenshot()), <int>[0, 0, 255]);
    await page.close();
  });

  test('without scripting the readable page is what shows', () async {
    // The control that matters most. With scripting off the first frame
    // never comes, so a splash left in place would cover the only content
    // the page has, for good.
    final Page page = await _open(javascript: false);
    // The fallback's own white, not the splash's red over it.
    expect(_centre(await page.screenshot()), <int>[255, 255, 255]);
    await page.close();
  });

  test('a pending Flutter view waits below the splash until raster ready', () async {
    final Page page = await _open();
    await page.evaluate<void>('''() => {
      document.body.style.position = 'fixed';
      document.body.style.inset = '0';
      const view = document.createElement('flutter-view');
      view.style.cssText = 'position:absolute;inset:0;display:block;background:#FFFF00';
      document.body.append(view);
    }''');
    expect(_centre(await page.screenshot()), <int>[255, 0, 0]);
    await page.evaluate<void>(
        '() => window.dispatchEvent(new Event("dartvel-first-frame"))');
    expect(_centre(await page.screenshot()), <int>[255, 255, 0]);
    await page.close();
  });

  test('and the first frame removes it', () async {
    final Page page = await _open();
    expect(await page.evaluate<bool>(
        '() => document.getElementById("dartvel-splash") !== null'), isTrue);
    await page.evaluate<void>(
        '() => window.dispatchEvent(new Event("flutter-first-frame"))');
    expect(await page.evaluate<bool>(
        '() => document.getElementById("dartvel-splash") !== null'), isTrue,
        reason: 'a deferred engine frame must keep the fallback splash');
    await page.evaluate<void>(
        '() => window.dispatchEvent(new Event("dartvel-first-frame"))');
    expect(await page.evaluate<bool>(
        '() => document.getElementById("dartvel-splash") === null'), isTrue);
    // And the page's own background is its own again.
    expect(_centre(await page.screenshot()), <int>[255, 255, 255]);
    await page.close();
  });

  test('blocked inline scripts cannot trap the rendered app under a splash', () async {
    final page = await _open(inlineBlocked: true);
    expect(_centre(await page.screenshot()), <int>[255, 0, 0]);
    await page.evaluate<void>('''()=>{
      document.body.style.position='fixed'; document.body.style.inset='0';
      const view=document.createElement('flutter-view');
      view.style.cssText='position:absolute;inset:0;display:block;background:#FFFF00';
      document.body.append(view);
    }''');
    expect(_centre(await page.screenshot()), <int>[255, 255, 0]);
    await page.close();
  });
}
