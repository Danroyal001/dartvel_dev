// The page's own text is on screen before the engine boots.
//
// A prerendered page carries its text for crawlers, printers and find. It
// was kept off the screen until now, so for the seconds a Flutter page
// takes to boot the reader saw a splash and nothing to read, and the
// largest contentful paint was the splash image. Now the text shows, styled,
// over the splash colour, until the first frame hands over to the app.
@TestOn('vm')
library;

import 'dart:io';

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

late Browser browser;
late HttpServer server;
final String html = dvApplyPageHtml(
  dvWebSplashApply(_shell, DVSplash(color: '#FF0000', darkColor: '#FF0000')),
  '<h1>Pricing</h1><p>Readable text for everybody.</p>',
);

Future<Page> _open() async {
  final Page page = await browser.newPage();
  await page.setViewport(const DeviceViewport(width: 800, height: 600));
  await page.goto('http://127.0.0.1:${server.port}/', wait: Until.load);
  return page;
}

/// The width of the page text's block on screen.
Future<num> _textWidth(Page page) => page.evaluate<num>(
    '() => document.querySelector(".dv-fallback").getBoundingClientRect().width');

/// Whether the heading is what a reader sees at its own position.
Future<bool> _headingOnTop(Page page) => page.evaluate<bool>('''() => {
  const h = document.querySelector(".dv-fallback h1");
  const r = h.getBoundingClientRect();
  const top = document.elementFromPoint(r.left + 5, r.top + r.height / 2);
  return h === top || h.contains(top);
}''');

void main() {
  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((HttpRequest request) {
      request.response.headers.contentType = ContentType.html;
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

  test('before the first frame the text is on screen, over the splash',
      () async {
    final Page page = await _open();
    expect(await _textWidth(page), greaterThan(200));
    expect(await _headingOnTop(page), isTrue);
    await page.close();
  });

  test('the first frame hands the screen to the app', () async {
    final Page page = await _open();
    await page.evaluate<void>(
        '() => window.dispatchEvent(new Event("flutter-first-frame"))');
    expect(await _textWidth(page), lessThanOrEqualTo(1));
    // Still in the document for find, crawlers and print.
    expect(await page.evaluate<String>(
        '() => document.querySelector(".dv-fallback h1").textContent'),
        'Pricing');
    await page.close();
  });
}
