// SSR-first in a real browser: the server-rendered document is the page
// from the first paint -- visible, on top, selectable, clickable, reachable
// with Tab and by a screen reader, in the app's colours -- and it hands over
// to the app at `dartvel-first-frame`, back into the clipped box that find,
// crawlers and print use.
//
// The engine's own changes to the page while it boots are reproduced: it
// fixes the body and turns off selection and touch scrolling on it.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:math' show Point;

import 'package:dartvel_cli/src/build/chrome_launch.dart';
import 'package:dartvel_cli/src/build/native_splash.dart';
import 'package:dartvel_core/dartvel.dart' show dvApplyPageHtml;
import 'package:puppeteer/puppeteer.dart';
import 'package:test/test.dart';

const String _shell = '''
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"><title>t</title></head>
<body>
  <script>/* flutter_bootstrap.js stands in here */</script>
</body>
</html>
''';

final String _content = <String>[
  '<a href="/">Home</a>',
  '<a href="/pricing">Pricing</a>',
  '<h1>Pricing</h1>',
  for (int i = 0; i < 40; i++) '<p>Paragraph $i of readable text for everybody.</p>',
].join();

late Browser browser;
late HttpServer server;

String _page({required bool ssrFirst}) => dvApplyPageHtml(
      dvWebSplashApply(
        _shell,
        DVSplash(
          color: '#FFFFFF',
          darkColor: '#0A0A0A',
          progressColor: '#1D4ED8',
          ssrFirst: ssrFirst,
        ),
      ),
      _content,
      path: '/pricing',
    );

/// What Flutter's full-page embedding does to the body while it boots.
const String _engineBoots = '''() => {
  const b = document.body.style;
  b.position = "fixed"; b.top = b.right = b.bottom = b.left = "0";
  b.overflow = "hidden"; b.userSelect = "none"; b.webkitUserSelect = "none";
  b.touchAction = "none";
  const view = document.createElement("flutter-view");
  view.style.cssText = "position:absolute;inset:0;display:block";
  document.body.appendChild(view);
}''';

Future<Page> _open({required bool ssrFirst, bool dark = false}) async {
  final Page page = await browser.newPage();
  await page.setViewport(const DeviceViewport(width: 390, height: 700));
  if (dark) {
    // puppeteer's MediaFeature spells the feature "prefers-colors-scheme",
    // which Chrome does not know; the protocol call takes it as written.
    await page.devTools.client.send('Emulation.setEmulatedMedia', <String, Object?>{
      'features': <Map<String, String>>[
        <String, String>{'name': 'prefers-color-scheme', 'value': 'dark'},
      ],
    });
  }
  await page.goto('http://127.0.0.1:${server.port}/${ssrFirst ? 'on' : 'off'}',
      wait: Until.load);
  return page;
}

Future<bool> _headingOnTop(Page page) => page.evaluate<bool>('''() => {
  const h = document.querySelector(".dv-fallback h1");
  const r = h.getBoundingClientRect();
  if (r.width < 2) return false;
  const top = document.elementFromPoint(r.left + 5, r.top + r.height / 2);
  return h === top || h.contains(top);
}''');

Future<void> _firstFrame(Page page) => page.evaluate<void>(
    '() => window.dispatchEvent(new Event("dartvel-first-frame"))');

