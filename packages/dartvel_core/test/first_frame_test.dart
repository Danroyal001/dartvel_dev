import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const DVFirstFrame light390 = DVFirstFrame(
  width: 390,
  dark: false,
  src: '/dv-first-frame/docs-390-light.webp',
  texts: <DVFirstFrameText>[
    DVFirstFrameText('Getting started', left: 24, top: 80, width: 200, height: 36),
    DVFirstFrameText('Routing', left: 24, top: 140, width: 80, height: 20, href: '/docs/routing'),
    DVFirstFrameText('<script>alert(1)</script>', left: 24, top: 180, width: 80, height: 20),
  ],
);
const DVFirstFrame dark390 = DVFirstFrame(
  width: 390,
  dark: true,
  src: '/dv-first-frame/docs-390-dark.webp',
  texts: <DVFirstFrameText>[],
);
const DVFirstFrame light1366 = DVFirstFrame(
  width: 1366,
  dark: false,
  src: '/dv-first-frame/docs-1366-light.webp',
  texts: <DVFirstFrameText>[
    DVFirstFrameText('Getting started', left: 300, top: 70, width: 300, height: 40),
  ],
);

void main() {
  group('the first frame block', () {
    final String html = dvFirstFrameHtml(<DVFirstFrame>[light390, dark390, light1366]);

    test('shows each picture only at its own width and colour scheme', () {
      expect(html, contains('@media (width:390px) and (prefers-color-scheme:light)'));
      expect(html, contains('@media (width:390px) and (prefers-color-scheme:dark)'));
      expect(html, contains('@media (width:1366px) and (prefers-color-scheme:light)'));
      expect(html, contains("url('/dv-first-frame/docs-390-dark.webp')"));
    });

    test('a scheme with no capture of its own uses the light one at that width', () {
      // Without the dark capture at 1366, a dark reader at 1366 gets the light
      // picture only when the app has no dark look (no dark capture anywhere);
      // here it has one, so 1366 dark keeps the splash.
      expect(html, isNot(contains('@media (width:1366px) and (prefers-color-scheme:dark)')));
      final String lightOnly = dvFirstFrameHtml(<DVFirstFrame>[light1366]);
      expect(lightOnly, contains('@media (width:1366px){'));
    });

    test('hides the splash where a picture shows, and nowhere else', () {
      expect(RegExp(r'@media \(width:390px\) and \(prefers-color-scheme:light\)\{[^@]*#dartvel-splash')
          .hasMatch(html), isTrue);
      expect(html, isNot(contains('#dartvel-splash{display:none}\n')));
    });

    test('lays the text over the picture where it is drawn, selectable and findable', () {
      expect(html, contains('left:24px;top:80px;width:200px;height:36px'));
      expect(html, contains('>Getting started<'));
      expect(html, contains('color:transparent'));
    });

    test('a link stays a link', () {
      expect(html, contains('<a href="/docs/routing"'));
    });

    test('escapes what the page drew', () {
      expect(html, isNot(contains('<script>alert')));
      expect(html, contains('&lt;script&gt;'));
    });

    test('is hidden from screen readers, which read the page document instead', () {
      expect(html, contains('id="dv-first-frame" aria-hidden="true"'));
    });

    test('goes when Flutter draws its first frame, and never shows without script', () {
      expect(html, contains('flutter-first-frame'));
      expect(html, contains('<noscript><style>#dv-first-frame{display:none!important}</style></noscript>'));
    });

    test('nothing to show is nothing written', () {
      expect(dvFirstFrameHtml(const <DVFirstFrame>[]), isEmpty);
    });
  });

  test('a route page carries its first frames through its manifest', () {
    const DVRoutePage page = DVRoutePage(route: '/docs', title: 'Docs', firstFrames: <DVFirstFrame>[light390]);
    final DVRoutePage back = DVRoutePage.fromJson(page.toJson());
    expect(back.firstFrames.single.src, light390.src);
    expect(back.firstFrames.single.texts[1].href, '/docs/routing');
    expect(back.firstFrames.single.texts.first.top, 80);
  });

  test('a page rendered at another path has no first frame: it shows something else', () {
    const DVRoutePage page = DVRoutePage(route: '/notes/:id', title: 'Note', firstFrames: <DVFirstFrame>[light390]);
    expect(page.at('/notes/7').firstFrames, isEmpty);
    expect(page.at('/notes/:id').firstFrames, hasLength(1));
  });

  test('the rendered page holds the block right after the body opens', () {
    const String shell = '<!DOCTYPE html><html><head><title>t</title></head><body><script src="flutter_bootstrap.js"></script></body></html>';
    final String out = dvRenderRoutePage(shell,
        const DVRoutePage(route: '/docs', title: 'Docs', firstFrames: <DVFirstFrame>[light390]));
    expect(out, contains('id="dv-first-frame"'));
    expect(out.indexOf('id="dv-first-frame"'), lessThan(out.indexOf('flutter_bootstrap.js')));
  });
}
