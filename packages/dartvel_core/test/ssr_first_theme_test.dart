// SSR-first for a page the build could not capture: a parameterised route
// whose document the server writes on request from the application's data
// (ChopDesk's menu at /r/<slug>). There is no paint snapshot of that page,
// so it cannot be laid out box by box; it is laid out in the app's own look,
// worked out by the build from every page it did capture: the fonts, sizes,
// weights and colours the app gives a heading, a paragraph and a link, the
// column the app sets its text in at each width, and the space between
// blocks. Before, such a page was the plain reading column in the system font.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

Map<String, Object?> _text(String text, List<num> rect,
        {String colour = '#111111', String family = 'Inter', num size = 16, int weight = 400, num lineHeight = 24}) =>
    <String, Object?>{
      'k': 't',
      'r': rect,
      'z': 1,
      's': true,
      'text': text,
      'runs': <Map<String, Object?>>[
        <String, Object?>{'t': text, 'f': family, 'fs': size, 'fw': weight, 'c': colour},
      ],
      'al': 'left',
      'lines': 1,
      'lh': lineHeight,
    };

Map<String, Object?> _width(int width, List<Map<String, Object?>> light, List<Map<String, Object?>> dark) =>
    <String, Object?>{
      'width': width,
      'height': 800,
      'light': <String, Object?>{'width': width, 'height': 800, 'items': light},
      'dark': <String, Object?>{'width': width, 'height': 800, 'items': dark},
      'controls': const <Object?>[],
    };

const String _doc = '<h1>Orders from your menu link</h1>\n'
    '<p>ChopDesk gives your buka a menu link.</p>\n'
    '<h2>How it works</h2>\n'
    '<p>Put your menu in.</p>\n';

Map<String, Object?> _page({required int gutter390, required int gutter1366}) => <String, Object?>{
      'widths': <Object?>[
        _width(390, <Map<String, Object?>>[
          _text('Orders from your menu link', <num>[gutter390, 90, 358, 80], size: 32, weight: 700, lineHeight: 40, colour: '#1a1410', family: 'Manrope'),
          _text('ChopDesk gives your buka a menu link.', <num>[gutter390, 186, 358, 48], colour: '#5a5048', family: 'Manrope'),
          _text('How it works', <num>[gutter390, 274, 200, 30], size: 22, weight: 600, lineHeight: 30, colour: '#1a1410', family: 'Manrope'),
          _text('Put your menu in.', <num>[gutter390, 316, 300, 24], colour: '#5a5048', family: 'Manrope'),
        ], <Map<String, Object?>>[
          _text('Orders from your menu link', <num>[gutter390, 90, 358, 80], size: 32, weight: 700, lineHeight: 40, colour: '#f5efe8', family: 'Manrope'),
          _text('ChopDesk gives your buka a menu link.', <num>[gutter390, 186, 358, 48], colour: '#bdb3a8', family: 'Manrope'),
          _text('How it works', <num>[gutter390, 274, 200, 30], size: 22, weight: 600, lineHeight: 30, colour: '#f5efe8', family: 'Manrope'),
          _text('Put your menu in.', <num>[gutter390, 316, 300, 24], colour: '#bdb3a8', family: 'Manrope'),
        ]),
        _width(1366, <Map<String, Object?>>[
          _text('Orders from your menu link', <num>[gutter1366, 110, 600, 56], size: 48, weight: 700, lineHeight: 56, colour: '#1a1410', family: 'Manrope'),
          _text('ChopDesk gives your buka a menu link.', <num>[gutter1366, 190, 1366 - 2 * gutter1366, 24], colour: '#5a5048', family: 'Manrope'),
          _text('How it works', <num>[gutter1366, 260, 200, 30], size: 22, weight: 600, lineHeight: 30, colour: '#1a1410', family: 'Manrope'),
          _text('Put your menu in.', <num>[gutter1366, 302, 300, 24], colour: '#5a5048', family: 'Manrope'),
        ], <Map<String, Object?>>[
          _text('Orders from your menu link', <num>[gutter1366, 110, 600, 56], size: 48, weight: 700, lineHeight: 56, colour: '#f5efe8', family: 'Manrope'),
          _text('ChopDesk gives your buka a menu link.', <num>[gutter1366, 190, 1366 - 2 * gutter1366, 24], colour: '#bdb3a8', family: 'Manrope'),
          _text('How it works', <num>[gutter1366, 260, 200, 30], size: 22, weight: 600, lineHeight: 30, colour: '#f5efe8', family: 'Manrope'),
          _text('Put your menu in.', <num>[gutter1366, 302, 300, 24], colour: '#bdb3a8', family: 'Manrope'),
        ]),
      ],
    };

