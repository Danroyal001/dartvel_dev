// A link to a heading opens the page at that heading.
//
// `/docs/ui#layouts` is how a reader shares a place in a long page, and a
// Flutter page ignores everything after the `#`: the page opened at the top
// and the reader never saw the section the link was for. Every heading a page
// draws now has an id from its words (dvHeadingSlug), and the page shell
// scrolls to the one the address names.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/find/find_in_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget body() => SingleChildScrollView(
      child: Column(
        crossAxisAlignment: .start,
        children: <Widget>[
          Semantics(headingLevel: 1, child: const Text('Retention policy')),
          for (int i = 0; i < 40; i++)
            Padding(
              padding: const .all(8),
              child: Text('Paragraph $i says something about records.'),
            ),
          Semantics(headingLevel: 2, child: const Text('Setup')),
          for (int i = 0; i < 40; i++)
            Padding(
              padding: const .all(8),
              child: Text('Step $i of the setup.'),
            ),
          Semantics(headingLevel: 2, child: const Text('Setup')),
          const Text('The second setup section.'),
          for (int i = 0; i < 10; i++) const SizedBox(height: 60),
        ],
      ),
    );

Widget page() => MaterialApp(
      home: DVPageShell(
        spec: const DVPageScaffoldSpec(title: 'Policy'),
        child: body(),
      ),
    );

bool onScreen(WidgetTester tester, Finder finder) {
  final Rect rect = tester.getRect(finder);
  final Size screen = tester.view.physicalSize / tester.view.devicePixelRatio;
  return rect.top >= 0 && rect.bottom <= screen.height;
}

double offset(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).last).position.pixels;

void main() {
  testWidgets('a heading id scrolls the page to that heading',
      (WidgetTester tester) async {
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    expect(onScreen(tester, find.text('Setup').first), isFalse);

    final Future<bool> revealed = DVFindInPage.revealHeading('setup');
    await tester.pumpAndSettle();
    expect(await revealed, isTrue);
    expect(onScreen(tester, find.text('Setup').first), isTrue);
  });

  testWidgets('a repeated heading is reached by its number',
      (WidgetTester tester) async {
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    final Future<bool> revealed = DVFindInPage.revealHeading('setup-2');
    await tester.pumpAndSettle();
    expect(await revealed, isTrue);
    expect(onScreen(tester, find.text('The second setup section.')), isTrue);
    expect(onScreen(tester, find.text('Setup').first), isFalse);
  });

  testWidgets('an id no heading has leaves the page where it is',
      (WidgetTester tester) async {
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    final Future<bool> revealed = DVFindInPage.revealHeading('pricing');
    await tester.pumpAndSettle();
    expect(await revealed, isFalse);
    expect(offset(tester), 0);
  });

  testWidgets('the page opens at the heading its address names',
      (WidgetTester tester) async {
    final GoRouter router = GoRouter(
      initialLocation: '/policy#setup-2',
      routes: <RouteBase>[
        GoRoute(
          path: '/policy',
          builder: (BuildContext context, GoRouterState state) =>
              DVPageShell(
            spec: const DVPageScaffoldSpec(title: 'Policy'),
            child: body(),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(onScreen(tester, find.text('The second setup section.')), isTrue);
  });

  testWidgets('a text fragment is not a heading id',
      (WidgetTester tester) async {
    final GoRouter router = GoRouter(
      initialLocation: '/policy#:~:text=setup',
      routes: <RouteBase>[
        GoRoute(
          path: '/policy',
          builder: (BuildContext context, GoRouterState state) =>
              DVPageShell(
            spec: const DVPageScaffoldSpec(title: 'Policy'),
            child: body(),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(offset(tester), 0);
  });
}
