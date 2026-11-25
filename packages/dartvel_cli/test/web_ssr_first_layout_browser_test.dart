// SSR-first in the app's own look, in a real browser: the laid-out document
// puts each piece of text, each link and each surface at the box the app's
// first frame draws it in, at the captured widths and moving linearly between
// them; it is still text (selectable, findable), its links still work at
// their own boxes, and at the handover it goes back into the clipped box.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' show Point;

import 'package:dartvel_cli/src/build/chrome_launch.dart';
import 'package:dartvel_cli/src/build/native_splash.dart';
import 'package:dartvel_core/dartvel.dart' show dvApplyPageHtml, dvFirstScreenId, dvSsrFirstLayout;
import 'package:puppeteer/puppeteer.dart';
import 'package:test/test.dart';

const String _shell = '<!DOCTYPE html><html><head><meta charset="UTF-8"><title>t</title></head>'
    '<body><script>/* flutter_bootstrap.js */</script></body></html>';

const String _doc = '<nav><a href="/pricing" title="Pricing" aria-label="Pricing">Pricing</a></nav>\n'
    '<h1>Ship faster</h1>\n<p>Build once. Run everywhere.</p>\n';

Map<String, Object?> _text(String text, List<num> rect, int z, {bool scrolls = true, num size = 16}) =>
    <String, Object?>{
      'k': 't', 'r': rect, 'z': z, 's': scrolls, 'text': text,
      'runs': <Object?>[<String, Object?>{'t': text, 'f': null, 'fs': size, 'fw': 400, 'c': '#111111'}],
      'al': 'left', 'lines': 1, 'lh': rect[3], 'nw': true,
    };

Map<String, Object?> _width(int width, num heroLeft) => <String, Object?>{
      'width': width,
      'height': 800,
      'light': <String, Object?>{
        'items': <Object?>[
          <String, Object?>{'k': 'b', 'r': <num>[0, 0, width, 800], 'z': 0, 's': false, 'bg': '#fafafa'},
          <String, Object?>{'k': 'b', 'r': <num>[0, 0, width, 60], 'z': 1, 's': false, 'bg': '#101820'},
          _text('Pricing', <num>[width - 90, 20, 70, 20], 2, scrolls: false),
          _text('Ship faster', <num>[heroLeft, 120, 300, 40], 3, size: 32),
          _text('Build once.', <num>[heroLeft, 180, 300, 24], 4),
          _text('Run everywhere.', <num>[heroLeft, 204, 300, 24], 5),
          <String, Object?>{'k': 'b', 'r': <num>[heroLeft, 1500, 300, 100], 'z': 6, 's': true, 'bg': '#ff0000'},
        ],
      },
      'controls': <Object?>[
        <String, Object?>{'k': 'a', 'href': '/pricing', 'name': 'Pricing', 'r': <num>[width - 100, 10, 90, 40]},
      ],
    };

late Browser browser;
late HttpServer server;

String _page() => dvApplyPageHtml(
      dvWebSplashApply(
        _shell,
        DVSplash(color: '#FFFFFF', darkColor: '#0A0A0A', progressColor: '#1D4ED8', ssrFirst: true),
      ),
      dvSsrFirstLayout(_doc, <String, Object?>{
        // Centred hero: left = (W - 300) / 2.
        'widths': <Object?>[_width(390, 45), _width(1366, 533)],
      }),
      path: '/',
    );

/// The page at a deep route under `<base href="/">`, as a server on a slow
/// line sends it: up to the end of the first screen, then (once [rest]
/// completes) the stylesheet for below the fold and the rest.
const String _baseShell = '<!DOCTYPE html><html><head><base href="/"><meta charset="UTF-8"><title>t</title></head>'
    '<body><script>/* flutter_bootstrap.js */</script></body></html>';

