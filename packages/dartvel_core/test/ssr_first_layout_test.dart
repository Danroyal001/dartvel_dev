// SSR-first in the app's own look: the document the server sends is laid out
// the way the app's first frame draws the page, from the paint snapshot the
// build's capture took at each width, so the handover changes nothing a
// visitor can see. The document itself stays what it was: same elements,
// same text, same order.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

Map<String, Object?> _text(String text, List<num> rect,
        {int z = 1,
        bool scrolls = true,
        String colour = '#111111',
        String? family = 'Inter',
        num size = 16,
        int weight = 400,
        List<Map<String, Object?>>? runs}) =>
    <String, Object?>{
      'k': 't',
      'r': rect,
      'z': z,
      's': scrolls,
      'text': text,
      'runs': runs ??
          <Map<String, Object?>>[
            <String, Object?>{'t': text, 'f': family, 'fs': size, 'fw': weight, 'c': colour},
          ],
      'al': 'left',
      'lines': 1,
      'lh': 24,
      'nw': true,
    };

Map<String, Object?> _box(List<num> rect, String colour, {int z = 0, bool scrolls = false}) =>
    <String, Object?>{'k': 'b', 'r': rect, 'z': z, 's': scrolls, 'bg': colour, 'rad': <num>[8, 8, 8, 8]};

Map<String, Object?> _width(int width, List<Map<String, Object?>> items,
        {List<Map<String, Object?>>? dark, List<Map<String, Object?>> controls = const <Map<String, Object?>>[]}) =>
    <String, Object?>{
      'width': width,
      'height': 800,
      'light': <String, Object?>{'width': width, 'height': 800, 'items': items},
      if (dark != null) 'dark': <String, Object?>{'width': width, 'height': 800, 'items': dark},
      'controls': controls,
    };

Map<String, Object?> _capture(List<Map<String, Object?>> widths) =>
    <String, Object?>{'widths': widths};

