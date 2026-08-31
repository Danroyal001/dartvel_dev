// The site renders, in both appearances, on every route.
//
// A build that succeeds proves the code compiled. It does not prove a page
// draws anything, and a site whose text is unselectable compiled perfectly for
// weeks.
import 'package:dartvel_site/components/site.dart';
import 'package:dartvel_site/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget page, Brightness brightness) => MaterialApp(
      theme: ThemeData(brightness: brightness, useMaterial3: true),
      home: Scaffold(body: SelectionArea(child: page)),
    );

void main() {
  // The generated page widgets, which is what the router actually builds.
  // These used to be public `buildXPage` functions the pages delegated to --
  // an indirection that existed only because @DVPage once required an
  // expression body. It does not any more, so the pages are private and this
  // renders what ships.
  // Each page with its own loader: loadLibrary is static per generated class,
  // so it cannot be reached through the DartvelPage the router builds.
  final pages = <String, (Future<void> Function(), Widget)>{
    'landing': (
      IndexPageGeneratedPage.loadLibrary,
      const IndexPageGeneratedPage()
    ),
    'features': (
      FeaturesPageGeneratedPage.loadLibrary,
      const FeaturesPageGeneratedPage()
    ),
    'docs': (DocsPageGeneratedPage.loadLibrary, const DocsPageGeneratedPage()),
    'cloud': (
      CloudPageGeneratedPage.loadLibrary,
      const CloudPageGeneratedPage()
    ),
  };

  for (final MapEntry<String, (Future<void> Function(), Widget)> page
      in pages.entries) {
    for (final Brightness brightness in Brightness.values) {
      testWidgets('${page.key} renders in ${brightness.name}',
          (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1400, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(host(page.value.$2, brightness));
        // The generated page loads its deferred library through a
        // FutureBuilder, so a single pump only ever sees the loading state.
        // Fixed frames rather than pumpAndSettle: Reveal retries every frame
        // until it is on screen, so the tree never goes quiet and settling
        // times out.
        // The deferred library resolves on the real event loop, which pump()
        // does not drain -- without runAsync the page sits on its loading
        // widget forever and the test reads as "the page renders nothing".
        await tester.runAsync(() async {
          await page.value.$1();
        });
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));

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