String _slowPage() => dvApplyPageHtml(
      dvWebSplashApply(
        _baseShell,
        DVSplash(color: '#FFFFFF', darkColor: '#0A0A0A', progressColor: '#1D4ED8', ssrFirst: true),
      ),
      dvSsrFirstLayout(_doc, <String, Object?>{
        'widths': <Object?>[_width(390, 45), _width(1366, 533)],
      }),
      path: '/docs/deep',
    );

Completer<void> rest = Completer<void>();

Future<Page> _open(int width, {int height = 800, String path = '/'}) async {
  final Page page = await browser.newPage();
  await page.setViewport(DeviceViewport(width: width, height: height));
  await page.goto('http://127.0.0.1:${server.port}$path', wait: Until.load);
  return page;
}

/// A hero the height of the screen with its headline in the middle (the end
/// of it filled with a gradient), the next section below it, and a link in
/// a closed menu, captured at 390 x 800 and at 390 x 1000.
const String _extraDoc = '<nav><a href="/menu" aria-label="Hidden menu link">Hidden menu link</a></nav>\n'
    '<h1>Ship faster</h1>\n<p>Build once.</p>\n';

String _extraPage() {
  Map<String, Object?> items(num height) => <String, Object?>{
        'height': height,
        'items': <Object?>[
          <String, Object?>{'k': 'b', 'r': <num>[0, 0, 390, height], 'z': 0, 's': true, 'bg': '#000000'},
          <String, Object?>{
            ..._text('Ship faster', <num>[45, height / 2 - 20, 300, 40], 1, size: 32),
            'runs': <Object?>[
              <String, Object?>{'t': 'Ship ', 'f': null, 'fs': 32, 'fw': 400, 'c': '#ffffff'},
              <String, Object?>{
                't': 'faster', 'f': null, 'fs': 32, 'fw': 400, 'c': '#ffffff',
                'g': 'linear-gradient(90deg,#ffffff 0%,#ff0000 100%)',
              },
            ],
          },
          _text('Build once.', <num>[45, height + 40, 300, 24], 2),
        ],
        'controls': <Object?>[],
      };
  final Map<String, Object?> base = items(800);
  return dvApplyPageHtml(
    dvWebSplashApply(
      _shell,
      DVSplash(color: '#FFFFFF', darkColor: '#0A0A0A', progressColor: '#1D4ED8', ssrFirst: true),
    ),
    dvSsrFirstLayout(_extraDoc, <String, Object?>{
      'widths': <Object?>[
        <String, Object?>{
          'width': 390,
          'height': 800,
          'light': base,
          'controls': <Object?>[],
          'tall': items(1000),
        },
      ],
    }),
    path: '/extra',
  );
}


/// A sentence with two links in it, as the build writes it (one <p>, its
/// links inline) and as the app paints it: its words one paragraph with a
/// gap per link, each link's words a paragraph of their own in its gap.
const String _sentenceDoc = '<h1>Ship faster</h1>\n<p>Questions, or a project in mind? '
    '<a href="/contact" title="Get a free quote" aria-label="Get a free quote">Get a free quote</a>. Our '
    '<a href="/privacy" title="privacy policy" aria-label="privacy policy">privacy policy</a> '
    'explains how we handle your data and your payments.</p>\n';

String _sentencePage() {
  Map<String, Object?> link(String text, List<num> rect, int z) => <String, Object?>{
        ..._text(text, rect, z),
        'runs': <Object?>[
          <String, Object?>{'t': text, 'f': null, 'fs': 16, 'fw': 400, 'c': '#1d4ed8', 'd': 'underline'},
        ],
      };
  return dvApplyPageHtml(
    dvWebSplashApply(
      _shell,
      DVSplash(color: '#FFFFFF', darkColor: '#0A0A0A', progressColor: '#1D4ED8', ssrFirst: true),
    ),
    dvSsrFirstLayout(_sentenceDoc, <String, Object?>{
      'widths': <Object?>[
        <String, Object?>{
          'width': 390,
          'height': 800,
          'light': <String, Object?>{
            'items': <Object?>[
              _text('Ship faster', <num>[20, 40, 350, 40], 1, size: 32),
              <String, Object?>{
                ..._text('Questions, or a project in mind? . Our  explains how we handle your data and your payments.',
                    <num>[20, 120, 350, 96], 2),
                'nw': false, 'lines': 4, 'lh': 24,
              },
              link('Get a free quote', <num>[20, 144, 130, 24], 3),
              link('privacy policy', <num>[200, 144, 110, 24], 4),
            ],
          },
          'controls': <Object?>[
            <String, Object?>{'k': 'a', 'href': '/contact', 'name': 'Get a free quote', 'r': <num>[20, 144, 130, 24]},
            <String, Object?>{'k': 'a', 'href': '/privacy', 'name': 'privacy policy', 'r': <num>[200, 144, 110, 24]},
          ],
        },
      ],
    }),
    path: '/sentence',
  );
}