/// The text of [html] with every tag taken out: what find and a crawler read.
String _visibleText(String html) => html
    .replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true), '')
    .replaceAll(RegExp(r'<div class="dvp"[^>]*>.*?</div>', dotAll: true), '')
    .replaceAll(RegExp('<[^>]+>'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

const String _doc = '<h1>Ship faster</h1>\n<p>Build once. Run everywhere.</p>\n'
    '<a href="/pricing" title="See pricing" aria-label="See pricing">See pricing</a>\n';

void main() {
  group('dvSsrFirstLayout', () {
    test('keeps the document: same text, same elements, same order', () {
      final String out = dvSsrFirstLayout(
        _doc,
        _capture(<Map<String, Object?>>[
          _width(390, <Map<String, Object?>>[
            _text('Ship faster', <num>[20, 100, 350, 40]),
            _text('Build once.', <num>[20, 150, 200, 24]),
            _text('Run everywhere.', <num>[20, 174, 200, 24]),
          ]),
        ]),
      );
      expect(_visibleText(out), _visibleText(_doc));
      expect(out, contains('<h1>'));
      expect(out, matches(RegExp(r'<a [^>]*href="/pricing"')));
      expect(out.indexOf('Ship faster'), lessThan(out.indexOf('Build once.')));
    });

    test('places each painted paragraph at its box, in its own style', () {
      final String out = dvSsrFirstLayout(
        _doc,
        _capture(<Map<String, Object?>>[
          _width(390, <Map<String, Object?>>[
            _text('Ship faster', <num>[20, 100, 350, 40], size: 32, weight: 700, colour: '#0a0a0a'),
          ]),
        ]),
      );
      final RegExpMatch run = RegExp(r'<h1><span id="(dvr\d+)">Ship faster</span></h1>').firstMatch(out)!;
      final String id = run.group(1)!;
      expect(out, contains('#$id{'));
      expect(RegExp('#$id\\{[^}]*left:20px;top:100px;width:350px;height:40px').hasMatch(out), isTrue,
          reason: out);
      expect(RegExp('#$id[^{]*\\{[^}]*font:700 32px/24px "Inter"').hasMatch(out), isTrue);
      expect(RegExp('#$id[^{]*\\{[^}]*color:#0a0a0a').hasMatch(out), isTrue);
    });

    test('a sentence the app splits into two paragraphs is two runs', () {
      final String out = dvSsrFirstLayout(
        _doc,
        _capture(<Map<String, Object?>>[
          _width(390, <Map<String, Object?>>[
            _text('Build once.', <num>[20, 150, 200, 24]),
            _text('Run everywhere.', <num>[20, 174, 200, 24]),
          ]),
        ]),
      );
      expect(RegExp(r'<p><span id="dvr\d+">Build once\.</span> <span id="dvr\d+">Run everywhere\.</span></p>')
          .hasMatch(out), isTrue, reason: out);
    });

    test('text the app does not paint stays for readers, hidden from the eye', () {
      final String out = dvSsrFirstLayout(
        _doc,
        _capture(<Map<String, Object?>>[
          _width(390, <Map<String, Object?>>[_text('Ship faster', <num>[20, 100, 350, 40])]),
        ]),
      );
      expect(out, contains('<span class="dvu">Build once. Run everywhere.</span>'));
      expect(out, contains('.dvu{position:absolute;width:1px;height:1px;overflow:hidden;clip-path:inset(50%)'));
    });

    test('between two captured widths every box moves linearly', () {
      final String out = dvSsrFirstLayout(
        _doc,
        _capture(<Map<String, Object?>>[
          // Centred: left = (W - 300) / 2.
          _width(400, <Map<String, Object?>>[_text('Ship faster', <num>[50, 100, 300, 40])]),
          _width(1000, <Map<String, Object?>>[_text('Ship faster', <num>[350, 100, 300, 40])]),
        ]),
      );
      final String id = RegExp(r'<span id="(dvr\d+)">Ship faster').firstMatch(out)!.group(1)!;
      expect(out, contains('#$id{left:calc(-150px + 50vw);top:100px;width:300px;height:40px'));
    });

    test('something on screen at one width only switches at the midpoint', () {
      final String out = dvSsrFirstLayout(
        _doc,
        _capture(<Map<String, Object?>>[
          _width(400, <Map<String, Object?>>[_text('Ship faster', <num>[50, 100, 300, 40])]),
          _width(1000, <Map<String, Object?>>[]),
        ]),
      );
      final String id = RegExp(r'<span id="(dvr\d+)">Ship faster').firstMatch(out)!.group(1)!;
      expect(out, contains('@media (min-width:700px){'));
      final String after = out.substring(out.indexOf('@media (min-width:700px){'));
      expect(after, contains('#$id{display:none}'));
    });

    test('a link is placed at its own box, its text inside it', () {
      final String out = dvSsrFirstLayout(
        _doc,
        _capture(<Map<String, Object?>>[
          _width(390, <Map<String, Object?>>[
            _text('See pricing', <num>[40, 300, 100, 20], z: 5),
          ], controls: <Map<String, Object?>>[
            <String, Object?>{'k': 'a', 'href': '/pricing', 'name': 'See pricing', 'r': <num>[20, 290, 140, 40]},
          ]),
        ]),
      );
      final RegExpMatch link = RegExp(r'<a id="(dva\d+)" href="/pricing"[^>]*><span id="(dvr\d+)">').firstMatch(out)!;
      expect(out, contains('#${link.group(1)}{left:20px;top:290px;width:140px;height:40px'));
      // Relative to the link: 40 - 20, 300 - 290.
      expect(out, contains('#${link.group(2)}{left:20px;top:10px;width:100px;height:20px'));
    });

    test('boxes and images are drawn by an aria-hidden layer that is not text', () {
      final String out = dvSsrFirstLayout(
        _doc,
        _capture(<Map<String, Object?>>[
          _width(390, <Map<String, Object?>>[
            _box(<num>[0, 0, 390, 800], '#ffffff'),
            <String, Object?>{'k': 'i', 'r': <num>[10, 10, 32, 32], 'z': 1, 's': false, 'src': 'assets/logo.png', 'fit': 'contain'},
            <String, Object?>{'k': 'i', 'r': <num>[50, 10, 32, 32], 'z': 2, 's': false, 'src': 'javascript:alert(1)', 'fit': 'contain'},
            _text('\u{e5d2}', <num>[350, 10, 24, 24], z: 3, family: 'MaterialIcons'),
          ]),
        ]),
      );
      final String layer = RegExp(r'<div class="dvp" aria-hidden="true">.*?</div>', dotAll: true).firstMatch(out)!.group(0)!;
      expect(layer, contains('src="assets/logo.png"'));
      expect(layer, isNot(contains('javascript')));
      expect(layer, isNot(contains('\u{e5d2}')), reason: 'decorative text is CSS content, not text');
      expect(out, contains('content:"\\e5d2 "'));
      expect(RegExp(r'#dvp\d+\{[^}]*background-color:#ffffff').hasMatch(out) ||
          RegExp(r'#dvp\d+[^{]*\{[^}]*background-color:#ffffff').hasMatch(out), isTrue);
      expect(out, contains('position:fixed'), reason: 'pinned, like an app bar');
    });

    test('dark colours come from the dark capture', () {
      final String out = dvSsrFirstLayout(
        _doc,
        _capture(<Map<String, Object?>>[
          _width(390, <Map<String, Object?>>[
            _box(<num>[0, 0, 390, 800], '#ffffff'),
            _text('Ship faster', <num>[20, 100, 350, 40], z: 1, colour: '#111111'),
          ], dark: <Map<String, Object?>>[
            _box(<num>[0, 0, 390, 800], '#000000'),
            _text('Ship faster', <num>[20, 100, 350, 40], z: 1, colour: '#eeeeee'),
          ]),
        ]),
      );
      final String dark = out.substring(out.indexOf('@media (prefers-color-scheme:dark){'));
      expect(dark, contains('color:#eeeeee'));
      expect(dark, contains('background-color:#000000'));
    });

    test('only on a screen, with scripting, before the handover', () {
      final String out = dvSsrFirstLayout(
        _doc,
        _capture(<Map<String, Object?>>[
          _width(390, <Map<String, Object?>>[_text('Ship faster', <num>[20, 100, 350, 40])]),
        ]),
      );
      final String style = RegExp(r'<style class="dvl-style">(.*?)</style>', dotAll: true).firstMatch(out)!.group(1)!;
      final int gate = style.indexOf('@media screen and (scripting:enabled){html:not([data-dv-app]){');
      expect(gate, greaterThanOrEqualTo(0));
      // The layer is hidden outside the gate: print, scripting off, after the
      // handover, and a browser that cannot read the nested rules.
      expect(style.indexOf('.dvl .dvp{display:none}'), lessThan(gate));
      expect(style.indexOf('#dvr'), greaterThan(gate));
    });

    test('the app\'s own fonts, by the family names it painted with', () {
      final String out = dvSsrFirstLayout(
        _doc,
        _capture(<Map<String, Object?>>[
          _width(390, <Map<String, Object?>>[
            _text('Ship faster', <num>[20, 100, 350, 40], family: 'Inter', weight: 700),
            _text('Build once.', <num>[20, 150, 200, 24], family: null),
          ]),
        ]),
        fonts: <String, List<DVLayoutFont>>{
          'Inter': <DVLayoutFont>[const DVLayoutFont('assets/fonts/inter.abc.woff2')],
          'Roboto': <DVLayoutFont>[const DVLayoutFont('assets/fonts/roboto.def.woff2', weight: 400)],
          'Unused': <DVLayoutFont>[const DVLayoutFont('assets/fonts/unused.woff2')],
        },
      );
      expect(out, contains('@font-face{font-family:"Inter";src:url(assets/fonts/inter.abc.woff2);'
          'font-weight:1 1000;font-style:normal;font-display:swap}'));
      expect(out, contains('@font-face{font-family:"Roboto";src:url(assets/fonts/roboto.def.woff2);'
          'font-weight:400;font-style:normal;font-display:swap}'));
      expect(out, isNot(contains('unused.woff2')));
      // No family: the engine's default, Roboto.
      expect(RegExp(r'font:400 16px/24px "Roboto"').hasMatch(out), isTrue);
    });

    test('a slot keeps the shape the server fills on each request', () {
      const String slotted = '<p><span data-dv-slot="today">Monday</span></p>\n';
      final String out = dvSsrFirstLayout(
        slotted,
        _capture(<Map<String, Object?>>[
          _width(390, <Map<String, Object?>>[_text('Monday', <num>[20, 100, 100, 24])]),
        ]),
      );
      expect(RegExp(r'<span id="dvr\d+"><span data-dv-slot="today">Monday</span></span>').hasMatch(out), isTrue,
          reason: out);
      expect(dvFillPageSlots(out, <String, String>{'today': 'Tuesday'}), contains('>Tuesday</span>'));
    });

    test('painted text cannot close the style element', () {
      final String out = dvSsrFirstLayout(
        _doc,
        _capture(<Map<String, Object?>>[
          _width(390, <Map<String, Object?>>[_text('</style><script>x()</script>', <num>[0, 0, 10, 10])]),
        ]),
      );
      expect(out, isNot(contains('</style><script>')));
    });

    test('the stylesheet means the same after the page minifier', () {
      final String out = dvSsrFirstLayout(
        _doc,
        _capture(<Map<String, Object?>>[
          _width(400, <Map<String, Object?>>[
            _box(<num>[0, 0, 400, 800], '#ffffff'),
            _text('Ship faster', <num>[50, 100, 300, 40], z: 1),
            _text('\u{e5d2}', <num>[350, 10, 24, 24], z: 2, family: 'MaterialIcons'),
          ]),
          _width(1000, <Map<String, Object?>>[_text('Ship faster', <num>[350, 100, 300, 40], z: 1)]),
        ]),
      );
      String style(String html) =>
          RegExp(r'<style class="dvl-style">(.*?)</style>', dotAll: true).firstMatch(html)!.group(1)!;
      // The minifier reads nested rules as declarations; nothing written may
      // depend on a space it would take out.
      expect(dvMinifyCss(style(out)), style(out));
    });

    test('no capture for a width: the document is returned as it was', () {
      expect(dvSsrFirstLayout(_doc, _capture(<Map<String, Object?>>[])), _doc);
    });
  });

  group('dvFindableHtml with a laid-out document', () {
    test('the style and the aria-hidden layer are not paragraphs', () {
      final String out = dvFindableHtml(
          '<div class="dvl"><style class="dvl-style">a{}</style><div class="dvp" aria-hidden="true"><i id="dvp1"></i></div><p>Text</p></div>');
      expect(out, contains('<style class="dvl-style">a{}</style><div class="dvp" aria-hidden="true"><i id="dvp1"></i></div>'
          '<section hidden="until-found" data-dv-anchor="0"><p>Text</p></section>'));
    });
  });
}