void main() {
  group('dvSsrFirstTheme', () {
    final String? theme = dvSsrFirstTheme(
      <(String, Map<String, Object?>)>[
        (_doc, _page(gutter390: 16, gutter1366: 93)),
        (_doc, _page(gutter390: 16, gutter1366: 93)),
      ],
      fonts: const <String, List<DVLayoutFont>>{
        'Manrope': <DVLayoutFont>[DVLayoutFont('assets/fonts/Manrope.ttf')],
      },
    );

    test('a heading, a paragraph in the fonts, sizes, weights and colours the app gives them', () {
      expect(theme, isNotNull);
      expect(theme, contains('.dvt h1{font:700 32px/40px "Manrope"'));
      expect(theme, contains('.dvt h2{font:600 22px/30px "Manrope"'));
      expect(theme, contains('.dvt p{font:400 16px/24px "Manrope"'));
      expect(theme, contains('color:#1a1410'));
      expect(theme, contains('color:#5a5048'));
      // The heading's size at a wide screen is the app's wide one.
      expect(theme, contains('.dvt h1{font:700 48px/56px "Manrope"'));
    });

    test('dark colours come from the dark capture', () {
      expect(theme, matches(RegExp(r'prefers-color-scheme:dark\)\{[^@]*\.dvt h1\{color:#f5efe8')));
      expect(theme, contains('color:#bdb3a8'));
    });

    // A length as the stylesheet writes it (`16px`, `calc(Apx + Bvw)`) on a
    // screen [width] wide.
    double at(String length, int width) {
      final RegExpMatch? calc = RegExp(r'calc\((-?[\d.]+)px \+ (-?[\d.]+)vw\)').firstMatch(length);
      if (calc != null) return double.parse(calc.group(1)!) + double.parse(calc.group(2)!) * width / 100;
      return double.parse(length.replaceAll('px', ''));
    }

    // The rules in force on a screen [width] wide: the base, then each
    // min-width block up to it.
    String rulesAt(int width) {
      final String body = theme!.substring(theme!.indexOf('html:not([data-dv-app]){'));
      final int media = body.indexOf('@media (min-width:1366px)');
      return width >= 1366 ? body : body.substring(0, media);
    }

    String last(String rules, String property) =>
        RegExp('\\.dvt\\{[^}]*$property:([^;}]+)').allMatches(rules).last.group(1)!;

    test('the column the app sets its text in, at each width', () {
      expect(at(last(rulesAt(390), 'padding-left'), 390), closeTo(16, 0.5));
      expect(at(last(rulesAt(390), 'padding-right'), 390), closeTo(16, 0.5));
      expect(at(last(rulesAt(1366), 'padding-left'), 1366), closeTo(93, 0.5));
      expect(at(last(rulesAt(1366), 'padding-right'), 1366), closeTo(93, 0.5));
      // The first block starts where the app starts it.
      expect(at(last(rulesAt(390), 'padding-top'), 390), 90);
      expect(at(last(rulesAt(1366), 'padding-top'), 1366), 110);
    });

    // A heading takes the space the app leaves before and after it; the
    // space after a paragraph is the gap to the next paragraph, not to the
    // next section (measured on ChopDesk's menu, the first version used every
    // gap after a paragraph and left 60 px between the dishes of a list).
    test('the space the app leaves around a heading, at each width', () {
      // 390: h1 90 + 80 = 170, paragraph at 186: 16 after it; paragraph
      // 186 + 48 = 234, h2 at 274: 40 before it; h2 274 + 30 = 304,
      // paragraph at 316: 12 after it.
      expect(rulesAt(390), contains('.dvt h1{margin:0 0 16px'));
      expect(rulesAt(390), contains('.dvt h2{margin:40px 0 12px'));
      // 1366: h1 110 + 56 = 166, paragraph at 190: 24; 190 + 24 = 214, h2 at
      // 260: 46.
      expect(rulesAt(1366), contains('.dvt h1{margin:0 0 24px'));
      expect(rulesAt(1366), contains('.dvt h2{margin:46px 0 12px'));
      // No two paragraphs in a row were captured: the default.
      expect(rulesAt(390), isNot(contains('.dvt p{margin:0 0 40px')));
    });

    test("the app's own fonts, and only on a screen with scripting before the handover", () {
      expect(theme, contains('@font-face{font-family:"Manrope"'));
      expect(theme, contains('@media screen and (scripting:enabled){html:not([data-dv-app])'));
      expect(theme, isNot(contains('</style')));
    });

    // ChopDesk's landing page: paragraphs side by side in a grid, and the
    // last paragraph of one section above the first of the next. Neither is
    // the space between two paragraphs of one text; the theme took 96 px.
    test('the space between paragraphs is measured within one column of text', () {
      Map<String, Object?> page(List<Map<String, Object?>> items) =>
          <String, Object?>{'widths': <Object?>[_width(1366, items, items)]};
      const String grid = '<p>Put your menu in.</p>\n<p>Share the link.</p>\n<p>Cook and close.</p>\n'
          '<p>Paid your way.</p>\n<p>Walk-ins too.</p>\n';
      final String? css = dvSsrFirstTheme(<(String, Map<String, Object?>)>[
        (grid, page(<Map<String, Object?>>[
          _text('Put your menu in.', <num>[93, 600, 360, 48]),
          _text('Share the link.', <num>[494, 600, 360, 48]),
          _text('Cook and close.', <num>[895, 600, 360, 48]),
          // The next section, 200 px below.
          _text('Paid your way.', <num>[93, 848, 360, 24]),
          // A paragraph 12 px under the one above it, in the same column.
          _text('Walk-ins too.', <num>[93, 884, 360, 24]),
        ])),
      ]);
      expect(css, contains('.dvt p{margin:0 0 12px'));
    });

    test('no capture: no theme', () {
      expect(dvSsrFirstTheme(const <(String, Map<String, Object?>)>[]), isNull);
    });
  });

  group('a data page on an SSR-first shell with a theme', () {
    final String theme = dvSsrFirstTheme(<(String, Map<String, Object?>)>[
      (_doc, _page(gutter390: 16, gutter1366: 93)),
    ])!;
    String shell(String head) => '<!DOCTYPE html><html><head><title>x</title>$head</head><body>'
        '<script src="flutter_bootstrap.js" async></script></body></html>';
    final String ssrHead = dvSsrFirstHead(background: '#FAF7F2', darkBackground: '#141210', accent: '#B83A12');
    const DVPageData data = DVPageData(title: 'Mma Nkoyo Kitchen: menu', document: <DVDocumentBlock>[
      DVDocumentBlock.heading('Mma Nkoyo Kitchen', level: 1),
      DVDocumentBlock.paragraph('Akwa Ibom soups, cooked fresh every morning.'),
    ]);

    test('is laid out in the theme, through the one render function', () {
      final String page = dvRenderPage(
        shell: shell('$ssrHead${dvSsrFirstThemeStyle(theme)}'),
        path: '/r/mma-nkoyo-kitchen',
        data: data,
      );
      expect(page, contains('class="dvt"'));
      expect(page, contains('Mma Nkoyo Kitchen'));
      expect(page, contains('Akwa Ibom soups, cooked fresh every morning.'));
    });

    test('without a theme it is the reading column it was', () {
      final String page = dvRenderPage(shell: shell(ssrHead), path: '/r/mma-nkoyo-kitchen', data: data);
      expect(page, isNot(contains('class="dvt"')));
    });

    test('a shell without SSR-first is never given the theme wrapper', () {
      final String page = dvRenderPage(shell: shell(dvSsrFirstThemeStyle(theme)), path: '/r/x', data: data);
      expect(page, isNot(contains('class="dvt"')));
    });
  });
}
