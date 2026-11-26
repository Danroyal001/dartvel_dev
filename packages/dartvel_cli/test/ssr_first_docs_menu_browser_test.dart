// SSR-first on a docs-style page, end to end in a real browser: a header
// whose GitHub and pub.dev links show only on a wide screen, and a side menu
// of links that a narrow screen folds into an "Open the docs menu" button.
//
// dartvel.dev shipped every docs page but the first few with its side menu
// and its header links painted as pictures of text: no <a> behind them, not
// found by Ctrl+F, not reached by Tab. The semantics read of each route that
// a tab moved to after its first was taken at 800 px wide, because the layout
// capture of the route before it put the page back at a fixed 800 x 600
// instead of the size it found it at. At 800 px the docs shell is the narrow
// one, so the document had a menu button and no menu, while the layout
// capture saw the menu painted at 1366 and 1920 and drew it as decoration.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:dartvel_cli/src/build/chrome_launch.dart';
import 'package:dartvel_cli/src/build/native_splash.dart';
import 'package:dartvel_cli/src/build/semantic_html.dart';
import 'package:dartvel_cli/src/build/semantics_capture.dart';
import 'package:dartvel_cli/src/build/ssr_first_capture.dart';
import 'package:dartvel_core/dartvel.dart' show dvApplyPageHtml;
import 'package:path/path.dart' as p;
import 'package:puppeteer/puppeteer.dart';
import 'package:test/test.dart';

/// The menu every docs page carries.
const List<(String, String)> _menu = <(String, String)>[
  ('/docs/a', 'Getting started'),
  ('/docs/b', 'Routing'),
  ('/docs/c', 'State management'),
];

const List<(String, String)> _headerLinks = <(String, String)>[
  ('https://github.com/example/repo', 'GitHub'),
  ('https://pub.dev/packages/example', 'pub.dev'),
];

/// A stand-in for the docs app, with the capture hook: below 1000 px the
/// menu and the header links fold into one icon button; from 1000 px the
/// header shows GitHub and pub.dev (an icon and a word each) and the side
/// menu lists every page. It paints what its semantics host says, so the
/// layout capture sees the same page the semantics read sees.
String _docsApp() {
  final String menu = jsonEncode(<List<String>>[
    for (final (String href, String label) in _menu) <String>[href, label],
  ]);
  final String header = jsonEncode(<List<String>>[
    for (final (String href, String label) in _headerLinks) <String>[href, label],
  ]);
  return '''<!DOCTYPE html><html><head><title>docs</title>
<style>body{margin:0} flt-semantics-host *{position:absolute;display:block;margin:0;font:16px/24px sans-serif}</style>
</head><body><script>
const menu = $menu;
const header = $header;
let told = matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
matchMedia('(prefers-color-scheme: dark)').addEventListener('change', (event) => {
  told = event.matches ? 'dark' : 'light';
});
function parts() {
  const width = innerWidth;
  const wide = width >= 1000;
  const out = [{kind: 'a', href: '/', label: 'Dartvel', r: [16, 16, 90, 24], fixed: true}];
  if (wide) {
    header.forEach(([href, label], index) => {
      out.push({kind: 'icon', r: [width - 240 + index * 110, 18, 20, 20], fixed: true});
      out.push({kind: 'a', href, label, aria: label, r: [width - 216 + index * 110, 16, 80, 24], fixed: true});
    });
    menu.forEach(([href, label], index) => {
      out.push({kind: 'a', href, label, r: [16, 96 + index * 40, 200, 24]});
    });
  } else {
    out.push({kind: 'button', label: 'Open the docs menu', r: [width - 56, 8, 40, 40], fixed: true});
  }
  const left = wide ? 260 : 16;
  out.push({kind: 'h1', label: 'Page ' + location.pathname, r: [left, 96, 600, 40]});
  out.push({kind: 'p', label: 'What ' + location.pathname + ' is about.', r: [left, 160, 600, 24]});
  return out;
}
function render() {
  const old = document.querySelector('flt-semantics-host');
  if (old) old.remove();
  const host = document.createElement('flt-semantics-host');
  for (const part of parts()) {
    let el;
    if (part.kind === 'a') {
      el = document.createElement('a');
      el.setAttribute('href', part.href);
      if (part.aria) el.setAttribute('aria-label', part.aria);
      else el.textContent = part.label;
    } else if (part.kind === 'button') {
      el = document.createElement('flt-semantics');
      el.setAttribute('role', 'button');
      el.setAttribute('aria-label', part.label);
    } else if (part.kind === 'h1') {
      el = document.createElement('h1');
      el.textContent = part.label;
    } else if (part.kind === 'p') {
      el = document.createElement('flt-semantics');
      const span = document.createElement('span');
      span.textContent = part.label;
      el.append(span);
    } else {
      continue;
    }
    el.style.left = part.r[0] + 'px';
    el.style.top = part.r[1] + 'px';
    el.style.width = part.r[2] + 'px';
    el.style.height = part.r[3] + 'px';
    host.append(el);
  }
  document.body.append(host);
}
addEventListener('resize', render);
globalThis.__dartvelCapture = {
  go(path) { history.pushState({}, '', path); render(); },
  location() { return location.pathname; },
  idle: () => true,
  brightness: () => told,
  snapshot() {
    const ink = told === 'dark' ? '#f5f5f5' : '#111111';
    const items = [{k: 'b', r: [0, 0, innerWidth, innerHeight], z: 0, s: false, bg: told === 'dark' ? '#0a0a0a' : '#ffffff'}];
    let z = 1;
    for (const part of parts()) {
      if (part.kind === 'icon') {
        items.push({k: 'b', r: part.r, z: z++, s: !part.fixed, bg: ink, rad: [4, 4, 4, 4]});
        continue;
      }
      if (part.kind === 'button') {
        items.push({k: 'b', r: part.r, z: z++, s: false, bg: ink});
        continue;
      }
      const size = part.kind === 'h1' ? 32 : 16;
      items.push({
        k: 't', r: part.r, z: z++, s: !part.fixed, text: part.label,
        runs: [{t: part.label, f: null, fs: size, fw: part.kind === 'h1' ? 700 : 400, c: ink}],
        al: 'left', lines: 1, lh: part.r[3], nw: true,
      });
    }
    return JSON.stringify({width: innerWidth, height: innerHeight, brightness: told, items});
  },
};
render();
</script></body></html>''';
}

