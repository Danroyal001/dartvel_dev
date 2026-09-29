// While the engine boots a visitor sees the splash, never the crawler text.
//
// A prerendered page carries its text for crawlers, printers, find and
// visitors without JavaScript. It stays off the screen while Flutter loads:
// 0.9.2 briefly showed it as the page during boot, and the owner rejected
// that. This guards the splash.
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

  test('before the first frame the splash is on screen and the text is not',
      () async {
    final Page page = await _open();
    expect(await _textWidth(page), lessThanOrEqualTo(1));
    expect(await _headingOnTop(page), isFalse);
    expect(await page.evaluate<bool>('''() => {
      const s = document.getElementById("dartvel-splash");
      const r = s.getBoundingClientRect();
      return r.width >= 790 && r.height >= 590 &&
          document.elementFromPoint(400, 300).closest("#dartvel-splash") !== null;
    }'''), isTrue);
    // Still in the document for crawlers, find and print.
    expect(await page.evaluate<String>(
        '() => document.querySelector(".dv-fallback h1").textContent'),
        'Pricing');
    await page.close();
  });

  test('the first frame removes the splash and the text stays hidden', () async {
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
