// Studio's canvas draws a page exactly as the application does.
//
// The owner opened /docs/accessibility in Studio and found a page that
// looked nothing like the site: the canvas drew a document rebuilt from the
// page's semantics, in Studio's own theme, on a white card, with no header.
// Studio is a route of the application, so it has the application's own page
// views -- the functions its router builds each page with -- and its themes.
// A compiled page is drawn by its view; a document being edited is drawn
// inside the view's layouts and shell, in the application's theme, at the
// device's width and height, laid out as the live route lays it out. The
// proof is the pixels: the artboard and the live route, rendered at the same
// size, are the same image.
//
// And the canvas gets the screen: the header, the formula bar and a banner
// stacked above it took a quarter of a laptop's height before a pixel of the
// page was drawn.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dartvel_flutter/src/studio/studio_formula_bar.dart';
import 'package:flutter_test/flutter_test.dart';

final ThemeData _light = ThemeData(
  useMaterial3: true,
  scaffoldBackgroundColor: const Color(0xFFF4EFE6),
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8A3B12)),
);
final ThemeData _dark = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: const Color(0xFF0B0F17),
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF8A3B12),
    brightness: Brightness.dark,
  ),
);

final DVStudioAppLook _look = DVStudioAppLook(
  theme: _light,
  darkTheme: _dark,
  themeMode: ThemeMode.light,
);

/// The site's chrome: a header in the theme's primary colour over the page.
class _SiteLayout extends StatelessWidget {
  const _SiteLayout({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            height: 56,
            color: Theme.of(context).colorScheme.primary,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Site header',
              style: TextStyle(color: Theme.of(context).colorScheme.onPrimary),
            ),
          ),
          Expanded(child: child),
        ],
      );
}

/// The compiled page at /about.
class _About extends StatelessWidget {
  const _About();

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          Semantics(headingLevel: 1, child: const Text('About the roastery')),
          const Text('We roast on Tuesdays.'),
        ],
      );
}

/// The application's page views, as the generator writes them.
Widget? _view(String path, {Widget? content, bool layout = true}) {
  final Widget? body = content ?? (path == '/about' ? const _About() : null);
  if (body == null) return null;
  // As the generated view is: the page's own lifecycle host around the
  // body, the layouts around that.
  final Widget hosted = DVPageLifecycleHost(child: body);
  return DVPageShell(
    spec: const DVPageScaffoldSpec(),
    child: layout ? _SiteLayout(child: hosted) : hosted,
  );
}

/// A page made in Studio.
DVPageDocument _landing() => DVPageDocument(
      route: '/landing',
      title: 'Landing',
      root: DVPageNode(
        type: 'box',
        properties: <String, Object?>{'padding': 32, 'spacing': 16},
        children: <DVPageNode>[
          DVPageNode(
            type: 'text',
            properties: <String, Object?>{
              'text': 'Fresh every Tuesday',
              'fontSize': 32,
              'fontWeight': 'bold',
            },
          ),
          DVPageNode(
            type: 'box',
            properties: <String, Object?>{
              'padding': 20,
              'backgroundColor': '#FFE7C2',
              'rounded': 12,
            },
            children: <DVPageNode>[
              DVPageNode(
                type: 'text',
                properties: <String, Object?>{'text': 'Beans from Kaduna'},
              ),
            ],
          ),
          DVPageNode(
            type: 'button',
            properties: <String, Object?>{
              'text': 'Order',
              ...dvStudioButtonDefaults,
            },
          ),
        ],
      ),
    );

const List<DVStudioSitePage> _pages = <DVStudioSitePage>[
  DVStudioSitePage(
    path: '/about',
    kind: DVStudioPageKind.code,
    source: 'lib/pages/about.dart:3',
  ),
];

Widget _studio({DVStudioAppLook? look}) => MaterialApp(
      home: Material(
        child: DVStudioScreen(
          site: DVStudioSiteSource(
            pages: () async => _pages,
            view: _view,
            look: look ?? _look,
          ),
        ),
      ),
    );

Finder _key(String key) => find.byKey(ValueKey<String>(key));