Future<List<num>> _box(Page page, String text) async {
  final List<Object?> box = await page.evaluate<List<Object?>>('''(text) => {
    const span = [...document.querySelectorAll('.dv-fallback span[id^=dvr]')]
        .find((el) => el.textContent === text);
    const r = span.getBoundingClientRect();
    return [r.left, r.top, r.width, r.height];
  }''', args: <Object?>[text]);
  return box.cast<num>();
}

/// A form as sigmadev.digital's keyword density checker draws it: a label
/// above an empty multi-line field with a hint, and a one-line field the app
/// starts at "1", as the build writes them and the app paints them.
const String _formDoc = '<h1>Keyword density</h1>\n'
    '<p><label for="dv-field-1">Your content</label> '
    '<textarea id="dv-field-1" name="Your content" data-dv-field="Your content"></textarea></p>\n'
    '<p><label for="dv-field-2">Phrase length</label> '
    '<input id="dv-field-2" type="text" name="Phrase length" data-dv-field="Phrase length"></p>\n'
    '<p><strong role="button" aria-label="Add to order">Add to order</strong></p>\n'
    '<a href="/menu" aria-label="Menu">Menu</a>\n';

String _formPage() {
  Map<String, Object?> editable(String text, List<num> rect, {bool oneLine = true}) => <String, Object?>{
        ..._text(text, rect, 5),
        'k': 'e',
        if (!oneLine) 'nw': null,
      };
  return dvApplyPageHtml(
    dvWebSplashApply(
      _shell,
      DVSplash(color: '#FFFFFF', darkColor: '#0A0A0A', progressColor: '#1D4ED8', ssrFirst: true),
    ),
    dvSsrFirstLayout(_formDoc, <String, Object?>{
      'widths': <Object?>[
        <String, Object?>{
          'width': 390,
          'height': 800,
          'light': <String, Object?>{
            'items': <Object?>[
              <String, Object?>{'k': 'b', 'r': <num>[0, 0, 390, 800], 'z': 0, 's': false, 'bg': '#fafafa'},
              _text('Keyword density', <num>[20, 40, 350, 40], 1, size: 32),
              _text('Your content', <num>[20, 280, 200, 20], 2),
              <String, Object?>{
                'k': 'b', 'r': <num>[20, 304, 350, 260], 'z': 3, 's': true, 'bg': '#ffffff',
                'bd': <Object?>[1, '#cccccc'], 'rad': <num>[8, 8, 8, 8],
              },
              editable('', <num>[36, 320, 318, 228], oneLine: false),
              <String, Object?>{
                ..._text('Paste your page', <num>[36, 320, 200, 24], 5),
                'runs': <Object?>[<String, Object?>{'t': 'Paste your page', 'f': null, 'fs': 16, 'fw': 400, 'c': '#888888'}],
              },
              _text('Phrase length', <num>[20, 590, 200, 20], 2),
              <String, Object?>{
                'k': 'b', 'r': <num>[20, 614, 350, 50], 'z': 3, 's': true, 'bg': '#ffffff',
                'bd': <Object?>[1, '#cccccc'], 'rad': <num>[8, 8, 8, 8],
              },
              editable('1', <num>[36, 627, 318, 24]),
              <String, Object?>{'k': 'b', 'r': <num>[20, 690, 160, 44], 'z': 3, 's': true, 'bg': '#1d4ed8'},
              _text('Add to order', <num>[40, 700, 120, 24], 4),
              _text('Menu', <num>[220, 700, 60, 24], 4),
            ],
          },
          'controls': <Object?>[
            <String, Object?>{'k': 'b', 'name': 'Add to order', 'r': <num>[20, 690, 160, 44]},
            <String, Object?>{'k': 'a', 'href': '/menu', 'name': 'Menu', 'r': <num>[210, 690, 80, 44]},
            <String, Object?>{'k': 'f', 'name': 'Your content', 'r': <num>[20, 304, 350, 260]},
            <String, Object?>{'k': 'f', 'name': 'Phrase length', 'r': <num>[20, 614, 350, 50]},
          ],
        },
      ],
    }),
    path: '/form',
  );
}

