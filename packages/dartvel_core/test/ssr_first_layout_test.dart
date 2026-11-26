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

    test('a button whose box is the whole screen is not placed over the page: the page shell\'s scroll button', () {
      // sigmadev.digital at 1366 (3.47.10): the page shell's "To the bottom"
      // node covers the screen on the semantics host and has no words of its
      // own painted. Everything painted lies inside its box, so it counted as
      // painted, was placed above the page, and took every click on the
      // header links and the hero's buttons.
      const String doc = '<p><strong role="button" aria-label="To the bottom"><span>To the bottom</span></strong></p>\n'
          '<a href="/pricing" title="See pricing" aria-label="See pricing">See pricing</a>\n';
      final String out = dvSsrFirstLayout(
        doc,
        _capture(<Map<String, Object?>>[
          _width(1366, <Map<String, Object?>>[
            _box(<num>[0, 0, 1366, 800], '#ffffff'),
            _text('See pricing', <num>[600, 20, 90, 24], z: 2, scrolls: false),
          ], controls: <Map<String, Object?>>[
            <String, Object?>{'k': 'b', 'name': 'To the bottom', 'r': <num>[0, 0, 1366, 800]},
            <String, Object?>{'k': 'a', 'href': '/pricing', 'name': 'See pricing', 'r': <num>[590, 10, 110, 44]},
          ]),
        ]),
      );
      final String button = RegExp(r'<strong [^>]*id="(dva\d+)"').firstMatch(out)!.group(1)!;
      final String link = RegExp(r'<a id="(dva\d+)"').firstMatch(out)!.group(1)!;
      expect(out, isNot(contains('#$button{left:0px;top:0px')), reason: 'not laid over the page');
      expect(out, matches(RegExp('<strong id="$button"[^>]*class="dvf"|<strong[^>]*class="dvf"[^>]*id="$button"')),
          reason: 'kept for readers, a Tab stop that shows itself when focused');
      expect(out, contains('#$link{left:590px;top:10px'));
    });

    test('a menu link off screen at a width does not take the same words painted elsewhere', () {
      // "Tools" is a header link (in a closed menu at 390) and a footer
      // heading. At 390 only the heading is painted; the link must not claim
      // it, or the link becomes a zero-size Tab stop and the heading loses
      // its text.
      const String doc = '<nav><a href="/tools" aria-label="Tools">Tools</a></nav>\n'
          '<footer><h3>Tools</h3></footer>\n';
      final String out = dvSsrFirstLayout(
        doc,
        _capture(<Map<String, Object?>>[
          _width(390, <Map<String, Object?>>[
            _text('Tools', <num>[20, 2000, 40, 15], z: 3),
          ]),
          _width(1366, <Map<String, Object?>>[
            _text('Tools', <num>[600, 20, 40, 20], z: 2, scrolls: false),
            _text('Tools', <num>[20, 1500, 40, 15], z: 3),
          ], controls: <Map<String, Object?>>[
            <String, Object?>{'k': 'a', 'href': '/tools', 'name': 'Tools', 'r': <num>[598, 18, 44, 24]},
          ]),
        ]),
      );
      final String link = RegExp(r'<a id="(dva\d+)"').firstMatch(out)!.group(1)!;
      final String heading = RegExp(r'<h3><span id="(dvr\d+)">Tools').firstMatch(out)!.group(1)!;
      // At 390 (the first range) the link is not on screen, and the heading
      // is where the app paints it: 2000 px down at 390, 1500 at 1366.
      expect(out, contains('#$link{display:none}'));
      expect(out, contains('#$heading{left:20px;top:calc(2199.8px + -51.23vw)'));
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

    // sigmadev.digital, SSR-first, before the handover: the hero's link
    // labels showed through the consent banner on a phone and a desktop.
    // Every link was stacked above everything painted, so it stayed above a
    // banner pinned to the screen that the app paints over it.
    test('what is pinned over a link and painted after it covers it', () {
      const String doc = '<a href="/pricing" title="See pricing" aria-label="See pricing">See pricing</a>\n'
          '<h2>Cookies and measurement</h2>\n'
          '<a href="/privacy" title="Privacy policy" aria-label="Privacy policy">Privacy policy</a>\n';
      final String out = dvSsrFirstLayout(
        doc,
        _capture(<Map<String, Object?>>[
          _width(390, <Map<String, Object?>>[
            // A page background pinned behind everything, painted first.
            _box(<num>[0, 0, 390, 800], '#ffffff', z: 0),
            _text('See pricing', <num>[40, 700, 100, 20], z: 5),
            // The banner, pinned to the bottom of the screen, over the link.
            _box(<num>[0, 600, 390, 200], '#fafafa', z: 10),
            _text('Cookies and measurement', <num>[16, 620, 300, 24], z: 11, scrolls: false),
            _text('Privacy policy', <num>[16, 760, 120, 20], z: 12, scrolls: false),
          ], controls: <Map<String, Object?>>[
            <String, Object?>{'k': 'a', 'href': '/pricing', 'name': 'See pricing', 'r': <num>[20, 690, 140, 40]},
            <String, Object?>{'k': 'a', 'href': '/privacy', 'name': 'Privacy policy', 'r': <num>[16, 755, 140, 30], 's': false},
          ]),
        ]),
      );
      int zOf(String id) {
        final RegExpMatch? found = RegExp('#$id\\{[^}]*z-index:(\\d+)').firstMatch(out);
        expect(found, isNotNull, reason: 'no z-index for #$id in $out');
        return int.parse(found!.group(1)!);
      }

      final String heroLink = RegExp(r'<a id="(dva\d+)" href="/pricing"').firstMatch(out)!.group(1)!;
      final String bannerLink = RegExp(r'<a id="(dva\d+)" href="/privacy"').firstMatch(out)!.group(1)!;
      final String heading = RegExp(r'<span id="(dvr\d+)">Cookies and measurement').firstMatch(out)!.group(1)!;
      final List<String> boxes = <String>[
        for (final RegExpMatch m in RegExp(r'#(dvp\d+)\{[^}]*background-color:(#[0-9a-f]+)').allMatches(out))
          if (m.group(2) == '#fafafa') m.group(1)!,
      ];
      final List<String> backgrounds = <String>[
        for (final RegExpMatch m in RegExp(r'#(dvp\d+)\{[^}]*background-color:(#[0-9a-f]+)').allMatches(out))
          if (m.group(2) == '#ffffff') m.group(1)!,
      ];
      expect(boxes, isNotEmpty, reason: out);
      expect(zOf(boxes.first), greaterThan(zOf(heroLink)), reason: 'the banner covers the link under it');
      expect(zOf(heading), greaterThan(zOf(heroLink)));
      expect(zOf(bannerLink), greaterThan(zOf(boxes.first)), reason: "the banner's own link is on the banner");
      expect(zOf(backgrounds.first), lessThan(zOf(heroLink)), reason: 'a pinned background stays behind');
    });

    // sigmadev.digital's tools, SSR-first: each field drew its box and stood
    // empty until Flutter took over, though the app starts it with a link.
    test('a field shows the text the app starts it with, in its style', () {
      const String doc = '<p><label for="dv-field-1">Link or text</label> '
          '<input id="dv-field-1" type="text" name="Link or text" data-dv-field="Link or text"></p>\n';
      Map<String, Object?> typed(String text, List<num> rect) => <String, Object?>{
            ..._text(text, rect, z: 4, size: 17, colour: '#123456'),
            'k': 'e',
          };
      final String out = dvSsrFirstLayout(
        doc,
        _capture(<Map<String, Object?>>[
          _width(390, <Map<String, Object?>>[
            _text('Link or text', <num>[20, 80, 200, 20], z: 1),
            _box(<num>[20, 100, 350, 50], '#ffffff', z: 2, scrolls: true),
            typed('https://sigmadev.digital', <num>[36, 113, 318, 24]),
            // A field the document has no input for (a menu that picks a
            // value): its text is drawn.
            typed('QR code', <num>[36, 213, 280, 24]),
          ], controls: <Map<String, Object?>>[
            <String, Object?>{'k': 'f', 'name': 'Link or text', 'r': <num>[20, 100, 350, 50]},
            <String, Object?>{'k': 'f', 'name': '', 'r': <num>[20, 200, 350, 50]},
          ]),
        ]),
      );
      final String input = RegExp(r'<input[^>]*>').firstMatch(out)!.group(0)!;
      expect(input, contains('value="https://sigmadev.digital"'));
      final RegExpMatch style = RegExp(r'#dv-field-1\{[^}]*font:[^}]*\}').firstMatch(out) ??
          (throw TestFailure('no style for the field in $out'));
      expect(style.group(0), contains('17px'));
      expect(style.group(0), contains('color:#123456'));
      expect(style.group(0), contains('padding:0 16px 0 16px'), reason: 'the text starts where the app starts it');
      expect(_visibleText(out), isNot(contains('https://sigmadev.digital')),
          reason: 'a value, not text the document says twice');
      expect(out, contains('content:"QR code"'), reason: 'drawn, where the document has no input');
    });

    // sigmadev.digital's keyword density checker, live on Dartvel 3.47.9: the
    // "Your content" box was painted where the app draws it, but the
    // document's own textarea was never placed there -- it stayed in the
    // reading column under the painted layer -- so a tap on the box hit the
    // painting and typing went nowhere until Flutter took over (8-15 s on a
    // phone). Every field is the document's own input, over its box.
    test('a field is placed over its painted box, so a tap types into it', () {
      const String doc = '<p><label for="dv-field-1">Your content</label> '
          '<textarea id="dv-field-1" name="Your content" data-dv-field="Your content"></textarea></p>\n'
          '<p><label for="dv-field-2">Phrase length</label> '
          '<input value="1" id="dv-field-2" type="text" name="Phrase length" data-dv-field="Phrase length"></p>\n';
      Map<String, Object?> editable(String text, List<num> rect, {bool oneLine = true}) => <String, Object?>{
            ..._text(text, rect, z: 4, size: 16, colour: '#0a0a0a'),
            'k': 'e',
            if (!oneLine) 'nw': null,
          };
      final String out = dvSsrFirstLayout(
        doc,
        _capture(<Map<String, Object?>>[
          _width(390, <Map<String, Object?>>[
            _text('Your content', <num>[20, 480, 200, 20], z: 1),
            _box(<num>[20, 504, 350, 260], '#ffffff', z: 2, scrolls: true),
            editable('', <num>[40, 520, 310, 228], oneLine: false),
            _text('Phrase length', <num>[20, 790, 200, 20], z: 1),
            _box(<num>[20, 814, 350, 50], '#ffffff', z: 2, scrolls: true),
            editable('1', <num>[40, 827, 310, 24]),
          ], controls: <Map<String, Object?>>[
            <String, Object?>{'k': 'f', 'name': 'Your content', 'r': <num>[20, 504, 350, 260]},
            <String, Object?>{'k': 'f', 'name': 'Phrase length', 'r': <num>[20, 814, 350, 50]},
          ]),
        ]),
      );
      for (final (String id, String box) in <(String, String)>[
        ('dv-field-1', 'left:20px;top:504px;width:350px;height:260px'),
        ('dv-field-2', 'left:20px;top:814px;width:350px;height:50px'),
      ]) {
        final RegExpMatch placed = RegExp('#$id\\{left:[^}]*\\}').firstMatch(out) ??
            (throw TestFailure('$id is never placed: $out'));
        expect(placed.group(0), contains(box));
        expect(placed.group(0), contains('position:absolute'));
        expect(placed.group(0), contains('z-index:'), reason: 'above what is painted, so the tap is its own');
      }
      // An empty field has the style typing takes: the app's font, where the
      // app starts its text, top and side.
      final String style = RegExp(r'#dv-field-1\{[^}]*font:[^}]*\}').firstMatch(out)?.group(0) ??
          (throw TestFailure('no style for the empty field in $out'));
      expect(style, contains('16px'));
      expect(style, contains('color:#0a0a0a'));
      expect(style, contains('padding:16px 20px 16px 20px'), reason: 'text starts where the app starts it');
      expect(out, contains('<label for="dv-field-1">'), reason: 'the label still names it');
    });

    test("a textarea starts with the app's text, as its content", () {
      const String doc = '<p><label for="dv-field-1">Rows</label> '
          '<textarea id="dv-field-1" name="Rows" data-dv-field="Rows"></textarea></p>\n';
      final String out = dvSsrFirstLayout(
        doc,
        _capture(<Map<String, Object?>>[
          _width(390, <Map<String, Object?>>[
            <String, Object?>{..._text('a,b\n1,2', <num>[36, 113, 318, 48], z: 4), 'k': 'e', 'nw': null},
          ], controls: <Map<String, Object?>>[
            <String, Object?>{'k': 'f', 'name': 'Rows', 'r': <num>[20, 100, 350, 80]},
          ]),
        ]),
      );
      expect(out, contains('data-dv-field="Rows">a,b\n1,2</textarea>'));
      expect(out, isNot(contains('content:"a,b')), reason: 'in the field, not drawn over it');
    });

    test("an empty field's hint is its placeholder, gone when the visitor types", () {
      const String doc = '<p><label for="dv-field-1">Link</label> '
          '<input id="dv-field-1" type="text" name="Link" data-dv-field="Link"></p>\n';
      final String out = dvSsrFirstLayout(
        doc,
        _capture(<Map<String, Object?>>[
          _width(390, <Map<String, Object?>>[
            _box(<num>[20, 100, 350, 50], '#ffffff', z: 2, scrolls: true),
            <String, Object?>{..._text('', <num>[36, 113, 318, 24], z: 4), 'k': 'e'},
            _text('https://example.com', <num>[36, 113, 200, 24], z: 4, colour: '#888888'),
          ], controls: <Map<String, Object?>>[
            <String, Object?>{'k': 'f', 'name': 'Link', 'r': <num>[20, 100, 350, 50]},
          ]),
        ]),
      );
      final String input = RegExp(r'<input[^>]*>').firstMatch(out)!.group(0)!;
      expect(input, contains('placeholder="https://example.com"'));
      expect(out, isNot(contains('content:"https://example.com"')),
          reason: 'drawn over the field, it stays on top of what is typed');
      expect(out, contains('#dv-field-1::placeholder{color:#888888'));
    });

    // sigmadev.digital's keyword density checker: an icon glyph painted at
    // the end of an empty field was taken for its hint -- an empty-looking
    // placeholder, and the icon gone from the page.
    test("an icon in an empty field is drawn, never taken for the field's hint", () {
      const String doc = '<p><label for="dv-field-1">Rows</label> '
          '<textarea id="dv-field-1" name="Rows" data-dv-field="Rows"></textarea></p>\n';
      final String out = dvSsrFirstLayout(
        doc,
        _capture(<Map<String, Object?>>[
          _width(390, <Map<String, Object?>>[
            <String, Object?>{..._text('', <num>[36, 113, 318, 228], z: 4), 'k': 'e', 'nw': null},
            _text('\u{e5cd}', <num>[312, 300, 20, 20], z: 5, family: 'MaterialIcons'),
          ], controls: <Map<String, Object?>>[
            <String, Object?>{'k': 'f', 'name': 'Rows', 'r': <num>[20, 100, 350, 260]},
          ]),
        ]),
      );
      expect(out, isNot(contains('placeholder=')));
      expect(out, contains(r'content:"\e5cd "'), reason: 'the icon is still drawn');
    });

    test('a button is a Tab stop before the app is there', () {
      const String doc = '<p><strong role="button" title="Analyse" aria-label="Analyse">Analyse</strong></p>\n';
      final String out = dvSsrFirstLayout(
        doc,
        _capture(<Map<String, Object?>>[
          _width(390, <Map<String, Object?>>[
            _text('Analyse', <num>[30, 110, 80, 24], z: 3),
          ], controls: <Map<String, Object?>>[
            <String, Object?>{'k': 'b', 'name': 'Analyse', 'r': <num>[20, 100, 100, 44]},
          ]),
        ]),
      );
      expect(RegExp(r'<strong [^>]*tabindex="0"').hasMatch(out), isTrue, reason: out);
    });

    test('a password field is never given a value', () {
      const String doc = '<p><label for="dv-field-1">Password</label> '
          '<input id="dv-field-1" type="password" name="Password" data-dv-field="Password"></p>\n';
      final String out = dvSsrFirstLayout(
        doc,
        _capture(<Map<String, Object?>>[
          _width(390, <Map<String, Object?>>[
            <String, Object?>{..._text('secret', <num>[36, 113, 318, 24], z: 4), 'k': 'e'},
          ], controls: <Map<String, Object?>>[
            <String, Object?>{'k': 'f', 'name': 'Password', 'r': <num>[20, 100, 350, 50]},
          ]),
        ]),
      );
      expect(out, isNot(contains('secret')));
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

    test('a fallback family the app does not bundle is not named: the app cannot draw with it', () {
      // Flutter on the web draws only with the fonts the app bundles (and its
      // own fallbacks), never the visitor's system fonts. The capture's
      // theme still lists the capture host's platform fallbacks (Material's
      // Linux list on a Linux build box); named in the stylesheet, each one
      // missing cost the browser a font lookup before the first paint, and
      // one present drew in a font the app never shows.
      final String out = dvSsrFirstLayout(
        _doc,
        _capture(<Map<String, Object?>>[
          _width(390, <Map<String, Object?>>[
            _text('Ship faster', <num>[20, 100, 350, 40], runs: <Map<String, Object?>>[
              <String, Object?>{
                't': 'Ship faster',
                'f': 'Inter',
                'fs': 16,
                'fw': 700,
                'c': '#111111',
                'ff': <String>['Ubuntu', 'Adwaita Sans', 'NotoEmoji', 'Cantarell'],
              },
            ]),
          ]),
        ]),
        fonts: <String, List<DVLayoutFont>>{
          'Inter': <DVLayoutFont>[const DVLayoutFont('assets/fonts/inter.abc.woff2')],
          'NotoEmoji': <DVLayoutFont>[const DVLayoutFont('assets/fonts/emoji.abc.woff2')],
        },
      );
      expect(out, contains('font:700 16px/24px "Inter","NotoEmoji",sans-serif'), reason: out);
      for (final String missing in <String>['Ubuntu', 'Adwaita Sans', 'Cantarell']) {
        expect(out, isNot(contains(missing)));
      }
      expect(out, contains('@font-face{font-family:"NotoEmoji"'));
    });

    test('the end of the first screen is marked, before the stylesheet for below the fold', () {
      // The head holds the first paint until this element is parsed
      // (dvSsrFirstHead), so the first frame is the first screen in place:
      // never the bare canvas, never half of it.
      final String out = dvSsrFirstLayout(
        _doc,
        _capture(<Map<String, Object?>>[
          _width(390, <Map<String, Object?>>[
            _text('Ship faster', <num>[20, 100, 350, 40]),
            _text('See pricing', <num>[20, 5000, 100, 20]),
          ]),
        ]),
      );
      const String marker = '<i id="$dvFirstScreenId" aria-hidden="true" hidden></i>';
      expect(marker.allMatches(out), hasLength(1), reason: out);
      final List<RegExpMatch> styles =
          RegExp(r'<style class="dvl-style">(.*?)</style>', dotAll: true).allMatches(out).toList();
      expect(out.indexOf(marker), greaterThan(out.indexOf('See pricing')));
      expect(out.indexOf(marker), lessThan(out.indexOf(styles.last.group(0)!)));
      // Find skips it like the rest of the layout's own pieces.
      expect(dvFindableHtml(out), contains(marker));
      expect(dvFindableHtml(out), isNot(contains('<section hidden="until-found" data-dv-anchor="3"><i id')));
    });

    test('everything above the fold: the marker still ends the document', () {
      final String out = dvSsrFirstLayout(
        _doc,
        _capture(<Map<String, Object?>>[
          _width(390, <Map<String, Object?>>[_text('Ship faster', <num>[20, 100, 350, 40])]),
        ]),
      );
      expect(out, endsWith('<i id="$dvFirstScreenId" aria-hidden="true" hidden></i></div>'));
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

    test('what is not paired at the second height still counts in the scroll height', () {
      // The footer at 3000 is not found at the taller screen (a lazy list
      // built differently): the scroll height must not shrink with the screen.
      final Map<String, Object?> width = _width(390, <Map<String, Object?>>[
        _text('Ship faster', <num>[20, 100, 350, 40]),
        <String, Object?>{'k': 'b', 'r': <num>[0, 2900, 390, 100], 'z': 2, 's': true, 'bg': '#222222'},
      ])
        ..['tall'] = <String, Object?>{
          'height': 1000,
          'items': <Map<String, Object?>>[_text('Ship faster', <num>[20, 100, 350, 40])],
          'controls': <Object?>[],
        };
      final String out = dvSsrFirstLayout(_doc, _capture(<Map<String, Object?>>[width]));
      expect(out, contains('.dvl{height:3000px}'));
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
      expect(out, matches(RegExp(r'\.dvl \.dvu:focus-within[,{][^}]*clip-path:none')));
      // A link whose own text is kept only for readers shows itself too.
      expect(out, matches(RegExp(r'<a [^>]*class="dvf"[^>]*href="/pricing"|<a [^>]*href="/pricing"[^>]*class="dvf"')));
      expect(out, matches(RegExp(r'\.dvl \.dvf:focus[,{][^}]*clip-path:none')));
    });

    test('a placed link with nothing but a picture in it keeps its place when focused', () {
      final String out = dvSsrFirstLayout(
        '<a href="/" aria-label="Home"><img src="logo.png" alt=""></a>\n',
        _capture(<Map<String, Object?>>[
          _width(390, <Map<String, Object?>>[
            <String, Object?>{'k': 'i', 'r': <num>[20, 16, 80, 40], 'z': 1, 's': false, 'src': 'logo.png', 'fit': 'contain'},
          ], controls: <Map<String, Object?>>[
            <String, Object?>{'k': 'a', 'href': '/', 'name': 'Home', 'r': <num>[20, 16, 80, 40]},
          ]),
        ]),
      );
      expect(out, isNot(contains('class="dvf"')));
    });

    // A sentence with links in it (DVWidgetSpan) is one <p> with its links
    // inline. The app paints its words as one paragraph with a gap for each
    // link (placeholders, not in the paragraph's text) and each link's words
    // as a paragraph of their own in that gap. Each piece was placed on its
    // own: the paragraph's words drawn by the layer, the document's words
    // hidden, and the links at their boxes on top, so the page showed "Our ,
    // and explain" with the links floating over it, and find and a selection
    // stopped at every link (sigmadev.digital/about, Dartvel 3.47.8).
    const String sentence = '<p>Questions, or a project in mind? '
        '<a href="/contact" title="Get a free quote" aria-label="Get a free quote">Get a free quote</a>. Our '
        '<a href="/privacy" title="privacy policy" aria-label="privacy policy">privacy policy</a> '
        'explain how we handle your data.</p>\n';
    Map<String, Object?> sentenceWidth(int width, List<num> rect, List<num> quote, List<num> privacy) =>
        _width(width, <Map<String, Object?>>[
          _text('Questions, or a project in mind? . Our  explain how we handle your data.', rect, z: 3, runs:
              <Map<String, Object?>>[
            <String, Object?>{'t': 'Questions, or a project in mind?', 'f': 'Inter', 'fs': 16, 'fw': 400, 'c': '#111111'},
            <String, Object?>{'t': ' ', 'f': 'Inter', 'fs': 16, 'fw': 400, 'c': '#111111'},
            <String, Object?>{'t': '. Our', 'f': 'Inter', 'fs': 16, 'fw': 400, 'c': '#111111'},
            <String, Object?>{'t': ' ', 'f': 'Inter', 'fs': 16, 'fw': 400, 'c': '#111111'},
            <String, Object?>{'t': ' ', 'f': 'Inter', 'fs': 16, 'fw': 400, 'c': '#111111'},
            <String, Object?>{'t': 'explain how we handle your data.', 'f': 'Inter', 'fs': 16, 'fw': 400, 'c': '#111111'},
          ])..['nw'] = false..['lines'] = 2,
          _text('Get a free quote', quote, z: 4, runs: <Map<String, Object?>>[
            <String, Object?>{'t': 'Get a free quote', 'f': 'Inter', 'fs': 16, 'fw': 400, 'c': '#1d4ed8', 'd': 'underline'},
          ]),
          _text('privacy policy', privacy, z: 5, runs: <Map<String, Object?>>[
            <String, Object?>{'t': 'privacy policy', 'f': 'Inter', 'fs': 16, 'fw': 400, 'c': '#1d4ed8', 'd': 'underline'},
          ]),
        ], controls: <Map<String, Object?>>[
          <String, Object?>{'k': 'a', 'href': '/contact', 'name': 'Get a free quote', 'r': quote},
          <String, Object?>{'k': 'a', 'href': '/privacy', 'name': 'privacy policy', 'r': privacy},
        ]);

    test('a sentence with links is one text block, its links inline in it', () {
      final String out = dvSsrFirstLayout(
        sentence,
        _capture(<Map<String, Object?>>[
          sentenceWidth(390, <num>[20, 300, 350, 48], <num>[270, 300, 120, 24], <num>[60, 324, 100, 24]),
        ]),
      );
      // One run holds the whole sentence, words and links, as the document
      // reads it: nothing of it hidden, nothing of it drawn by the layer.
      final RegExpMatch block = RegExp(r'<p><span id="(dvr\d+)">(.*?)</span></p>', dotAll: true).firstMatch(out)!;
      final String id = block.group(1)!;
      final String inside = block.group(2)!;
      expect(_visibleText(inside), 'Questions, or a project in mind? Get a free quote. Our privacy policy explain how we handle your data.');
      expect(inside, isNot(contains('dvu')));
      expect(out, isNot(contains('content:"Questions')));
      // Placed at the paragraph's box, wrapping as the app wraps it.
      expect(out, contains('#$id{left:20px;top:300px;width:350px;height:48px'));
      expect(out, matches(RegExp('#$id[,{][^}]*white-space:pre-wrap')));
      // Each link flows in the line, styled in place: no box of its own.
      final List<RegExpMatch> links = RegExp(r'<a id="(dva\d+)" href="[^"]+"[^>]*><span id="(dvr\d+)">').allMatches(inside).toList();
      expect(links, hasLength(2));
      for (final RegExpMatch link in links) {
        expect(out, isNot(matches(RegExp('#${link.group(1)}\\{left:'))));
        expect(out, isNot(matches(RegExp('#${link.group(2)}\\{left:'))));
        expect(out, isNot(matches(RegExp('#${link.group(1)}\\{[^}]*position:absolute'))));
        expect(out, matches(RegExp('#${link.group(2)}[,{][^}]*text-decoration:underline')));
        expect(out, matches(RegExp('#${link.group(2)}[,{][^}]*color:#1d4ed8')));
      }
    });

    test('a sentence the app does not paint as one keeps its pieces as before', () {
      // Nothing painted matches the sentence's words: its text and links are
      // matched one by one, as any other.
      final String out = dvSsrFirstLayout(
        sentence,
        _capture(<Map<String, Object?>>[
          _width(390, <Map<String, Object?>>[
            _text('Get a free quote', <num>[40, 300, 120, 24], z: 5),
          ], controls: <Map<String, Object?>>[
            <String, Object?>{'k': 'a', 'href': '/contact', 'name': 'Get a free quote', 'r': <num>[40, 300, 120, 24]},
          ]),
        ]),
      );
      expect(out, isNot(contains('<p><span id="dvr')));
      expect(out, matches(RegExp(r'#dva\d+\{left:40px;top:300px')));
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
