// Every page, at every size a real device has.
//
// A layout that overflows does it silently in release: Flutter paints the
// yellow-and-black stripes in debug and simply clips in production, so a phone
// visitor sees content cut off with nothing to indicate it. Nothing here had
// ever been rendered narrower than a laptop.
//
// The sizes are the ones people actually hold. The 320 entry is not a device
// anyone still ships; it is the floor, and a layout that survives it survives
// a split-screen tablet and a browser someone has zoomed to 200%.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_site/dartvel_client/dartvel_client.dart';
import 'package:dartvel_site/pages/_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// The page under test, inside a router.
///
/// Not optional: the header's links read the current path from the router to
/// decide which one is lit, so a page pumped bare throws and Flutter renders
/// its error box -- which is 100,000 pixels tall and reads exactly like a
/// catastrophic layout overflow.
Widget routed(Widget page) => MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/',
        routes: <RouteBase>[
          GoRoute(
            path: '/',
            builder: (BuildContext context, GoRouterState state) =>
                Scaffold(body: Layout(child: page)),
          ),
          for (final String path in const <String>[
            '/docs',
            '/features',
            '/cloud',
          ])
            GoRoute(
              path: path,
              builder: (BuildContext context, GoRouterState state) =>
                  Scaffold(body: Layout(child: page)),
            ),
        ],
      ),
    );

const List<(String, Size)> _devices = <(String, Size)>[
  ('a narrow floor', Size(320, 640)),
  ('iPhone SE', Size(375, 667)),
  ('iPhone 14', Size(390, 844)),
  ('Pixel 7', Size(412, 915)),
  ('iPad portrait', Size(820, 1180)),
  ('iPad landscape', Size(1180, 820)),
  ('a laptop', Size(1440, 900)),
];

final Map<String, Widget Function()> _pages = <String, Widget Function()>{
  'home': () => const IndexPageGeneratedPage(),
  'docs': () => const DocsPageGeneratedPage(),
  'features': () => const FeaturesPageGeneratedPage(),
  'cloud': () => const CloudPageGeneratedPage(),
};

void main() {
  // Deferred pages in a widget test need both halves of this, and neither
  // alone is enough.
  //
  // A testWidgets body runs inside a FakeAsync zone. A library that has never
  // been loaded cannot finish loading there: pump() advances fake time while
  // the load waits on the real event loop, so the page sits on its loading
  // state forever. Calling loadLibrary inside tester.runAsync instead
  // deadlocks outright -- the suite produced no output at all and was killed
  // by its timeout, which reads exactly like a slow compile and was blamed on
  // one for weeks.
  //
  // So: load them for real up here, where setUpAll is ordinary async. That is
  // still not enough on its own, because the generated page caches the future
  // it created in this zone, and a future handed to a FutureBuilder in a
  // different zone never delivers -- every page then shows its loading state,
  // including the ones that loaded fine.
  //
  // Dropping the cache before each test makes the page call loadLibrary again
  // inside its own zone, where the library is by now already loaded, so the
  // new future completes at once.
  setUpAll(() async {
    await IndexPageGeneratedPage.loadLibrary();
    await FeaturesPageGeneratedPage.loadLibrary();
    await DocsPageGeneratedPage.loadLibrary();
    await CloudPageGeneratedPage.loadLibrary();
  });

  setUp(dvResetDeferredPages);

  for (final MapEntry<String, Widget Function()> page in _pages.entries) {
    group(page.key, () {
      for (final (String device, Size size) in _devices) {
        testWidgets('lays out on $device without overflowing',
            (WidgetTester tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);

          // Inside the site layout, because that is what the generated router
          // wraps each page in -- the header is where a row of links is most
          // likely to run off a narrow screen.
          await tester.pumpWidget(routed(page.value()));
          await tester.pump();
          // The generated router imports each page deferred, so the first
          // render schedules a library load. Left pending it fails the test
          // as a leaked timer, and which test sees it depends on ordering --
          // which is a confusing way to be told about a deferred import.
          await tester.pump(const Duration(milliseconds: 50));

          expect(tester.takeException(), isNull);
        });
      }

      testWidgets('the header does not run off a phone',
          (WidgetTester tester) async {
        // The specific failure a row of five links produces: it lays out
        // wider than the window and is clipped, so the last link is
        // unreachable and nothing says so.
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(routed(page.value()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(
          tester.getSize(find.byType(SiteHeader)).width,
          lessThanOrEqualTo(390),
        );
      });
    });
  }

  testWidgets('a reading column is capped on a wide display',
      (WidgetTester tester) async {
    // The other direction. Text that runs the full width of a 1920 monitor is
    // unreadable for a different reason than text that overflows a phone.
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(routed(const CloudPageGeneratedPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Found by the cap it declares, not by position. Taking the first
    // ConstrainedBox under a Section picks up whichever wrapper happens to
    // come first -- a minimum tap target, a reveal -- and measures something
    // that was never meant to be capped.
    final Iterable<ConstrainedBox> columns = tester
        .widgetList<ConstrainedBox>(find.byType(ConstrainedBox))
        .where((ConstrainedBox box) => box.constraints.maxWidth == 1040);

    expect(columns, isNotEmpty,
        reason: 'every section should hold its content to a reading column');

    for (final ConstrainedBox column in columns) {
      expect(tester.getSize(find.byWidget(column)).width,
          lessThanOrEqualTo(1040));
    }
  });
}