void main() {
  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((HttpRequest request) {
      request.response.headers.contentType = ContentType.html;
      if (request.uri.path == '/docs/deep') {
        final String page = _slowPage();
        final int split = page.indexOf('<i id="$dvFirstScreenId"');
        request.response.bufferOutput = false;
        request.response.write(page.substring(0, split < 0 ? page.length ~/ 2 : split));
        request.response.flush().then((_) => rest.future).then((_) {
          request.response.write(page.substring(split < 0 ? page.length ~/ 2 : split));
          return request.response.close();
        });
        return;
      }
      request.response.write(request.uri.path == '/'
          ? _page()
          : request.uri.path == '/extra'
              ? _extraPage()
              : request.uri.path == '/sentence'
              ? _sentencePage()
              : request.uri.path == '/form'
              ? _formPage()
              : '<!DOCTYPE html><title>next</title><p id="landed">${request.uri.path}</p>');
      request.response.close();
    });
    browser = await puppeteer.launch(executablePath: await dvChromeExecutable(), args: dvChromeLaunchArgs);
  });
  tearDownAll(() async {
    await browser.close();
    await server.close(force: true);
  });

  test('at a captured width every piece of text is at its captured box', () async {
    for (final (int width, num left) in <(int, num)>[(390, 45), (1366, 533)]) {
      final Page page = await _open(width);
      expect(await _box(page, 'Ship faster'), <num>[left, 120, 300, 40], reason: 'at $width');
      expect(await _box(page, 'Build once.'), <num>[left, 180, 300, 24]);
      final List<num> link = await _box(page, 'Pricing');
      expect(link, <num>[width - 90, 20, 70, 20]);
      await page.close();
    }
  });

  test('between captured widths it moves linearly', () async {
    final Page page = await _open(800);
    final List<num> hero = await _box(page, 'Ship faster');
    expect(hero[0], closeTo(250, 0.6));
    await page.close();
  });

  test('surfaces are drawn behind the text, in their colours', () async {
    final Page page = await _open(390);
    final String colour = await page.evaluate<String>('''() => {
      const at = [...document.querySelectorAll('.dvp > *')].filter((el) => {
        const r = el.getBoundingClientRect();
        return r.left <= 5 && r.right >= 5 && r.top <= 30 && r.bottom >= 30;
      }).sort((a, b) => getComputedStyle(b).zIndex - getComputedStyle(a).zIndex)[0];
      return getComputedStyle(at).backgroundColor;
    }''');
    expect(colour, 'rgb(16, 24, 32)');
    await page.close();
  });

  test('it is still text: selectable, and on top where it is drawn', () async {
    final Page page = await _open(390);
    final List<num> box = await _box(page, 'Ship faster');
    final bool onTop = await page.evaluate<bool>('''(x, y) => {
      const el = document.elementFromPoint(x, y);
      return el.textContent === 'Ship faster';
    }''', args: <Object?>[box[0] + 10, box[1] + 10]);
    expect(onTop, isTrue);
    await page.mouse.click(Point<num>(box[0] + 2, box[1] + 20), clickCount: 3);
    expect(await page.evaluate<String>('() => getSelection().toString().trim()'), 'Ship faster');
    await page.close();
  });

  test('a section the height of the screen fits a screen of another height', () async {
    for (final int height in <int>[640, 800, 1200]) {
      final Page page = await _open(390, height: height, path: '/extra');
      final List<num> headline = await _box(page, 'Ship faster');
      expect(headline[1], closeTo(height / 2 - 20, 0.6), reason: 'headline at $height');
      final List<num> next = await _box(page, 'Build once.');
      expect(next[1], closeTo(height + 40, 0.6), reason: 'next section at $height');
      await page.close();
    }
  });

  test('gradient text is still the text, cut out of its gradient, and visible when selected', () async {
    final Page page = await _open(390, path: '/extra');
    final Map<String, Object?> style = await page.evaluate<Map<String, Object?>>('''() => {
      const span = [...document.querySelectorAll('.dv-fallback span[id^=dvr]')]
          .find((el) => el.textContent === 'faster');
      const own = getComputedStyle(span);
      const selected = getComputedStyle(span, '::selection');
      return {clip: own.webkitBackgroundClip, fill: own.webkitTextFillColor,
              image: own.backgroundImage, selectedFill: selected.webkitTextFillColor};
    }''');
    expect(style['clip'], 'text');
    expect(style['fill'], 'rgba(0, 0, 0, 0)');
    expect(style['image'] as String, startsWith('linear-gradient(90deg'));
    expect(style['selectedFill'], isNot('rgba(0, 0, 0, 0)'));
    // Find and selection read it as one heading.
    expect(await page.evaluate<String>('() => document.querySelector(".dv-fallback h1").textContent'), 'Ship faster');
    await page.close();
  });

  test('a link kept only for readers is never an invisible Tab stop', () async {
    final Page page = await _open(390, path: '/extra');
    await page.keyboard.press(Key.tab);
    final Map<String, Object?> focused = await page.evaluate<Map<String, Object?>>('''() => {
      const el = document.activeElement;
      const r = el.getBoundingClientRect();
      return {text: el.textContent, w: r.width, h: r.height, top: r.top,
              clip: getComputedStyle(el.closest('.dvu') || el).clipPath};
    }''');
    expect(focused['text'], 'Hidden menu link');
    expect(focused['w'] as num, greaterThan(20));
    expect(focused['h'] as num, greaterThan(10));
    expect(focused['top'] as num, inInclusiveRange(0, 800));
    expect(focused['clip'], 'none');
    await page.close();
  });

  test('a link works at its own box, the app bar stays put when scrolled', () async {
    final Page page = await _open(390);
    await page.evaluate<void>('() => document.querySelector(".dv-fallback").scrollTop = 600');
    final List<num> link = await _box(page, 'Pricing');
    expect(link[1], 20, reason: 'pinned like the app bar');
    await Future.wait(<Future<Object?>>[
      page.waitForNavigation(),
      page.mouse.click(Point<num>(390 - 95 + 2, 12)),
    ]);
    expect(page.url, endsWith('/pricing'));
    await page.close();
  });

  test('a sentence with links is one block of text, its links in its line', () async {
    // Each piece placed on its own drew the links over the words with gaps
    // and stray punctuation where they belong ("Our , and explain"), and
    // find and a selection stopped at every link (sigmadev.digital/about).
    final Page page = await _open(390, path: '/sentence');
    final Map<String, Object?> layout = await page.evaluate<Map<String, Object?>>('''() => {
      const p = [...document.querySelectorAll('.dv-fallback p')].find((el) => el.textContent.includes('Questions'));
      const rect = (r) => [r.left, r.top, r.right, r.bottom];
      const words = document.createRange();
      words.selectNodeContents(p.firstChild.nodeType === 3 ? p.firstChild : p.firstChild.firstChild);
      const before = [...words.getClientRects()].pop();
      const quote = p.querySelector('a[href="/contact"]').getClientRects()[0];
      const privacy = p.querySelector('a[href="/privacy"]').getClientRects()[0];
      const block = p.querySelector('span[id^=dvr]').getBoundingClientRect();
      const layer = [...document.querySelectorAll('.dvp > *')]
          .map((el) => getComputedStyle(el, '::before').content).join(' ');
      return {before: rect(before), quote: rect(quote), privacy: rect(privacy), block: rect(block), layer,
              blockText: p.querySelector('span[id^=dvr]').textContent};
    }''');
    final List<num> before = (layout['before']! as List<Object?>).cast<num>();
    final List<num> quote = (layout['quote']! as List<Object?>).cast<num>();
    final List<num> privacy = (layout['privacy']! as List<Object?>).cast<num>();
    final List<num> block = (layout['block']! as List<Object?>).cast<num>();
    // The sentence is where the app paints it, and holds all of itself.
    expect(block[0], closeTo(20, 0.6));
    expect(block[1], closeTo(120, 0.6));
    expect(layout['blockText'], 'Questions, or a project in mind? Get a free quote. Our privacy policy '
        'explains how we handle your data and your payments.');
    // Its own words are drawn (not hidden for readers), by the document, not
    // by the layer.
    expect(before[2] - before[0], greaterThan(50));
    expect(layout['layer'] as String, isNot(contains('Questions')));
    // Each link follows the words before it in the line: never on top of
    // them, never off on a line of its own.
    for (final List<num> link in <List<num>>[quote, privacy]) {
      expect(link[0], greaterThanOrEqualTo(block[0] - 0.5));
      expect(link[2], lessThanOrEqualTo(block[0] + 350 + 0.5));
      expect(link[1], greaterThanOrEqualTo(block[1] - 0.5));
    }
    final bool sameLine = (quote[1] - before[1]).abs() < 1;
    expect(sameLine ? quote[0] >= before[2] - 0.5 : quote[1] >= before[3] - 0.5, isTrue,
        reason: 'the link starts after the words before it: $before, $quote');
    expect(privacy[1] > quote[1] || privacy[0] >= quote[2], isTrue, reason: 'in reading order');
    // Find runs across a link, and a selection reads the sentence as it is.
    expect(await page.evaluate<bool>("() => window.find('free quote. Our privacy policy explains')"), isTrue);
    await page.evaluate<void>('''() => {
      const p = [...document.querySelectorAll('.dv-fallback p')].find((el) => el.textContent.includes('Questions'));
      getSelection().selectAllChildren(p);
    }''');
    expect(await page.evaluate<String>('() => getSelection().toString().replace(/\\\\s+/g, " ").trim()'),
        'Questions, or a project in mind? Get a free quote. Our privacy policy explains how we handle your data and your payments.');
    // The link is still a link: styled as the app styles it, and it works.
    final String decoration = await page.evaluate<String>(
        '() => getComputedStyle(document.querySelector(\'.dv-fallback p a[href="/contact"] span\')).textDecorationLine');
    expect(decoration, 'underline');
    await Future.wait(<Future<Object?>>[
      page.waitForNavigation(),
      page.mouse.click(Point<num>(quote[0] + 5, (quote[1] + quote[3]) / 2)),
    ]);
    expect(page.url, endsWith('/contact'));
    await page.close();
  });

  test('the page scrolls as far as the app\'s content goes', () async {
    final Page page = await _open(390);
    final num height = await page.evaluate<num>('() => document.querySelector(".dv-fallback").scrollHeight');
    expect(height, greaterThanOrEqualTo(1600));
    await page.close();
  });

  test('nothing is painted until the first screen is in: never the bare canvas, never half of it', () async {
    // The head holds rendering until the end of the first screen is parsed
    // (a render-blocking expect link). A deep route under <base href="/">:
    // a bare "#id" would resolve against the base, name another page and be
    // ignored, so the link names this page.
    rest = Completer<void>();
    final Page page = await browser.newPage();
    await page.setViewport(DeviceViewport(width: 390, height: 800));
    unawaited(page.goto('http://127.0.0.1:${server.port}/docs/deep', wait: Until.domContentLoaded).catchError((Object _) => null));
    // The document holds everything up to the marker, its own first stylesheet
    // included, and would have painted long before this.
    await page.waitForFunction('() => !!document.querySelector(".dvl")');
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    final num paintsBefore = await page.evaluate<num>('() => performance.getEntriesByType("paint").length');
    rest.complete();
    await page.waitForFunction('() => performance.getEntriesByType("paint").length > 0');
    expect(paintsBefore, 0, reason: 'painted before the first screen was parsed');
    final bool blocking = await page.evaluate<bool>('''() => [...document.querySelectorAll('link[rel=expect]')]
        .some((l) => l.href === location.href.split('#')[0] + '#$dvFirstScreenId' && l.blocking.contains('render'))''');
    expect(blocking, isTrue);
    await page.close();
  });

  test('at the handover the layout and its layer are gone', () async {
    final Page page = await _open(390);
    await page.evaluate<void>('() => window.dispatchEvent(new Event("dartvel-first-frame"))');
    await page.waitForFunction('() => document.documentElement.hasAttribute("data-dv-app")');
    final bool layerHidden = await page.evaluate<bool>(
        '() => getComputedStyle(document.querySelector(".dvp")).display === "none"');
    expect(layerHidden, isTrue);
    final num width = await page.evaluate<num>(
        '() => document.querySelector(".dv-fallback").getBoundingClientRect().width');
    expect(width, lessThanOrEqualTo(1));
    await page.close();
  });

  test('print gets the reading column, not the layout', () async {
    final Page page = await _open(390);
    await page.emulateMediaType(MediaType.print);
    final String position = await page.evaluate<String>('''() => {
      const span = document.querySelector('.dv-fallback span[id^=dvr]');
      return getComputedStyle(span).position;
    }''');
    expect(position, 'static');
    await page.close();
  });
  // sigmadev.digital's keyword density checker, live on Dartvel 3.47.9: the
  // "Your content" box was drawn, but a tap on it hit the painting and typing
  // went nowhere until Flutter took over (8-15 s on a phone). A click or a
  // tap on a field's painted box is a click on the document's own field, and
  // the keyboard types into it.
  for (final bool touch in <bool>[false, true]) {
    test('a ${touch ? 'tap' : 'click'} on a field\'s painted box types into it, in the app\'s style', () async {
      final Page page = await browser.newPage();
      await page.setViewport(DeviceViewport(width: 390, height: 800, isMobile: touch, hasTouch: touch));
      await page.goto('http://127.0.0.1:${server.port}/form', wait: Until.load);
      // Middle of the painted box, well inside it.
      final Map<String, Object?> hit = await page.evaluate<Map<String, Object?>>("""() => {
        const el = document.elementFromPoint(195, 430);
        return {id: el && el.id, tag: el && el.tagName};
      }""");
      expect(hit['id'], 'dv-field-1', reason: 'the painting must not take the tap: $hit');
      if (touch) {
        await page.touchscreen.tap(const Point<num>(195, 430));
      } else {
        await page.mouse.click(const Point<num>(195, 430));
      }
      await page.keyboard.type('hello world');
      final Map<String, Object?> typed = await page.evaluate<Map<String, Object?>>("""() => {
        const el = document.activeElement, s = getComputedStyle(el), r = el.getBoundingClientRect();
        return {id: el.id, value: el.value, size: s.fontSize, padTop: s.paddingTop, padLeft: s.paddingLeft,
          x: r.left, y: r.top, w: r.width, h: r.height, placeholder: el.placeholder};
      }""");
      expect(typed['id'], 'dv-field-1');
      expect(typed['value'], 'hello world');
      expect(typed['size'], '16px');
      expect(typed['padTop'], '16px', reason: 'the first line starts where the app starts it');
      expect(typed['padLeft'], '16px');
      expect(<num>[typed['x']! as num, typed['y']! as num, typed['w']! as num, typed['h']! as num],
          <num>[20, 304, 350, 260], reason: 'over the painted box');
      expect(typed['placeholder'], 'Paste your page');
      // The one-line field: Tab reaches it, it holds the app's "1".
      await page.keyboard.press(Key.tab);
      final Map<String, Object?> next = await page.evaluate<Map<String, Object?>>(
          '() => ({id: document.activeElement.id, value: document.activeElement.value})');
      expect(next, <String, Object?>{'id': 'dv-field-2', 'value': '1'});
      await page.close();
    });
  }
  // ChopDesk on 3G: a tap in the first seconds after load did nothing while
  // the app took over, and on a desktop the first click on a link sometimes
  // did nothing. Nothing pressed on the server-rendered page is dropped: a
  // link navigates, a button pressed before or during the handover is
  // pressed on the app's button once it is there, a field tapped during the
  // handover is focused in the app.
  test('a click before or during the handover is never dropped', () async {
    final Page page = await browser.newPage();
    await page.setViewport(DeviceViewport(width: 390, height: 800));
    await page.goto('http://127.0.0.1:${server.port}/form', wait: Until.load);
    // The app, as its semantics tree puts it on the page once it has drawn:
    // the same button and field where the document has them.
    await page.evaluate("""() => {
      window.appPresses = []; window.appFocus = null;
      const host = document.createElement('flt-semantics-host');
      host.style.cssText = 'position:fixed;left:0;top:0;width:390px;height:800px;z-index:0';
      host.innerHTML = '<flt-semantics role="button" aria-label="Add to order" style="position:absolute;left:20px;top:690px;width:160px;height:44px;display:block"></flt-semantics>'
        + '<input aria-label="Your content" style="position:absolute;left:20px;top:304px;width:350px;height:260px">';
      document.body.prepend(host);
      host.firstElementChild.addEventListener('click', () => window.appPresses.push('Add to order'));
      host.lastElementChild.addEventListener('focus', () => window.appFocus = 'Your content');
    }""");
    // Before: a press on the button.
    await page.mouse.click(const Point<num>(100, 712));
    expect(await page.evaluate<String?>('() => document.querySelector(".dv-fallback [aria-label=\\"Add to order\\"]").getAttribute("aria-busy")'),
        'true');
    // The app has drawn: the handover starts, and a tap lands on the field
    // while the document fades.
    await page.evaluate('() => window.dispatchEvent(new Event("dartvel-first-frame"))');
    await page.mouse.click(const Point<num>(195, 430));
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final Map<String, Object?> after = await page.evaluate<Map<String, Object?>>(
        '() => ({app: document.documentElement.hasAttribute("data-dv-app"), presses: window.appPresses, focus: window.appFocus})');
    expect(after['app'], isTrue);
    expect(after['presses'], <Object?>['Add to order'], reason: 'pressed once, on the app');
    expect(after['focus'], 'Your content', reason: 'the tap during the handover reaches the app');
    await page.close();
  });

  test('a link clicked during the handover navigates', () async {
    final Page page = await browser.newPage();
    await page.setViewport(DeviceViewport(width: 390, height: 800));
    // The fade is the window: with reduced motion there is none.
    await page.devTools.client.send('Emulation.setEmulatedMedia', <String, Object?>{
      'features': <Map<String, String>>[<String, String>{'name': 'prefers-reduced-motion', 'value': 'no-preference'}],
    });
    await page.goto('http://127.0.0.1:${server.port}/form', wait: Until.load);
    await page.evaluate('() => window.dispatchEvent(new Event("dartvel-first-frame"))');
    await Future.wait(<Future<void>>[
      page.waitForNavigation(timeout: const Duration(seconds: 5)),
      page.mouse.click(const Point<num>(250, 712)),
    ]);
    expect(await page.evaluate<String>('() => location.pathname'), '/menu');
    await page.close();
  });
}