const String _shell = '<!DOCTYPE html><html><head><base href="/"><meta charset="UTF-8"><title>t</title></head>'
    '<body><script>/* flutter_bootstrap.js */</script></body></html>';

void main() {
  late Directory root;
  late Directory web;
  final List<String> routes = <String>['/docs/a', '/docs/b', '/docs/c'];

  setUpAll(() async {
    root = Directory.systemTemp.createTempSync('dv_docs_menu_');
    web = Directory(p.join(root.path, 'build', 'web'))..createSync(recursive: true);
    File(p.join(web.path, 'index.html')).writeAsStringSync(_docsApp());
    // One tab, moved from route to route inside the running app, with the
    // layout capture after each read: what `dartvel build web` does with
    // ssrFirst on.
    final run = await dvCaptureSemantics(
      projectRoot: root.path,
      webRoot: web.path,
      routes: routes,
      concurrency: 1,
      layoutWidths: const <int>[390, 1366],
      settle: const Duration(seconds: 6),
    );
    expect(run.browserAvailable, isTrue, reason: 'this test needs Chrome');
    expect(run.captured, routes.length);
  });
  tearDownAll(() => root.deleteSync(recursive: true));

  test('every route is read at the same size, whatever the layout capture of the route before it did', () {
    for (final String route in routes) {
      final String tree = File(dvSemanticsPathFor(root.path, route)).readAsStringSync();
      for (final (String href, String label) in <(String, String)>[..._menu, ..._headerLinks]) {
        expect(tree, contains('"href":"$href"'), reason: '$route has the "$label" link');
      }
      expect(tree, isNot(contains('Open the docs menu')),
          reason: '$route was read at the width the first route was read at, not the narrow one');
    }
  });

  test('the layout capture puts the page back at the size it found it at', () async {
    final Browser browser =
        await puppeteer.launch(executablePath: await dvChromeExecutable(), args: dvChromeLaunchArgs);
    addTearDown(browser.close);
    final Page page = await browser.newPage();
    await page.setViewport(const DeviceViewport(width: 1280, height: 1024));
    await page.setContent(_docsApp());
    final String path = p.join(root.path, 'restore.layout.json');
    expect(await dvCaptureLayout(page, const <int>[390, 1366], path: path), isTrue);
    expect(await page.evaluate<List<Object?>>('() => [innerWidth, innerHeight]'), <Object?>[1280, 1024]);
    expect(page.viewport?.width, 1280);
  }, timeout: const Timeout(Duration(minutes: 2)));

  group('the laid-out docs page in a browser', () {
    late Browser browser;
    late HttpServer server;

    setUpAll(() async {
      final Map<String, String> pages = <String, String>{
        for (final String route in routes)
          route: dvApplyPageHtml(
            dvWebSplashApply(
              _shell,
              DVSplash(color: '#FFFFFF', darkColor: '#0A0A0A', progressColor: '#1D4ED8', ssrFirst: true),
            ),
            dvApplySsrFirstLayout(
              root.path,
              route,
              dvSemanticHtml(DVSemanticNode.listFromJson(
                  File(dvSemanticsPathFor(root.path, route)).readAsStringSync())),
              const {},
            ),
            path: route,
          ),
      };
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest request) {
        request.response.headers.contentType = ContentType.html;
        request.response.write(pages[request.uri.path] ?? '<!DOCTYPE html><title>x</title>');
        request.response.close();
      });
      browser = await puppeteer.launch(executablePath: await dvChromeExecutable(), args: dvChromeLaunchArgs);
    });
    tearDownAll(() async {
      await browser.close();
      await server.close(force: true);
    });

    Future<Page> open(String route, {int width = 1366, String scheme = 'light'}) async {
      final Page page = await browser.newPage();
      await page.setViewport(DeviceViewport(width: width, height: 900));
      await page.emulateMediaFeatures(<MediaFeature>[MediaFeature.prefersColorsScheme(scheme)]);
      await page.goto('http://127.0.0.1:${server.port}$route', wait: Until.load);
      return page;
    }

    for (final String route in routes) {
      for (final String scheme in <String>['light', 'dark']) {
        test('$route ($scheme): each menu and header link is a real link over its painted text', () async {
          final Page page = await open(route, scheme: scheme);
          addTearDown(page.close);
          for (final (String href, String label) in <(String, String)>[..._menu, ..._headerLinks]) {
            final Map<String, Object?> found = (await page.evaluate<Map<dynamic, dynamic>>('''(href, label) => {
              const link = document.querySelector('a[href="' + href + '"]');
              if (!link) return {link: false};
              const box = link.getBoundingClientRect();
              const hit = document.elementFromPoint(box.left + box.width / 2, box.top + box.height / 2);
              const words = [...link.querySelectorAll('span')].find((span) =>
                  span.textContent === label && span.getBoundingClientRect().width > 0);
              const seen = words ? getComputedStyle(words) : null;
              return {
                link: true,
                box: [box.left, box.top, box.width, box.height],
                onTop: !!hit && (hit === link || link.contains(hit)),
                words: !!words && seen.visibility !== 'hidden' && seen.opacity !== '0' && seen.color !== 'rgba(0, 0, 0, 0)',
              };
            }''', args: <Object?>[href, label])).cast<String, Object?>();
            expect(found['link'], isTrue, reason: '$label is an <a href="$href">');
            final List<num> box = (found['box']! as List<Object?>).cast<num>();
            expect(box[2] * box[3], greaterThan(0), reason: '$label has a box on screen');
            expect(found['onTop'], isTrue, reason: 'a press on $label lands on its link');
            expect(found['words'], isTrue, reason: '$label is drawn as the link\'s own text');
          }
          // Nothing the app paints as a link's words is decoration.
          final List<Object?> pictured = await page.evaluate<List<Object?>>('''() =>
            [...document.querySelectorAll('.dvp *')]
              .map((el) => getComputedStyle(el, '::before').content)
              .filter((content) => content && content !== 'none' && content !== 'normal')''');
          for (final (_, String label) in <(String, String)>[..._menu, ..._headerLinks]) {
            expect(pictured, isNot(contains('"$label"')), reason: '$label is not a picture of text');
          }
        }, timeout: const Timeout(Duration(minutes: 1)));
      }

      test('$route: Ctrl+F finds each link and Tab reaches it', () async {
        final Page page = await open(route);
        addTearDown(page.close);
        for (final (String href, String label) in <(String, String)>[..._menu, ..._headerLinks]) {
          final bool found = await page.evaluate<bool>('''(href, label) => {
            getSelection().removeAllRanges();
            if (!window.find(label, true, false, true)) return false;
            const node = getSelection().anchorNode;
            const element = node && (node.nodeType === 1 ? node : node.parentElement);
            return !!element && !!element.closest('a[href="' + href + '"]');
          }''', args: <Object?>[href, label]);
          expect(found, isTrue, reason: 'find "$label" lands in its link');
        }
        final Set<String> reached = <String>{};
        for (int press = 0; press < 30; press++) {
          await page.keyboard.press(Key.tab);
          final String? at = await page.evaluate<String?>(
              '() => document.activeElement && document.activeElement.getAttribute("href")');
          if (at != null) reached.add(at);
        }
        for (final (String href, String label) in <(String, String)>[..._menu, ..._headerLinks]) {
          expect(reached, contains(href), reason: 'Tab reaches $label');
        }
      }, timeout: const Timeout(Duration(minutes: 1)));
    }
  });
}
