// The web splash shows how far the page has got, not just that it is there.
//
// A Flutter web page downloads its compiled app, a renderer and fonts before
// the first frame, and a still splash through all of that reads as a page
// that died. A thin bar across the top moves as each of those arrives,
// creeps between them so it never stands still, and completes on the first
// frame. It is a progressbar to assistive technology, the document is
// aria-busy until the page is ready, and with reduced motion it steps rather
// than slides.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_cli/src/build/chrome_launch.dart';
import 'package:dartvel_cli/src/build/native_splash.dart';
import 'package:dartvel_cli/src/build/pwa_icons.dart';
import 'package:dartvel_core/dartvel.dart' show dvApplyPageHtml;
import 'package:puppeteer/protocol/emulation.dart' as cdp;
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
String html = '';

Future<Page> _open({bool javascript = true, bool reduced = false}) async {
  final Page page = await browser.newPage();
  await page.setViewport(const DeviceViewport(width: 200, height: 200));
  await page.setJavaScriptEnabled(javascript);
  await page.devTools.emulation.setEmulatedMedia(features: <cdp.MediaFeature>[
    cdp.MediaFeature(
        name: 'prefers-reduced-motion', value: reduced ? 'reduce' : ''),
  ]);
  await page.goto('http://127.0.0.1:${server.port}/', wait: Until.load);
  return page;
}

Future<num> _value(Page page) => page.evaluate<num>(
    '() => Number(document.getElementById("dartvel-progress")'
    '.getAttribute("aria-valuenow"))');

void main() {
  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((HttpRequest request) {
      request.response.headers.contentType = request.uri.path == '/'
          ? ContentType.html
          : ContentType('application', 'octet-stream');
      request.response
        ..write(request.uri.path == '/' ? html : 'x')
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
      dvWebSplashApply(_shell,
          DVSplash(color: '#FFFFFF', darkColor: '#000000', progressColor: '#00FF00')),
      '<p>Readable text</p>',
    );
  });

  test('a progressbar is on screen, started, and the page is busy', () async {
    final Page page = await _open();
    expect(await page.evaluate<String?>('() => '
        'document.getElementById("dartvel-progress").getAttribute("role")'),
        'progressbar');
    final num v = await _value(page);
    expect(v, greaterThan(0));
    expect(v, lessThan(100));
    expect(await page.evaluate<String?>(
        '() => document.documentElement.getAttribute("aria-busy")'), 'true');
    // Drawn in the colour it was given, across the top.
    expect(await page.evaluate<String>('() => getComputedStyle('
        'document.querySelector("#dartvel-progress > div")).backgroundColor'),
        'rgb(0, 255, 0)');
    await page.close();
  });

  test('it moves when the app and the renderer arrive', () async {
    final Page page = await _open(reduced: true);
    // The head preloads main.dart.js, so the app has arrived by the time the
    // page has loaded, and the bar says so.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final num afterApp = await _value(page);
    expect(afterApp, greaterThanOrEqualTo(45));
    await page.evaluate<void>(
        '() => fetch("/canvaskit/canvaskit.wasm").then(r => r.text())');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(await _value(page), greaterThan(afterApp));
    await page.close();
  });

  test('between arrivals it creeps rather than standing still', () async {
    final Page page = await _open();
    final num first = await _value(page);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    expect(await _value(page), greaterThan(first));
    await page.close();
  });

  test('the first frame completes it, takes it away and ends busy', () async {
    final Page page = await _open(reduced: true);
    await page.evaluate<void>(
        '() => window.dispatchEvent(new Event("flutter-first-frame"))');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(await page.evaluate<bool>(
        '() => document.getElementById("dartvel-progress") === null'), isTrue);
    expect(await page.evaluate<String?>(
        '() => document.documentElement.getAttribute("aria-busy")'), isNull);
    await page.close();
  });

  test('without scripting there is no bar standing over the page', () async {
    final Page page = await _open(javascript: false);
    final DVRgbaImage shot =
        dvPngDecode(Uint8List.fromList(await page.screenshot()));
    expect(shot.get(100, 1).sublist(0, 3), isNot(<int>[0, 255, 0]));
    await page.close();
  });

  test('it is on by default, and a project can turn it off', () {
    expect(DVSplash.fromConfig(const <Object?, Object?>{}, root: '.').progress,
        isTrue);
    final DVSplash off = DVSplash.fromConfig(const <Object?, Object?>{
      'splash': <Object?, Object?>{'progress': false},
    }, root: '.');
    expect(off.progress, isFalse);
    expect(dvWebSplashApply(_shell, off), isNot(contains('id="dartvel-progress"')));
  });
}