void main() {
  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((HttpRequest request) {
      request.response.headers.contentType = ContentType.html;
      if (request.uri.path == '/on' || request.uri.path == '/off') {
        request.response.write(_page(ssrFirst: request.uri.path == '/on'));
      } else {
        request.response.write('<!DOCTYPE html><title>next</title>'
            '<p id="landed">${request.uri.path}</p>');
      }
      request.response.close();
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

  test('off: the splash covers the page and the document is off screen',
      () async {
    final Page page = await _open(ssrFirst: false);
    expect(await _headingOnTop(page), isFalse);
    expect(await page.evaluate<bool>(
        '() => document.elementFromPoint(195, 350).closest("#dartvel-splash") !== null'),
        isTrue);
    await page.close();
  });

  test('on: the document is the page, in the app colours, splash hidden',
      () async {
    final Page page = await _open(ssrFirst: true);
    await page.evaluate<void>(_engineBoots);
    expect(await _headingOnTop(page), isTrue);
    expect(await page.evaluate<String>(
        '() => getComputedStyle(document.getElementById("dartvel-splash")).display'),
        'none');
    expect(await page.evaluate<String>(
        '() => getComputedStyle(document.querySelector(".dv-fallback")).backgroundColor'),
        'rgb(255, 255, 255)');
    // The loading bar stays above it. (It takes no pointer events, so
    // hit-testing passes through it; compare the stacking instead.)
    expect(await page.evaluate<bool>('''() => {
      const z = (el) => Number(getComputedStyle(el).zIndex);
      const bar = document.getElementById("dartvel-progress");
      return getComputedStyle(bar).display !== "none" &&
          z(bar) > z(document.querySelector(".dv-fallback"));
    }'''), isTrue);
    await page.close();
  });

  test('on, dark: the dark colours', () async {
    final Page page = await _open(ssrFirst: true, dark: true);
    expect(await page.evaluate<String>(
        '() => getComputedStyle(document.querySelector(".dv-fallback")).backgroundColor'),
        'rgb(10, 10, 10)');
    await page.close();
  });

  test('on: it scrolls and its text selects with the engine booting', () async {
    final Page page = await _open(ssrFirst: true);
    await page.evaluate<void>(_engineBoots);
    await page.mouse.move(const Point<num>(195, 400));
    await page.mouse.wheel(deltaY: 600);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(await page.evaluate<num>(
        '() => document.querySelector(".dv-fallback").scrollTop'),
        greaterThan(100));
    // A triple click selects a paragraph.
    final ElementHandle paragraph =
        (await page.$$('.dv-fallback p')).firstWhere((ElementHandle _) => true);
    await paragraph.evaluate<void>('(p) => p.scrollIntoView()');
    await paragraph.click(clickCount: 3);
    expect(await page.evaluate<String>('() => getSelection().toString()'),
        contains('readable text'));
    await page.close();
  });

  test('on: Tab reaches its links and a screen reader reads it', () async {
    final Page page = await _open(ssrFirst: true);
    await page.evaluate<void>(_engineBoots);
    await page.keyboard.press(Key.tab);
    expect(await page.evaluate<String>('() => document.activeElement.textContent'),
        'Home');
    final AXNode tree = await page.accessibility.snapshot();
    String all(AXNode node) =>
        '${node.name ?? ''} ${node.children.map(all).join(' ')}';
    expect(all(tree), contains('Pricing'));
    expect(all(tree), contains('Paragraph 3 of readable text'));
    await page.close();
  });

  test('on: a link is a normal navigation before the app loads', () async {
    final Page page = await _open(ssrFirst: true);
    await page.evaluate<void>(_engineBoots);
    await Future.wait(<Future<Object?>>[
      page.waitForNavigation(),
      page.click('.dv-fallback a[href="/pricing"]'),
    ]);
    expect(await page.evaluate<String>(
        '() => document.getElementById("landed").textContent'), '/pricing');
    await page.close();
  });

  test('on: the first frame hands over to the app', () async {
    final Page page = await _open(ssrFirst: true);
    await page.evaluate<void>(_engineBoots);
    await _firstFrame(page);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(await page.evaluate<bool>(
        '() => document.documentElement.hasAttribute("data-dv-app")'), isTrue);
    expect(await _headingOnTop(page), isFalse);
    // Back in the clipped box, still in the document for find and print.
    expect(await page.evaluate<num>(
        '() => document.querySelector(".dv-fallback").getBoundingClientRect().width'),
        lessThanOrEqualTo(1));
    expect(await page.evaluate<String>(
        '() => document.querySelector(".dv-fallback h1").textContent'), 'Pricing');
    await page.close();
  });

  test('on: a selection in progress is not taken away', () async {
    final Page page = await _open(ssrFirst: true);
    await page.evaluate<void>(_engineBoots);
    await (await page.$('.dv-fallback h1')).click(clickCount: 3);
    await _firstFrame(page);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(await _headingOnTop(page), isTrue);
    await page.evaluate<void>('() => getSelection().removeAllRanges()');
    await Future<void>.delayed(const Duration(milliseconds: 900));
    expect(await _headingOnTop(page), isFalse);
    await page.close();
  });
}
