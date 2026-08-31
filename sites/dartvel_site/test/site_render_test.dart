// The site renders, in both appearances, on every route.
//
// A build that succeeds proves the code compiled. It does not prove a page
// draws anything, and a site whose text is unselectable compiled perfectly for
// weeks.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_site/components/site.dart';
import 'package:dartvel_site/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget page, Brightness brightness) => MaterialApp(
      theme: ThemeData(brightness: brightness, useMaterial3: true),
      home: Scaffold(body: SelectionArea(child: page)),
    );

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

  // The generated page widgets, which is what the router actually builds.
  // These used to be public `buildXPage` functions the pages delegated to --
  // an indirection that existed only because @DVPage once required an
  // expression body. It does not any more, so the pages are private and this
  // renders what ships.
  // No loadLibrary here, and that is the fix rather than an omission.
  //
  // This used to call it inside tester.runAsync, on the theory that the
  // deferred library resolves on the real event loop which pump() does not
  // drain. runAsync around loadLibrary deadlocks: the suite produced no
  // output at all and was killed by its timeout, which reads exactly like a
  // slow compile and was blamed on one for weeks.
  //
  // It is also unnecessary. The Dart VM does not split deferred libraries, so
  // in a test they are already loaded and the generated page's FutureBuilder
  // resolves on the next pump.
  final pages = <String, Widget>{
    'landing': const IndexPageGeneratedPage(),
    'features': const FeaturesPageGeneratedPage(),
    'docs': const DocsPageGeneratedPage(),
    'cloud': const CloudPageGeneratedPage(),
  };

  for (final MapEntry<String, Widget> page in pages.entries) {
    for (final Brightness brightness in Brightness.values) {
      testWidgets('${page.key} renders in ${brightness.name}',
          (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1400, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(host(page.value, brightness));
        // The generated page loads its deferred library through a
        // FutureBuilder, so a single pump only ever sees the loading state.
        //
        // Fixed frames rather than pumpAndSettle: a revealed section retries
        // its position check every frame until it is on screen, so the tree
        // never goes quiet and settling times out.
        // Several frames, not two. The deferred library resolves on a timer,
        // the FutureBuilder needs a frame after that to build its child, and
        // the reveal needs one more. Two frames happened to be enough for
        // whichever page ran first and for nothing after it, which is how
        // this failed: the first test passed and every later one reported
        // that the page rendered nothing.
        for (int frame = 0; frame < 6; frame += 1) {
          await tester.pump(const Duration(seconds: 1));
        }

        expect(tester.takeException(), isNull);
        expect(find.byType(DVText), findsWidgets);
      });
    }
  }

  testWidgets('the palette actually differs between appearances',
      (WidgetTester tester) async {
    // Two themes that resolve to the same colours is the failure a render
    // test alone would pass.
    late Palette light;
    late Palette dark;

    // Distinct keys, or Flutter reuses the element between pumps and the
    // second Builder never re-resolves -- which reads as "both themes are
    // identical" and is really "the theme never changed".
    await tester.pumpWidget(MaterialApp(
      key: const ValueKey<String>('light'),
      theme: ThemeData(brightness: Brightness.light),
      home: Builder(builder: (BuildContext context) {
        light = Palette.of(context);
        return const SizedBox.shrink();
      }),
    ));
    await tester.pumpWidget(MaterialApp(
      key: const ValueKey<String>('dark'),
      theme: ThemeData(brightness: Brightness.dark),
      home: Builder(builder: (BuildContext context) {
        dark = Palette.of(context);
        return const SizedBox.shrink();
      }),
    ));

    expect(light.page, isNot(dark.page));
    expect(light.ink, isNot(dark.ink));
    expect(light.surface, isNot(dark.surface));
    // Ink must contrast with its own background in each, or one appearance is
    // unreadable while the other looks fine.
    expect((light.ink.computeLuminance() - light.page.computeLuminance()).abs(),
        greaterThan(0.5));
    expect((dark.ink.computeLuminance() - dark.page.computeLuminance()).abs(),
        greaterThan(0.5));
  });

  testWidgets('code blocks are selectable', (WidgetTester tester) async {
    // The complaint that started this: an install command you cannot copy.
    await tester.pumpWidget(host(
      const CodeBlock(<String>['brew install dartvel_dev']),
      Brightness.light,
    ));

    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.text('brew install dartvel_dev'), findsOneWidget);
  });
}