void _screen(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Future<Uint8List> _pixels(WidgetTester tester, Finder boundary) async {
  final Uint8List? bytes = await tester.runAsync(() async {
    final ui.Image image = await captureImage(tester.element(boundary));
    final ByteData? data =
        await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  return bytes!;
}

/// How many pixels of [a] and [b] differ, as a fraction of all of them.
double _difference(Uint8List a, Uint8List b) {
  expect(a.length, b.length, reason: 'the two images are not the same size');
  int differing = 0;
  for (int i = 0; i < a.length; i += 4) {
    if (a[i] != b[i] ||
        a[i + 1] != b[i + 1] ||
        a[i + 2] != b[i + 2] ||
        a[i + 3] != b[i + 3]) {
      differing++;
    }
  }
  return differing / (a.length / 4);
}

void main() {
  late SqliteDVDatabaseAdapter database;

  setUp(() async {
    database = SqliteDVDatabaseAdapter.memory();
    DV.Database.configure(database);
    DVPageStore.resetCache();
  });

  tearDown(() {
    database.close();
    DVPageStore.resetCache();
  });

  testWidgets(
      'a compiled page is drawn by the application\'s own view of it, in '
      'the application\'s theme, header and all', (WidgetTester tester) async {
    _screen(tester, const Size(1600, 1000));
    await tester.pumpWidget(_studio());
    await tester.pumpAndSettle();

    await tester.tap(_key('dv-studio-route-/about'));
    await tester.pumpAndSettle();

    expect(find.text('Site header'), findsOneWidget);
    expect(find.text('We roast on Tuesdays.'), findsOneWidget);
    final BuildContext inPage = tester.element(find.text('We roast on Tuesdays.'));
    expect(Theme.of(inPage).scaffoldBackgroundColor, _light.scaffoldBackgroundColor);
    expect(Theme.of(inPage).colorScheme.primary, _light.colorScheme.primary);
  });

  testWidgets('editing a page written in code copies the page, not the site '
      'around it', (WidgetTester tester) async {
    _screen(tester, const Size(1600, 1000));
    await tester.pumpWidget(_studio());
    await tester.pumpAndSettle();
    await tester.tap(_key('dv-studio-route-/about'));
    await tester.pumpAndSettle();
    await tester.tap(_key('dv-studio-override'));
    await tester.pumpAndSettle();
    await tester.tap(_key('dv-studio-publish'));
    await tester.pumpAndSettle();
    final DVPageDocument? copy = await const DVPageStore().load('/about');
    final List<String> texts = <String>[];
    void walk(DVPageNode node) {
      if (node.properties['text'] case final String text) texts.add(text);
      node.children.forEach(walk);
    }

    walk(copy!.root);
    expect(texts, contains('We roast on Tuesdays.'));
    expect(texts, isNot(contains('Site header')),
        reason: 'the header is the layout\'s, drawn around the copy');
  });

  testWidgets('the page is drawn in the application\'s dark theme on request, '
      'and without its layout on request', (WidgetTester tester) async {
    _screen(tester, const Size(1600, 1000));
    await tester.pumpWidget(_studio());
    await tester.pumpAndSettle();
    await tester.tap(_key('dv-studio-route-/about'));
    await tester.pumpAndSettle();

    await tester.tap(_key('dv-studio-appearance'));
    await tester.pumpAndSettle();
    final BuildContext inPage = tester.element(find.text('We roast on Tuesdays.'));
    expect(Theme.of(inPage).brightness, Brightness.dark);
    expect(Theme.of(inPage).scaffoldBackgroundColor, _dark.scaffoldBackgroundColor);

    await tester.tap(_key('dv-studio-show-layout'));
    await tester.pumpAndSettle();
    expect(find.text('Site header'), findsNothing);
    expect(find.text('We roast on Tuesdays.'), findsOneWidget);
  });

  testWidgets(
      'a page being edited is the live route, pixel for pixel, at the '
      'device\'s size', (WidgetTester tester) async {
    await const DVPageStore().save(_landing());

    // The live route, as the router draws a page made in Studio: the
    // stored document in the page's frame, in the application's theme, in a
    // desktop window.
    _screen(tester, const Size(1280, 800));
    await tester.pumpWidget(MaterialApp(
      theme: _light,
      debugShowCheckedModeBanner: false,
      home: RepaintBoundary(
        key: const ValueKey<String>('live'),
        child: DVStudioPageRoute(
          '/landing',
          frame: (Widget document) => _view('/landing', content: document)!,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Fresh every Tuesday'), findsOneWidget);
    final Uint8List live = await _pixels(tester, _key('live'));

    // The same page open in Studio, at 100%, nothing selected.
    await tester.pumpWidget(const SizedBox.shrink());
    _screen(tester, const Size(2000, 1200));
    await tester.pumpWidget(_studio());
    await tester.pumpAndSettle();
    await tester.tap(_key('dv-studio-route-/landing'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('100%'));
    await tester.pumpAndSettle();
    expect(find.text('Site header'), findsOneWidget,
        reason: 'the page is edited inside its layout');
    expect(tester.getSize(_key('dv-studio-artboard')), const Size(1280, 800));
    final Uint8List canvas = await _pixels(tester, _key('dv-studio-artboard'));

    expect(_difference(live, canvas), 0);
  });

  testWidgets('selecting an element outlines it without moving anything',
      (WidgetTester tester) async {
    await const DVPageStore().save(_landing());
    _screen(tester, const Size(2000, 1200));
    await tester.pumpWidget(_studio());
    await tester.pumpAndSettle();
    await tester.tap(_key('dv-studio-route-/landing'));
    await tester.pumpAndSettle();

    Map<String, Rect> where() => <String, Rect>{
          for (final String text in <String>[
            'Fresh every Tuesday',
            'Beans from Kaduna',
            'Order',
            'Site header',
          ])
            text: tester.getRect(find.descendant(
                of: _key('dv-studio-artboard'), matching: find.text(text))),
        };
    final Map<String, Rect> before = where();
    await tester.tap(find.descendant(
        of: _key('dv-studio-artboard'),
        matching: find.text('Beans from Kaduna')));
    await tester.pumpAndSettle();
    expect(where(), before);
  });

  testWidgets(
      'at 1280×720 the canvas has most of the screen below the toolbar, '
      'for a page written in code and for a page being edited',
      (WidgetTester tester) async {
    await const DVPageStore().save(_landing());
    _screen(tester, const Size(1280, 720));
    await tester.pumpWidget(_studio());
    await tester.pumpAndSettle();

    await tester.tap(_key('dv-studio-route-/about'));
    await tester.pumpAndSettle();
    // What the page is stays on screen, as one line of the toolbar.
    expect(find.text('Written in code'), findsOneWidget);
    expect(tester.getSize(_key('dv-studio-page-area')).height,
        greaterThanOrEqualTo(720 * 0.9));

    await tester.tap(_key('dv-studio-route-/landing'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: _key('dv-studio-artboard'),
        matching: find.text('Beans from Kaduna')));
    await tester.pumpAndSettle();
    // The formula bar is there for the selection, and still the page has
    // most of the height.
    expect(find.byType(DVStudioFormulaBar), findsOneWidget);
    expect(tester.getSize(_key('dv-studio-page-area')).height,
        greaterThanOrEqualTo(720 * 0.85));
  });

  testWidgets('a page only being looked at has no formula bar; a page being '
      'edited keeps one, so selecting does not push the page down',
      (WidgetTester tester) async {
    await const DVPageStore().save(_landing());
    _screen(tester, const Size(1440, 900));
    await tester.pumpWidget(_studio());
    await tester.pumpAndSettle();
    await tester.tap(_key('dv-studio-route-/about'));
    await tester.pumpAndSettle();
    expect(find.byType(DVStudioFormulaBar), findsNothing);

    await tester.tap(_key('dv-studio-route-/landing'));
    await tester.pumpAndSettle();
    expect(find.byType(DVStudioFormulaBar), findsOneWidget);
    final Rect artboard = tester.getRect(_key('dv-studio-artboard'));
    await tester.tap(find.descendant(
        of: _key('dv-studio-artboard'),
        matching: find.text('Beans from Kaduna')));
    await tester.pumpAndSettle();
    expect(tester.getRect(_key('dv-studio-artboard')), artboard);
  });

  testWidgets('Ctrl+\\ hides both side panels and gives the canvas their width, '
      'and each panel folds on its own', (WidgetTester tester) async {
    await const DVPageStore().save(_landing());
    _screen(tester, const Size(1440, 900));
    await tester.pumpWidget(_studio());
    await tester.pumpAndSettle();
    await tester.tap(_key('dv-studio-route-/landing'));
    await tester.pumpAndSettle();
    final double open = tester.getSize(_key('dv-studio-page-area')).width;

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.backslash);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    final double hidden = tester.getSize(_key('dv-studio-page-area')).width;
    expect(hidden, 1440 - 76, reason: 'everything but the rail');
    expect(find.byType(DVStudioInspector), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.backslash);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(tester.getSize(_key('dv-studio-page-area')).width, open);

    await tester.tap(_key('dv-studio-toggle-right'));
    await tester.pumpAndSettle();
    expect(find.byType(DVStudioInspector), findsNothing);
    expect(tester.getSize(_key('dv-studio-page-area')).width, greaterThan(open));
    await tester.tap(_key('dv-studio-toggle-left'));
    await tester.pumpAndSettle();
    expect(tester.getSize(_key('dv-studio-page-area')).width, hidden);
  });

  testWidgets("a page on the canvas reads its own address from the router, not "
      "Studio's, so its header lights the link the live page lights",
      (WidgetTester tester) async {
    _screen(tester, const Size(1600, 1000));
    await const DVPageStore().save(_landing());
    Widget? routed(String path, {Widget? content, bool layout = true}) {
      final Widget? page = _view(path, content: content, layout: layout);
      if (page == null) return null;
      return Column(children: <Widget>[
        Builder(
          builder: (BuildContext context) =>
              Text('at ${GoRouterState.of(context).uri.path}'),
        ),
        Expanded(child: page),
      ]);
    }

    final GoRouter router = GoRouter(
      initialLocation: '/__studio',
      routes: <RouteBase>[
        GoRoute(
          path: '/__studio',
          builder: (BuildContext context, GoRouterState state) => Material(
            child: DVStudioScreen(
              site: DVStudioSiteSource(
                pages: () async => _pages,
                view: routed,
                look: _look,
              ),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.tap(_key('dv-studio-route-/about'));
    await tester.pumpAndSettle();
    expect(find.text('at /about'), findsOneWidget);

    await tester.tap(_key('dv-studio-route-/landing'));
    await tester.pumpAndSettle();
    expect(find.text('at /landing'), findsOneWidget);
    expect(router.state.uri.path, '/__studio',
        reason: 'the application stays where it is');
  });

  testWidgets('fitted, the page\'s window fills the canvas from top to bottom',
      (WidgetTester tester) async {
    await const DVPageStore().save(_landing());
    _screen(tester, const Size(1440, 900));
    await tester.pumpWidget(_studio());
    await tester.pumpAndSettle();
    for (final String route in <String>['/about', '/landing']) {
      await tester.tap(_key('dv-studio-route-$route'));
      await tester.pumpAndSettle();
      final Rect area = tester.getRect(_key('dv-studio-page-area'));
      final Rect window = tester.getRect(_key(
          route == '/about' ? 'dv-studio-live-page' : 'dv-studio-artboard'));
      expect(area.bottom - window.bottom, lessThan(80), reason: route);
      expect(window.width, lessThanOrEqualTo(area.width), reason: route);
    }
  });

  group('a page made in Studio on the live site', () {
    testWidgets('is drawn inside the frame it is given', (WidgetTester tester) async {
      await const DVPageStore().save(_landing());
      await tester.pumpWidget(MaterialApp(
        theme: _light,
        home: DVStudioPageRoute(
          '/landing',
          frame: (Widget document) => _view('/landing', content: document)!,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Site header'), findsOneWidget);
      expect(find.text('Fresh every Tuesday'), findsOneWidget);
    });

    testWidgets('an address with nothing at it is not framed as a page',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: _light,
        home: DVStudioPageRoute(
          '/nothing-here',
          frame: (Widget document) => _view('/nothing-here', content: document)!,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Site header'), findsNothing);
      expect(find.byType(DVNotFoundPage), findsOneWidget);
    });

    testWidgets('scrolls when it is taller than the window, rather than '
        'overflowing it', (WidgetTester tester) async {
      _screen(tester, const Size(800, 600));
      final DVPageDocument tall = DVPageDocument(
        route: '/tall',
        root: DVPageNode(
          type: 'box',
          properties: <String, Object?>{'spacing': 8},
          children: <DVPageNode>[
            for (int i = 0; i < 60; i++)
              DVPageNode(
                type: 'text',
                properties: <String, Object?>{'text': 'Line $i'},
              ),
          ],
        ),
      );
      await const DVPageStore().save(tall);
      await tester.pumpWidget(MaterialApp(
        theme: _light,
        home: DVStudioPageRoute(
          '/tall',
          frame: (Widget document) => _view('/tall', content: document)!,
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.dragUntilVisible(
        find.text('Line 59'),
        find.byType(SingleChildScrollView),
        const Offset(0, -300),
      );
      expect(find.text('Line 59'), findsOneWidget);
    });
  });
}
