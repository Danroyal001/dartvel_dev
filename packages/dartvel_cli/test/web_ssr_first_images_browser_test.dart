// SSR-first, in a real browser: a small image on the first screen is part of
// the first painted frame. On sigmadev.digital (Dartvel 3.47.9) the first
// frame was the whole first screen except the header logo, which came 0.2 s
// (light) to 3 s (dark) later: it was fetched separately, decoded
// asynchronously, and in dark mode named by a stylesheet rule found only
// once the stylesheet applied.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dartvel_cli/src/build/chrome_launch.dart';
import 'package:dartvel_cli/src/build/native_splash.dart';
import 'package:dartvel_core/dartvel.dart' show dvApplyPageHtml, dvSsrFirstLayout;
import 'package:puppeteer/puppeteer.dart';
import 'package:test/test.dart';

const String _shell = '<!DOCTYPE html><html><head><meta charset="UTF-8"><title>t</title></head>'
    '<body><script>/* flutter_bootstrap.js */</script></body></html>';

const String _doc = '<h1>Ship faster</h1>\n';

/// A solid [width] x [height] PNG in one colour.
List<int> _png(int width, int height, List<int> rgb) {
  List<int> chunk(String type, List<int> data) {
    final List<int> body = <int>[...type.codeUnits, ...data];
    int crc = 0xffffffff;
    for (final int byte in body) {
      crc ^= byte;
      for (int bit = 0; bit < 8; bit++) {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
      }
    }
    crc ^= 0xffffffff;
    final ByteData length = ByteData(4)..setUint32(0, data.length);
    final ByteData sum = ByteData(4)..setUint32(0, crc);
    return <int>[...length.buffer.asUint8List(), ...body, ...sum.buffer.asUint8List()];
  }

  final ByteData header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8)
    ..setUint8(9, 2);
  final List<int> raw = <int>[
    for (int y = 0; y < height; y++) ...<int>[0, for (int x = 0; x < width; x++) ...rgb],
  ];
  return <int>[
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, //
    ...chunk('IHDR', header.buffer.asUint8List()),
    ...chunk('IDAT', zlib.encode(raw)),
    ...chunk('IEND', const <int>[]),
  ];
}

final List<int> _black = _png(48, 16, <int>[0, 0, 0]);
final List<int> _white = _png(48, 16, <int>[255, 255, 255]);

String _page({required bool readImages}) => dvApplyPageHtml(
      dvWebSplashApply(
        _shell,
        DVSplash(color: '#FFFFFF', darkColor: '#0A0A0A', progressColor: '#1D4ED8', ssrFirst: true),
      ),
      dvSsrFirstLayout(
        _doc,
        <String, Object?>{
          'widths': <Object?>[
            <String, Object?>{
              'width': 390,
              'height': 800,
              'light': <String, Object?>{
                'items': <Object?>[
                  <String, Object?>{'k': 'i', 'r': <num>[16, 12, 48, 16], 'z': 1, 's': false, 'src': 'assets/black.png'},
                ],
              },
              'dark': <String, Object?>{
                'items': <Object?>[
                  <String, Object?>{'k': 'i', 'r': <num>[16, 12, 48, 16], 'z': 1, 's': false, 'src': 'assets/white.png'},
                ],
              },
              'controls': <Object?>[],
            },
          ],
        },
        readImage: readImages
            ? (String source) => source.endsWith('black.png') ? _black : _white
            : null,
      ),
      path: '/',
    );

late Browser browser;
late HttpServer server;

/// Whether the logo had its pixels when the browser reported its first paint.
Future<bool> _logoInFirstPaint(String path, String scheme) async {
  final Page page = await browser.newPage();
  await page.setViewport(DeviceViewport(width: 390, height: 800));
  // puppeteer's MediaFeature spells the colour-scheme feature wrongly.
  await page.devTools.client.send('Emulation.setEmulatedMedia', <String, Object?>{
    'features': <Map<String, String>>[<String, String>{'name': 'prefers-color-scheme', 'value': scheme}],
  });
  await page.evaluateOnNewDocument('''() => {
    window.__logo = null;
    new PerformanceObserver((list) => {
      if (window.__logo !== null) return;
      const img = document.querySelector('.dvp img');
      const style = img && getComputedStyle(img).content;
      // In dark mode the light <img> shows the dark source as its content.
      window.__logo = !!img && img.complete && img.naturalWidth > 0
        && (${scheme == 'dark'} ? style.indexOf('data:image/png') >= 0 : true);
    }).observe({ type: 'paint', buffered: true });
  }''');
  await page.goto('http://127.0.0.1:${server.port}$path', wait: Until.domContentLoaded);
  await page.waitForFunction('() => window.__logo !== null');
  final bool shown = await page.evaluate<bool>('() => window.__logo');
  await page.close();
  return shown;
}

void main() {
  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((HttpRequest request) async {
      final String path = request.uri.path;
      if (path.endsWith('.png')) {
        // A slow line: a separate image arrives well after the page.
        await Future<void>.delayed(const Duration(seconds: 3));
        request.response
          ..headers.contentType = ContentType('image', 'png')
          ..add(path.endsWith('black.png') ? _black : _white);
        await request.response.close();
        return;
      }
      request.response
        ..headers.contentType = ContentType.html
        ..write(_page(readImages: path != '/url'));
      await request.response.close();
    });
    browser = await puppeteer.launch(executablePath: await dvChromeExecutable(), args: dvChromeLaunchArgs);
  });
  tearDownAll(() async {
    await browser.close();
    await server.close(force: true);
  });

  test('a small first-screen image is in the first painted frame, light and dark', () async {
    expect(await _logoInFirstPaint('/', 'light'), isTrue);
    expect(await _logoInFirstPaint('/', 'dark'), isTrue);
  });

  test('fetched separately it was not: the check sees the difference', () async {
    expect(await _logoInFirstPaint('/url', 'light'), isFalse);
    expect(await _logoInFirstPaint('/url', 'dark'), isFalse);
  });
}
