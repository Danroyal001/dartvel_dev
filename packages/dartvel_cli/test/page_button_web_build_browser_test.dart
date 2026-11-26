// The long-page button takes clicks on its own circle only: a web build of a
// real app, in a real browser, with a real mouse and a real finger.
//
// sigmadev.digital ran 3.47.11 to 3.47.13 with "To the bottom" published as a
// semantics node the size of the whole window, the page's links inside it.
// Every click on the page went to the button: a click on the logo scrolled to
// the bottom, the next one back to the top, and the link never opened. The
// button's Semantics was not a node of its own, so Flutter merged its name,
// role and tap up into the page shell's node. #326 had kept the server-
// rendered document from drawing that node over the page; the app's own tree,
// after takeover, still had it, and no test clicked a built app.
//
// The app is test/fixtures/page_button_app: a header with a link over a long
// page, the layout's button on. The test builds it with `flutter build web`
// (DV_PAGE_BUTTON_PREBUILT=1 reuses the last build) and serves it.
@TestOn('vm')
@Timeout(Duration(minutes: 15))
library;

import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/build/chrome_launch.dart';
import 'package:path/path.dart' as p;
import 'package:puppeteer/puppeteer.dart';
import 'package:test/test.dart';

final String _app = p.join(Directory.current.path, 'test', 'fixtures', 'page_button_app');

/// Serves [root], answering every path that is not a file with index.html,
/// as a web-server build does for its routes.
Future<HttpServer> _serve(String root) async {
  final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((HttpRequest request) async {
    String path = Uri.decodeComponent(request.uri.path);
    if (path.endsWith('/')) path = '${path}index.html';
    File file = File(p.join(root, p.normalize(path.substring(1))));
    if (!p.isWithin(root, file.path) || !file.existsSync()) file = File(p.join(root, 'index.html'));
    final String ext = p.extension(file.path);
    request.response.headers.contentType = switch (ext) {
      '.html' => ContentType.html,
      '.js' || '.mjs' => ContentType('text', 'javascript', charset: 'utf-8'),
      '.json' => ContentType.json,
      '.wasm' => ContentType('application', 'wasm'),
      _ => ContentType.binary,
    };
    await request.response.addStream(file.openRead());
    await request.response.close();
  });
  return server;
}

/// The semantics node named [label]: its box in the window, or null.
Future<Map<String, Object?>?> _node(Page page, String label) async {
  final String json = await page.evaluate<String>('''(label) => {
    for (const node of document.querySelectorAll('flt-semantics, a, button, [role]')) {
      const name = (node.getAttribute('aria-label') || '').trim();
      const own = !node.querySelector('flt-semantics, a, button, [role]');
      if (name !== label && !(own && (node.textContent || '').trim() === label)) continue;
      const box = node.getBoundingClientRect();
      if (box.width === 0 && box.height === 0) continue;
      return JSON.stringify({x: box.x, y: box.y, width: box.width, height: box.height, tag: node.tagName});
    }
    return 'null';
  }''', args: <Object?>[label]);
  return jsonDecode(json) as Map<String, Object?>?;
}

Future<Map<String, Object?>> _waitNode(Page page, String label, {Duration timeout = const Duration(seconds: 30)}) async {
  final DateTime end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    final Map<String, Object?>? node = await _node(page, label);
    if (node != null) return node;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  throw TestFailure('no semantics node "$label" after $timeout');
}

Future<void> _press(Page page, bool touch, num x, num y) async {
  final Point<num> point = Point<num>(x, y);
  if (touch) {
    await page.touchscreen.tap(point);
  } else {
    await page.mouse.click(point);
  }
  await Future<void>.delayed(const Duration(milliseconds: 1200));
}

double _centre(Map<String, Object?> box, String axis, String size) =>
    (box[axis]! as num).toDouble() + (box[size]! as num).toDouble() / 2;

void main() {
  late HttpServer server;
  late Browser browser;

  setUpAll(() async {
    final String web = p.join(_app, 'build', 'web');
    if (Platform.environment['DV_PAGE_BUTTON_PREBUILT'] != '1' || !File(p.join(web, 'main.dart.js')).existsSync()) {
      for (final List<String> command in <List<String>>[
        <String>['pub', 'get'],
        <String>['build', 'web', '--release', '--no-wasm-dry-run'],
      ]) {
        final ProcessResult result = await Process.run('flutter', command, workingDirectory: _app, runInShell: true);
        if (result.exitCode != 0) fail('flutter ${command.join(' ')} failed:\n${result.stdout}\n${result.stderr}');
      }
    }
    server = await _serve(web);
    browser = await puppeteer.launch(executablePath: await dvChromeExecutable(), args: dvChromeLaunchArgs);
  });

  tearDownAll(() async {
    await browser.close();
    await server.close(force: true);
  });

  for (final (int width, int height) in const <(int, int)>[(1366, 900), (390, 844)]) {
    for (final bool touch in <bool>[false, true]) {
      final String input = touch ? 'a finger' : 'a mouse';
      test('at $width px with $input: the button takes only its own circle, and the header link opens', () async {
        final Page page = await browser.newPage();
        addTearDown(page.close);
        await page.setViewport(DeviceViewport(width: width, height: height, hasTouch: touch, isMobile: touch));
        final String origin = 'http://127.0.0.1:${server.port}';
        await page.goto('$origin/', wait: Until.networkIdle);

        final Map<String, Object?> button = await _waitNode(page, 'To the bottom');
        expect((button['width']! as num).toDouble(), lessThanOrEqualTo(48), reason: 'button node $button');
        expect((button['height']! as num).toDouble(), lessThanOrEqualTo(48), reason: 'button node $button');

        // A press on the page, away from the button and the link, scrolls
        // nothing: on the empty part of the header (where only the window-
        // sized node was), and on the page's text.
        final Map<String, Object?> rowBefore = await _waitNode(page, 'Row 3');
        for (final (num x, num y) in <(num, num)>[(width * 0.75, 35), (width / 3, 300)]) {
          await _press(page, touch, x, y);
          expect(await _node(page, 'Back to top'), isNull, reason: 'a press at ($x, $y) scrolled the page to the bottom');
          final Map<String, Object?> rowAfter = await _waitNode(page, 'Row 3');
          expect(rowAfter['y'], rowBefore['y'], reason: 'a press at ($x, $y) moved the page');
        }

        // The button's own circle, as drawn at the bottom right.
        await _press(page, touch, width - 20 - 22, height - 20 - 22);
        await _waitNode(page, 'Back to top', timeout: const Duration(seconds: 5));
        await _press(page, touch, width - 20 - 22, height - 20 - 22);
        await _waitNode(page, 'To the bottom', timeout: const Duration(seconds: 5));

        // The header link opens its page, and the page does not jump first.
        final Map<String, Object?> link = await _waitNode(page, 'Home link');
        await _press(page, touch, _centre(link, 'x', 'width'), _centre(link, 'y', 'height'));
        final DateTime end = DateTime.now().add(const Duration(seconds: 10));
        String path = '/';
        while (DateTime.now().isBefore(end)) {
          path = await page.evaluate<String>('() => location.pathname');
          if (path == '/linked') break;
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        expect(path, '/linked', reason: 'the header link did not open');
      });
    }
  }
}
