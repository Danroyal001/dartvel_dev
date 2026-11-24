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

    test('two links to the same page are told apart by their names', () {
      // A menu link and a button further down both go to /pricing; the
      // semantics host lists the button first at this width.
      const String doc = '<nav><a href="/pricing" title="Pricing" aria-label="Pricing">Pricing</a></nav>\n'
          '<p><a href="/pricing" title="See plans" aria-label="See plans">See plans</a></p>\n';
      final String out = dvSsrFirstLayout(
        doc,
        _capture(<Map<String, Object?>>[
          _width(390, <Map<String, Object?>>[
            _text('Pricing', <num>[300, 20, 60, 20], z: 1),
            _text('See plans', <num>[40, 700, 100, 20], z: 2),
          ], controls: <Map<String, Object?>>[
            <String, Object?>{'k': 'a', 'href': '/pricing', 'name': 'See plans', 'r': <num>[20, 690, 140, 40]},
            <String, Object?>{'k': 'a', 'href': '/pricing', 'name': 'Pricing', 'r': <num>[290, 10, 80, 40]},
          ]),
        ]),
      );
      final List<String> links = RegExp(r'<a id="(dva\d+)"').allMatches(out).map((RegExpMatch m) => m.group(1)!).toList();
      expect(out, contains('#${links[0]}{left:290px;top:10px'));
      expect(out, contains('#${links[1]}{left:20px;top:690px'));
    });

    test('a link with nothing painted in its box is not placed: a closed menu', () {
      // The semantics host reports a box for a link in a menu that is laid
      // out but invisible; placed, it would sit on top of the page and take
      // its clicks and its Tab stops.
      final String out = dvSsrFirstLayout(
        _doc,
        _capture(<Map<String, Object?>>[
          _width(390, <Map<String, Object?>>[
            _text('Ship faster', <num>[20, 100, 350, 40], z: 1),
          ], controls: <Map<String, Object?>>[
            <String, Object?>{'k': 'a', 'href': '/pricing', 'name': 'See pricing', 'r': <num>[20, 100, 200, 40]},
          ]),
        ]),
      );
      final String link = RegExp(r'<a id="(dva\d+)"').firstMatch(out)!.group(1)!;
      expect(out, contains('#$link{display:none}'));
    });

    test('a link whose box was not found keeps its painted text on screen', () {
      final String out = dvSsrFirstLayout(
        _doc,
        _capture(<Map<String, Object?>>[
          _width(390, <Map<String, Object?>>[
            _text('See pricing', <num>[40, 300, 100, 20], z: 5),
          ]),
        ]),
      );
      final String link = RegExp(r'<a id="(dva\d+)"').firstMatch(out)!.group(1)!;
      final String run = RegExp(r'<span id="(dvr\d+)">See pricing').firstMatch(out)!.group(1)!;
      expect(out, isNot(contains('#$link{display:none}')));
      expect(out, contains('#$run{left:40px;top:300px'));
    });

    test('what a narrower width pinned is placed again, not left pinned, at the next', () {
      // At 400 the link has no box and its text is pinned like an app bar; at
      // 1000 the link has a box and its text sits inside it. The wider range
      // comes later in the stylesheet, so it has to undo the narrower one.
      final String out = dvSsrFirstLayout(
        _doc,
        _capture(<Map<String, Object?>>[
          _width(400, <Map<String, Object?>>[
            _text('See pricing', <num>[40, 300, 100, 20], z: 5, scrolls: false),
          ]),
          _width(1000, <Map<String, Object?>>[
            _text('See pricing', <num>[40, 300, 100, 20], z: 5),
          ], controls: <Map<String, Object?>>[
            <String, Object?>{'k': 'a', 'href': '/pricing', 'name': 'See pricing', 'r': <num>[20, 290, 140, 40]},
          ]),
        ]),
      );
      final String id = RegExp(r'<span id="(dvr\d+)">See pricing').firstMatch(out)!.group(1)!;
      final String wide = out.substring(out.indexOf('@media (min-width:700px){'));
      expect(RegExp('#$id\\{[^}]*position:absolute').hasMatch(wide), isTrue, reason: wide);
    });

    test('only what a later range changes is written again', () {
      final String out = dvSsrFirstLayout(
        _doc,
        _capture(<Map<String, Object?>>[
          _width(400, <Map<String, Object?>>[_text('Ship faster', <num>[50, 100, 300, 40])]),
          _width(1000, <Map<String, Object?>>[_text('Ship faster', <num>[350, 100, 300, 40])]),
        ]),
      );
      final String id = RegExp(r'<span id="(dvr\d+)">Ship faster').firstMatch(out)!.group(1)!;
      // Always on screen, always in the page: no display or position to say.
      expect(RegExp('#$id\\{[^}]*(display|position):').hasMatch(out), isFalse, reason: out);
    });

    test('a z-index that does not change is written once', () {
      final String out = dvSsrFirstLayout(
        _doc,
        _capture(<Map<String, Object?>>[
          _width(400, <Map<String, Object?>>[_text('Ship faster', <num>[50, 100, 300, 40], z: 7)]),
          _width(1000, <Map<String, Object?>>[_text('Ship faster', <num>[350, 100, 300, 40], z: 9)]),
          _width(1600, <Map<String, Object?>>[_text('Ship faster', <num>[650, 100, 300, 40], z: 9)]),
        ]),
      );
      final String id = RegExp(r'<span id="(dvr\d+)">Ship faster').firstMatch(out)!.group(1)!;
      // One line from 400 to 1600 (centred): one placement, and the z-index
      // the nearer capture has.
      expect(RegExp('#$id\\{left:').allMatches(out).length, 2, reason: out);
      expect(RegExp('#$id\\{[^}]*z-index:9').allMatches(out).length, 1);
    });

    test('what is below the fold is placed by a second stylesheet after the document', () {
      final String out = dvSsrFirstLayout(
        _doc,
        _capture(<Map<String, Object?>>[
          _width(390, <Map<String, Object?>>[
            _text('Ship faster', <num>[20, 100, 350, 40]),
            _text('See pricing', <num>[20, 5000, 100, 20]),
          ]),
        ]),
      );
      final String top = RegExp(r'<span id="(dvr\d+)">Ship faster').firstMatch(out)!.group(1)!;
      final String deep = RegExp(r'<span id="(dvr\d+)">See pricing').firstMatch(out)!.group(1)!;
      final List<RegExpMatch> styles = RegExp(r'<style class="dvl-style">(.*?)</style>', dotAll: true).allMatches(out).toList();
      expect(styles, hasLength(2));
      expect(styles.first.group(1), contains('#$top{'));
      expect(styles.first.group(1), isNot(contains('#$deep{')));
      expect(styles.last.group(1), contains('#$deep{'));
      expect(out.indexOf(styles.last.group(0)!), greaterThan(out.indexOf('See pricing')));
      // Until it arrives, what it places is off the screen, not in the way.
      expect(styles.first.group(1), contains('.dvl [id^=dvr]{position:absolute;left:-99999px'));
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

    test('a run filled with a gradient is real text clipped to its gradient', () {
      final String out = dvSsrFirstLayout(
        _doc,
        _capture(<Map<String, Object?>>[
          _width(390, <Map<String, Object?>>[
            _text('Ship faster', <num>[20, 100, 350, 40], runs: <Map<String, Object?>>[
              <String, Object?>{'t': 'Ship ', 'f': 'Inter', 'fs': 32, 'fw': 700, 'c': '#ffffff'},
              <String, Object?>{
                't': 'faster',
                'f': 'Inter',
                'fs': 32,
                'fw': 700,
                'c': '#ffffff',
                'g': 'linear-gradient(120deg,#ffffff 0%,#a3a3a3 100%)',
              },
            ]),
          ]),
        ]),
      );
      expect(out, contains('<h1><span id="dvr'));
      expect(_visibleText(out), _visibleText(_doc));
      final String sub = RegExp(r'<span id="(dvr[\d-]+)">faster</span>').firstMatch(out)!.group(1)!;
      final RegExp rule = RegExp('#$sub[^{]*\\{([^}]*)\\}');
      final String style = rule.firstMatch(out)!.group(1)!;
      expect(style, contains('background-image:linear-gradient(120deg,#ffffff 0%,#a3a3a3 100%)'));
      expect(style, contains('-webkit-background-clip:text'));
      expect(style, contains('-webkit-text-fill-color:transparent'));
      // Selected, the glyphs show again.
      expect(out, contains('::selection{-webkit-text-fill-color:'));
    });

    test('a section the height of the screen grows with the screen', () {
      // Captured at 800 and 1000 high: the hero is the screen's height, the
      // headline sits in its middle and the next section starts below it.
      Map<String, Object?> at(num height) => <String, Object?>{
            'height': height,
            'items': <Map<String, Object?>>[
              <String, Object?>{'k': 'b', 'r': <num>[0, 0, 390, height], 'z': 0, 's': true, 'bg': '#000000'},
              _text('Ship faster', <num>[20, height / 2 - 20, 350, 40], z: 1),
              _text('Build once.', <num>[20, height + 40, 200, 24], z: 2),
            ],
            'controls': <Object?>[],
          };
      final Map<String, Object?> width = _width(390, (at(800)['items']! as List<Object?>).cast())
        ..['tall'] = at(1000);
      final String out = dvSsrFirstLayout(_doc, _capture(<Map<String, Object?>>[width]));
      String id(String text) => RegExp('<span id="(dvr\\d+)">$text').firstMatch(out)!.group(1)!;
      expect(out, contains('#${id('Ship faster')}{left:20px;top:calc(-20px + 50dvh);'));
      expect(out, contains('#${id('Build once.')}{left:20px;top:calc(40px + 100dvh);'));
      final String hero = RegExp(r'<i id="(dvp\d+)">').firstMatch(out)!.group(1)!;
      expect(out, contains('#$hero{left:0px;top:0px;width:390px;height:100dvh'));
      expect(out, contains('.dvl{height:calc(64px + 100dvh)}'));
      // What does not depend on the height is written as before.
      expect(out, contains('left:20px;top:calc(-20px + 50dvh);width:350px;height:40px'));
    });

    test('widths captured at different heights: the height is not read as width', () {
      // 360 is captured 800 high and 390 844 high; the page is the screen's
      // height at both, which is no change with width at all.
      Map<String, Object?> at(int width, num height) {
        List<Map<String, Object?>> items(num h) => <Map<String, Object?>>[
              <String, Object?>{'k': 'b', 'r': <num>[0, 0, width, h], 'z': 0, 's': false, 'bg': '#000000'},
              _text('Ship faster', <num>[20, h - 60, 300, 40], z: 1, scrolls: false),
            ];
        return <String, Object?>{
          'width': width,
          'height': height,
          'light': <String, Object?>{'width': width, 'height': height, 'items': items(height)},
          'controls': <Object?>[],
          'tall': <String, Object?>{'height': height * 1.25, 'items': items(height * 1.25), 'controls': <Object?>[]},
        };
      }

      final String out = dvSsrFirstLayout(_doc, _capture(<Map<String, Object?>>[at(360, 800), at(390, 844)]));
      final String hero = RegExp(r'<i id="(dvp\d+)">').firstMatch(out)!.group(1)!;
      final String id = RegExp(r'<span id="(dvr\d+)">Ship faster').firstMatch(out)!.group(1)!;
      expect(out, isNot(contains('146.67vw')));
      expect(out, contains('#$hero{left:0px;top:0px;width:calc(0px + 100vw);height:100dvh'));
      expect(out, contains('#$id{left:20px;top:calc(-60px + 100dvh);width:300px;height:40px'));
    });

    test('a capture with no second height is laid out as before', () {
      final String out = dvSsrFirstLayout(
        _doc,
        _capture(<Map<String, Object?>>[
          _width(390, <Map<String, Object?>>[_text('Ship faster', <num>[20, 100, 350, 40])]),
        ]),
      );
      expect(out, isNot(contains('dvh')));
    });

    test('a link kept only for readers shows itself when the keyboard reaches it', () {
      final String out = dvSsrFirstLayout(
        _doc,
        _capture(<Map<String, Object?>>[
          _width(390, <Map<String, Object?>>[_text('Ship faster', <num>[20, 100, 350, 40])]),
        ]),
      );
      // "See pricing" is not painted: kept for readers, hidden from the eye,
      // and no Tab stop is ever invisible.
      expect(out, contains('<span class="dvu">See pricing</span>'));
      expect(out, contains('.dvu:focus-within'));
      expect(out, matches(RegExp(r'\.dvl \.dvu:focus-within\{[^}]*clip-path:none')));
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
