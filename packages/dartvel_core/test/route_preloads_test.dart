// A served route names its own code and first-frame images in its head.
//
// A static build writes each page's preloads into that page's HTML. A server
// answers every route from one shell, so it has no page to write them into:
// it reads them per route from the prefetch manifest the build wrote and
// puts them in the head it sends -- in the part `streaming: shell` sends
// before the data, since they depend on the route and never on the data.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const String manifest = '''
{"routes": {
  "/docs": {
    "scripts": ["main.dart.js_2.part.js", "main.dart.js_5.part.js"],
    "images": [
      {"url": "assets/assets/hero.png", "as": "fetch", "slot": 320},
      {"url": "https://cdn.example.com/a.jpg", "as": "image"}
    ]
  },
  "/products/:id": {"scripts": ["main.dart.js_7.part.js"], "images": []},
  "/": {"scripts": [], "images": []}
}}
''';

void main() {
  group('a route\'s own preloads', () {
    final DVRoutePreloads preloads = DVRoutePreloads.parse(manifest);

    test('its parts as scripts and its images the way they are fetched', () {
      // The same shapes the static build writes: a preload is only reused
      // by a request made the same way, so fetch() bytes need crossorigin.
      expect(
        preloads.linksFor('/docs'),
        '<link rel="preload" href="main.dart.js_2.part.js" as="script">\n'
        '<link rel="preload" href="main.dart.js_5.part.js" as="script">\n'
        '<link rel="preload" href="assets/assets/hero.png" as="fetch" '
        'crossorigin="anonymous">\n'
        '<link rel="preload" href="https://cdn.example.com/a.jpg" '
        'as="image">\n',
      );
    });

    test('keyed by the pattern the request matched, not its path', () {
      expect(preloads.linksFor('/products/:id'),
          contains('href="main.dart.js_7.part.js"'));
      expect(preloads.linksFor('/products/5'), isEmpty);
    });

    test('a route with nothing to name gets nothing', () {
      expect(preloads.linksFor('/'), isEmpty);
      expect(preloads.linksFor('/nowhere'), isEmpty);
    });

    test('nothing the shell already names is preloaded again', () {
      const String shell = '<head><link rel="preload" '
          'href="main.dart.js_2.part.js" as="script">'
          '<style>#s{background:url("assets/assets/hero.png")}</style></head>';
      final String links = preloads.linksFor('/docs', shell: shell);
      expect(links, isNot(contains('main.dart.js_2.part.js')));
      expect(links, isNot(contains('hero.png')));
      expect(links, contains('main.dart.js_5.part.js'));
    });

    test('an image drawn through a variant is not named in a head', () {
      // Which variant a visitor needs depends on their screen, which the
      // server cannot know when it writes the head -- the static build keeps
      // these out of its heads for the same reason. A link prefetches them
      // once it knows the screen.
      final DVRoutePreloads variants = DVRoutePreloads.parse('''
{"routes": {"/shop": {"scripts": [], "images": [
  {"url": "assets/_dartvel/img/640/hero.webp", "as": "fetch",
   "variant": {"src": "assets/hero.png", "width": 320}},
  {"url": "assets/assets/logo.png", "as": "fetch"}
]}}}''');
      final String links = variants.linksFor('/shop');
      expect(links, isNot(contains('hero')));
      expect(links, contains('assets/assets/logo.png'));
    });

    test('an address cannot break out of its attribute', () {
      final DVRoutePreloads hostile = DVRoutePreloads.parse(
          '{"routes": {"/x": {"scripts": ["a.js\\"><script>x()</script>"]}}}');
      final String links = hostile.linksFor('/x');
      expect(links, isNot(contains('<script>')));
      expect(links, contains('a.js&quot;&gt;'));
    });

    test('a missing or broken manifest names nothing and throws nothing', () {
      for (final String? broken in <String?>[
        null,
        '',
        'not json',
        '[]',
        '{"routes": []}',
        '{"routes": {"/a": {"scripts": "x", "images": [1, {"url": 2}]}}}',
      ]) {
        final DVRoutePreloads parsed = DVRoutePreloads.parse(broken);
        expect(parsed.linksFor('/a'), isEmpty, reason: '$broken');
      }
      expect(DVRoutePreloads.parse(null).isEmpty, isTrue);
      expect(preloads.isEmpty, isFalse);
    });
  });

  group('into a page', () {
    const String page = '<html><head><title>x</title></head><body></body></html>';

    test('before the end of its head', () {
      final String out = dvWithPreloads(page, '<link rel="preload">\n');
      expect(out.indexOf('<link rel="preload">'),
          lessThan(out.indexOf('</head>')));
      expect(out.indexOf('<link rel="preload">'),
          greaterThan(out.indexOf('<title>')));
    });

    test('nothing to add, or nowhere to add it, leaves the page alone', () {
      expect(dvWithPreloads(page, ''), page);
      expect(dvWithPreloads('<p>no head</p>', '<link>\n'), '<p>no head</p>');
    });
  });
}
