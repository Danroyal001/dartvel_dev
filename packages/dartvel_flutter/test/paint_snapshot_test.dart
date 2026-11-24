// The paint snapshot the build reads to lay the SSR-first document out the
// way the app's first frame draws the page.
//
// The capture runs the app in Chrome and asks it, through the capture hook,
// what it painted: every paragraph with its box and each run's style, every
// filled box, every image with its source, and whether each scrolls with the
// page or is pinned like an app bar. The build turns that into the CSS that
// places the server-rendered document's own text where the app draws it.
import 'dart:convert';

import 'package:dartvel_flutter/src/seo/paint_snapshot.dart';
import 'package:dartvel_flutter/src/widgets/described_paint.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<Map<String, Object?>> _items(Map<String, Object?> snapshot) =>
    (snapshot['items']! as List<Object?>).cast<Map<String, Object?>>();

Map<String, Object?> _text(Map<String, Object?> snapshot, String text) =>
    _items(snapshot).firstWhere(
        (Map<String, Object?> item) => item['k'] == 't' && item['text'] == text);

List<double> _rect(Map<String, Object?> item) =>
    (item['r']! as List<Object?>).cast<num>().map((num v) => v.toDouble()).toList();

void main() {
  idleTests();
  setUp(() {
    final TestWidgetsFlutterBinding binding =
        TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first
      ..physicalSize = const Size(400, 800)
      ..devicePixelRatio = 1;
  });
  tearDown(() =>
      TestWidgetsFlutterBinding.instance.platformDispatcher.views.first
        ..resetPhysicalSize()
        ..resetDevicePixelRatio());

  testWidgets('reports the viewport and survives JSON', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    final Map<String, Object?> snapshot = dvPaintSnapshot();
    expect(snapshot['width'], 400);
    expect(snapshot['height'], 800);
    expect(snapshot['brightness'], 'light');
    expect(jsonDecode(jsonEncode(snapshot)), isA<Map<String, Object?>>());
  });

  testWidgets('a paragraph: its box, alignment, lines and each run\'s style',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFFFAFAFA),
        body: Padding(
          padding: const EdgeInsets.only(left: 20, top: 30),
          child: SizedBox(
            width: 300,
            child: Text.rich(
              const TextSpan(
                text: 'Hello ',
                children: <InlineSpan>[
                  TextSpan(
                      text: 'world',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFFF0000),
                          decoration: TextDecoration.underline)),
                ],
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 18,
                  height: 1.5,
                  letterSpacing: 0.5,
                  color: Color(0xFF112233)),
            ),
          ),
        ),
      ),
    ));
    final Map<String, Object?> item = _text(dvPaintSnapshot(), 'Hello world');
    final List<double> rect = _rect(item);
    expect(rect[0], 20);
    expect(rect[1], 30);
    expect(rect[2], 300);
    expect(item['al'], 'center');
    expect(item['lines'], 1);
    expect(item['lh'], closeTo(27, 0.01));
    expect(item['s'], isFalse, reason: 'not inside a scroller: pinned');
    final List<Map<String, Object?>> runs =
        (item['runs']! as List<Object?>).cast<Map<String, Object?>>();
    expect(runs, hasLength(2));
    expect(runs[0]['t'], 'Hello ');
    expect(runs[0]['f'], 'Inter');
    expect(runs[0]['fs'], 18);
    expect(runs[0]['fw'], 400);
    expect(runs[0]['c'], '#112233');
    expect(runs[0]['ls'], 0.5);
    expect(runs[1]['t'], 'world');
    expect(runs[1]['fw'], 700);
    expect(runs[1]['c'], '#ff0000');
    expect(runs[1]['d'], 'underline');
  });

  testWidgets('boxes: colour, radii, border and shadow, in paint order',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFFFFFFFF),
        body: Align(
          alignment: Alignment.topLeft,
          child: Container(
            margin: const EdgeInsets.all(10),
            width: 100,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0x80336699),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF000000), width: 2),
              boxShadow: const <BoxShadow>[
                BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 4)),
              ],
            ),
            child: const ColoredBox(color: Color(0xFF00FF00)),
          ),
        ),
      ),
    ));
    final List<Map<String, Object?>> boxes = _items(dvPaintSnapshot())
        .where((Map<String, Object?> item) => item['k'] == 'b')
        .toList();
    final Map<String, Object?> page =
        boxes.firstWhere((Map<String, Object?> b) => b['bg'] == '#ffffff');
    expect(_rect(page), <double>[0, 0, 400, 800]);
    final Map<String, Object?> card = boxes
        .firstWhere((Map<String, Object?> b) => b['bg'] == 'rgba(51,102,153,0.502)');
    expect(_rect(card), <double>[10, 10, 100, 50]);
    expect(card['rad'], <double>[12, 12, 12, 12]);
    expect(card['bd'], <Object?>[2, '#000000']);
    expect(card['sh'], '0px 4px 8px 0px rgba(0,0,0,0.2)');
    final Map<String, Object?> inner =
        boxes.firstWhere((Map<String, Object?> b) => b['bg'] == '#00ff00');
    expect((inner['z']! as int) > (card['z']! as int), isTrue);
    expect((card['z']! as int) > (page['z']! as int), isTrue);
  });

  testWidgets('an image: its source, box and fit', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: Image(
          image: ResizeImage(const NetworkImage('https://example.com/a.png'), width: 64),
          width: 64,
          height: 32,
          fit: BoxFit.cover,
        ),
      ),
    ));
    final Map<String, Object?> image = _items(dvPaintSnapshot())
        .firstWhere((Map<String, Object?> item) => item['k'] == 'i');
    expect(image['src'], 'https://example.com/a.png');
    expect(_rect(image), <double>[0, 0, 64, 32]);
    expect(image['fit'], 'cover');
  });

  testWidgets('an asset image is served from assets/', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: Image(image: AssetImage('assets/logo.png'), width: 10, height: 10),
      ),
    ));
    // The test has no such file; the snapshot reads the widget, not the bytes.
    tester.takeException();
    final Map<String, Object?> image = _items(dvPaintSnapshot())
        .firstWhere((Map<String, Object?> item) => item['k'] == 'i');
    expect(image['src'], 'assets/assets/logo.png');
  });

  testWidgets('the page scroller: below the fold is kept, and scrolls',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Bar')),
        body: ListView(
          children: <Widget>[
            for (int index = 0; index < 30; index++)
              SizedBox(height: 100, child: Text('Row $index')),
          ],
        ),
      ),
    ));
    final Map<String, Object?> snapshot = dvPaintSnapshot();
    expect(_text(snapshot, 'Bar')['s'], isFalse);
    expect(_text(snapshot, 'Row 0')['s'], isTrue);
    // ListView builds a little past the screen; what it built is reported
    // even though the viewport clips it.
    final Map<String, Object?> below = _text(snapshot, 'Row 8');
    expect(_rect(below)[1], greaterThan(800));
  });

  testWidgets('a SingleChildScrollView page is the page scroller too',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SingleChildScrollView(
        child: Column(
          children: <Widget>[
            for (int index = 0; index < 20; index++)
              SizedBox(height: 100, child: Text('Block $index')),
          ],
        ),
      ),
    ));
    final Map<String, Object?> snapshot = dvPaintSnapshot();
    expect(_text(snapshot, 'Block 0')['s'], isTrue);
    expect(_text(snapshot, 'Block 15')['s'], isTrue);
  });

  testWidgets('a page scroll view inside the page shell\'s own scroller is the page too',
      (WidgetTester tester) async {
    // The shell (DVPageViewport) is a scroller the size of the screen that does
    // not scroll when the page has its own scroll view; the page\'s is the one
    // whose content runs below the fold.
    await tester.pumpWidget(MaterialApp(
      home: SingleChildScrollView(
        child: SizedBox(
          height: 800,
          child: SingleChildScrollView(
            child: Column(
              children: <Widget>[
                for (int index = 0; index < 20; index++)
                  SizedBox(height: 100, child: Text('Section $index')),
              ],
            ),
          ),
        ),
      ),
    ));
    final Map<String, Object?> snapshot = dvPaintSnapshot();
    expect(_text(snapshot, 'Section 15')['s'], isTrue);
    expect(_rect(_text(snapshot, 'Section 15'))[1], 1500);
  });

  testWidgets('a horizontal SingleChildScrollView clips what is off to the side',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            for (int index = 0; index < 10; index++)
              SizedBox(width: 150, height: 40, child: Text('Tile $index')),
          ],
        ),
      ),
    ));
    final Iterable<Object?> texts = _items(dvPaintSnapshot())
        .where((Map<String, Object?> item) => item['k'] == 't')
        .map((Map<String, Object?> item) => item['text']);
    expect(texts, contains('Tile 0'));
    expect(texts, isNot(contains('Tile 5')));
  });

  testWidgets('a horizontal scroller clips what is off to the side',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 50,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: <Widget>[
              for (int index = 0; index < 10; index++)
                SizedBox(width: 150, child: Text('Card $index')),
            ],
          ),
        ),
      ),
    ));
    final Map<String, Object?> snapshot = dvPaintSnapshot();
    final Iterable<Object?> texts = _items(snapshot)
        .where((Map<String, Object?> item) => item['k'] == 't')
        .map((Map<String, Object?> item) => item['text']);
    expect(texts, contains('Card 0'));
    expect(texts, isNot(contains('Card 4')), reason: 'built in the cache extent, off screen');
  });

  testWidgets('what is invisible is not reported', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Column(
        children: <Widget>[
          Opacity(opacity: 0, child: Text('Faded')),
          Offstage(child: Text('Offstage')),
          Opacity(opacity: 0.5, child: Text('Half')),
        ],
      ),
    ));
    final Map<String, Object?> snapshot = dvPaintSnapshot();
    final Iterable<Object?> texts = _items(snapshot)
        .where((Map<String, Object?> item) => item['k'] == 't')
        .map((Map<String, Object?> item) => item['text']);
    expect(texts, isNot(contains('Faded')));
    expect(texts, isNot(contains('Offstage')));
    expect(_text(snapshot, 'Half')['op'], 0.5);
  });

  testWidgets('a Material surface reports its resolved colour and shape',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 120,
          height: 40,
          child: Material(
            color: const Color(0xFF123456),
            shape: const StadiumBorder(),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    ));
    final Map<String, Object?> pill = _items(dvPaintSnapshot()).firstWhere(
        (Map<String, Object?> item) => item['k'] == 'b' && item['bg'] == '#123456');
    expect(pill['rad'], <double>[20, 20, 20, 20]);
  });

  // -- Paint the capture cannot read from a painter or a shader, described.

  testWidgets('a described painter: its gradients, top first, as CSS layers',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 400,
          height: 200,
          child: CustomPaint(
            painter: DVGradientPainter(<Gradient>[
              DVRadialGradient(
                center: Alignment(0.7, -1),
                radiusX: 0.6,
                radiusY: 0.8,
                colors: <Color>[Color.fromRGBO(163, 163, 163, 0.28), Color.fromRGBO(163, 163, 163, 0)],
                stops: <double>[0, 0.6],
              ),
              DVRadialGradient(
                center: Alignment.bottomLeft,
                radiusX: 0.5,
                radiusY: 0.7,
                colors: <Color>[Color.fromRGBO(212, 212, 212, 0.14), Color.fromRGBO(212, 212, 212, 0)],
                stops: <double>[0, 0.6],
              ),
            ]),
          ),
        ),
      ),
    ));
    final Map<String, Object?> glow = _items(dvPaintSnapshot())
        .firstWhere((Map<String, Object?> item) => item['k'] == 'b' && item['g'] != null);
    expect(_rect(glow), <double>[0, 0, 400, 200]);
    // CSS paints the first layer on top: the painter's last gradient first.
    expect(
      glow['g'],
      'radial-gradient(50% 70% at 0% 100%,rgba(212,212,212,0.141) 0%,rgba(212,212,212,0) 60%),'
      'radial-gradient(60% 80% at 85% 0%,rgba(163,163,163,0.278) 0%,rgba(163,163,163,0) 60%)',
    );
  });

  testWidgets('a painter that describes nothing paints no box', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: 100, height: 100, child: CustomPaint(painter: _Opaque())),
      ),
    ));
    expect(_items(dvPaintSnapshot()).where((Map<String, Object?> item) => item['k'] == 'b'), isEmpty);
  });

  testWidgets('a radial gradient keeps its radius; a linear one its angle on the box',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          SizedBox(
            width: 200,
            height: 100,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 0.5,
                  colors: <Color>[Color(0xFFFF0000), Color(0xFF0000FF)],
                ),
              ),
            ),
          ),
          SizedBox(
            width: 200,
            height: 100,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[Color(0xFF000000), Color(0xFFFFFFFF)],
                ),
              ),
            ),
          ),
        ]),
      ),
    ));
    final List<Map<String, Object?>> boxes = _items(dvPaintSnapshot())
        .where((Map<String, Object?> item) => item['g'] != null)
        .toList();
    // Half the shorter side: a 50 px circle.
    expect(boxes[0]['g'], 'radial-gradient(circle 50px at 50% 50%,#ff0000 0%,#0000ff 100%)');
    // Corner to corner of a 200 x 100 box: the direction is atan2(200, 100),
    // 63.43 degrees, and CSS's line for it is exactly the corner-to-corner
    // projection, so the stops stay at 0 and 100.
    expect(boxes[1]['g'], 'linear-gradient(116.57deg,#000000 0%,#ffffff 100%)');
  });

  testWidgets('a gradient run of text: its gradient on its run, CSS-angled',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 300,
          child: DVGradientText(
            TextSpan(text: 'We build it, ', children: <InlineSpan>[
              DVGradientSpan(
                text: 'and keep it running.',
                gradient: LinearGradient(
                  begin: Alignment(-0.866, -0.5),
                  end: Alignment(0.866, 0.5),
                  colors: <Color>[Color(0xFFFFFFFF), Color(0xFFD4D4D4), Color(0xFFA3A3A3)],
                  stops: <double>[0, 0.55, 1],
                ),
              ),
            ]),
            style: TextStyle(fontSize: 20, color: Color(0xFFFFFFFF)),
          ),
        ),
      ),
    ));
    final Map<String, Object?> paragraph =
        _text(dvPaintSnapshot(), 'We build it, and keep it running.');
    final List<Map<String, Object?>> runs =
        (paragraph['runs']! as List<Object?>).cast<Map<String, Object?>>();
    expect(runs[0].containsKey('g'), isFalse);
    expect(runs[1]['t'], 'and keep it running.');
    expect(runs[1]['g'], 'linear-gradient(120deg,#ffffff 0%,#d4d4d4 55%,#a3a3a3 100%)');
    expect(find.byType(ShaderMask), findsOneWidget);
  });

  testWidgets('a text field\'s outline border is a box at the field', (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 240,
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Email',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF888888), width: 1.5),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF777777), width: 1.5),
                ),
                filled: true,
                fillColor: const Color(0xFFF4F4F4),
              ),
            ),
          ),
        ),
      ),
    ));
    final Rect field = tester.getRect(find.byType(InputDecorator));
    final Map<String, Object?> border = _items(dvPaintSnapshot())
        .firstWhere((Map<String, Object?> item) => item['k'] == 'b' && item['bd'] != null);
    expect(_rect(border), <double>[field.left, field.top, field.width, field.height]);
    expect(border['bd'], <Object?>[1.5, '#777777']);
    expect(border['rad'], <double>[10, 10, 10, 10]);
    expect(border['bg'], '#f4f4f4');
  });

  testWidgets('a multi-line field\'s border is round the whole field, not its scroller',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: 300,
              child: TextField(
                minLines: 6,
                maxLines: null,
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: Color(0xFFE5E5E5)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    final Rect field = tester.getRect(find.byType(InputDecorator));
    final List<Map<String, Object?>> borders = _items(dvPaintSnapshot())
        .where((Map<String, Object?> item) => item['k'] == 'b' && item['bd'] != null)
        .toList();
    expect(borders, hasLength(1));
    expect(_rect(borders.single), <double>[field.left, field.top, field.width, field.height]);
    // On the desktop and the web a multi-line field draws a scrollbar with a
    // painter of its own, inside the border.
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('a default text field: Material 3\'s underline, in the theme\'s colour',
      (WidgetTester tester) async {
    final ThemeData theme = ThemeData(colorSchemeSeed: const Color(0xFF225588));
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: const Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: 240, child: TextField(decoration: InputDecoration(hintText: 'Name'))),
        ),
      ),
    ));
    final Map<String, Object?> border = _items(dvPaintSnapshot())
        .firstWhere((Map<String, Object?> item) => item['k'] == 'b' && item['bd'] != null);
    final List<Object?> value = border['bd']! as List<Object?>;
    expect(value[1], dvCssColor(theme.colorScheme.outline));
    expect(value[2], <double>[0, 0, 1, 0]);
  });
}

/// A painter that draws something it does not describe.
class _Opaque extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) =>
      canvas.drawCircle(size.center(Offset.zero), 10, Paint()..color = const Color(0xFFFF0000));

  @override
  bool shouldRepaint(_Opaque oldDelegate) => false;
}

void idleTests() {
  testWidgets('idle: nothing left to draw once the page is at rest', (WidgetTester tester) async {
    final AnimationController controller = AnimationController(
        vsync: const TestVSync(), duration: const Duration(milliseconds: 300));
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(home: FadeTransition(opacity: controller, child: const Text('Fading'))));
    controller.forward();
    await tester.pump(const Duration(milliseconds: 50));
    expect(dvPaintIdle(), isFalse, reason: 'mid animation');
    await tester.pumpAndSettle();
    expect(dvPaintIdle(), isTrue);
  });
}
