// The search box: Ctrl+K or Cmd+K from anywhere, results as the reader
// types, arrows and Enter to open one, and a panel that is the whole screen
// on a phone.
import 'dart:async';

import 'package:dartvel_site/components/site_search.dart';
import 'package:dartvel_site/dartvel_client/dartvel_client.dart';
import 'package:dartvel_site/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const List<SiteSearchItem> found = <SiteSearchItem>[
  SiteSearchItem(
    title: 'Dartvel cache: get, set, has and delete',
    heading: '',
    snippet: 'Four calls.',
    href: '/docs/cache',
  ),
  SiteSearchItem(
    title: 'Dartvel auth: sign-in, second factor and sessions',
    heading: 'Second factor',
    snippet: 'An authenticator app code.',
    href: '/docs/auth#second-factor',
  ),
];

Widget app(SiteSearchFetch fetch) => MaterialApp.router(
      theme: dartvelSiteTheme(Brightness.light),
      routerConfig: GoRouter(routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext context, GoRouterState state) =>
              SiteSearchShortcut(
            fetch: fetch,
            child: const Scaffold(body: Text('home page')),
          ),
        ),
        GoRoute(
          path: '/docs/auth',
          builder: (BuildContext context, GoRouterState state) => Scaffold(
              body: Text('auth page #${state.uri.fragment}')),
        ),
        GoRoute(
          path: '/docs/cache',
          builder: (BuildContext context, GoRouterState state) =>
              const Scaffold(body: Text('cache page')),
        ),
      ]),
    );

Future<void> pressSearchShortcut(WidgetTester tester,
    {LogicalKeyboardKey modifier = LogicalKeyboardKey.controlLeft}) async {
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
  await tester.sendKeyUpEvent(modifier);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Ctrl+K and Cmd+K open the search from a page with no focus',
      (WidgetTester tester) async {
    await tester.pumpWidget(app((String q) async => const SiteSearchAnswer()));
    await tester.pumpAndSettle();
    expect(find.byType(SiteSearchPanel), findsNothing);

    await pressSearchShortcut(tester);
    expect(find.byType(SiteSearchPanel), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(SiteSearchPanel), findsNothing);

    await pressSearchShortcut(tester, modifier: LogicalKeyboardKey.metaLeft);
    expect(find.byType(SiteSearchPanel), findsOneWidget);
  });

  testWidgets('K alone types a K; it opens nothing',
      (WidgetTester tester) async {
    await tester.pumpWidget(app((String q) async => const SiteSearchAnswer()));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.pumpAndSettle();
    expect(find.byType(SiteSearchPanel), findsNothing);
  });

  testWidgets('typing asks once the reader pauses, and shows what came back',
      (WidgetTester tester) async {
    final List<String> asked = <String>[];
    await tester.pumpWidget(app((String q) async {
      asked.add(q);
      return const SiteSearchAnswer(items: found);
    }));
    await pressSearchShortcut(tester);

    await tester.enterText(find.byType(TextField), 'c');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.enterText(find.byType(TextField), 'ca');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.enterText(find.byType(TextField), 'cache');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    // One request for what the reader stopped at, not one per keystroke.
    expect(asked, <String>['cache']);
    expect(find.text('Dartvel cache: get, set, has and delete'), findsOneWidget);
    expect(find.text('Second factor'), findsOneWidget);
  });

  testWidgets('an answer to an older query never replaces a newer one',
      (WidgetTester tester) async {
    final Completer<SiteSearchAnswer> slow = Completer<SiteSearchAnswer>();
    await tester.pumpWidget(app((String q) async => q == 'ca'
        ? slow.future
        : const SiteSearchAnswer(items: <SiteSearchItem>[
            SiteSearchItem(
                title: 'The newer answer', heading: '', snippet: '', href: '/'),
          ])));
    await pressSearchShortcut(tester);
    await tester.enterText(find.byType(TextField), 'ca');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField), 'cache');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    slow.complete(const SiteSearchAnswer(items: found));
    await tester.pumpAndSettle();

    expect(find.text('The newer answer'), findsOneWidget);
    expect(find.text('Dartvel cache: get, set, has and delete'), findsNothing);
  });

  testWidgets('down and Enter open the second result, at its section',
      (WidgetTester tester) async {
    await tester.pumpWidget(
        app((String q) async => const SiteSearchAnswer(items: found)));
    await pressSearchShortcut(tester);
    await tester.enterText(find.byType(TextField), 'factor');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.byType(SiteSearchPanel), findsNothing);
    expect(find.text('auth page #second-factor'), findsOneWidget);
  });

  testWidgets('a rate-limited reader is told to wait, not shown an error',
      (WidgetTester tester) async {
    await tester.pumpWidget(
        app((String q) async => const SiteSearchAnswer(limited: true)));
    await pressSearchShortcut(tester);
    await tester.enterText(find.byType(TextField), 'cache');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.textContaining('Too many searches'), findsOneWidget);
  });

  testWidgets('on a phone the panel is the whole screen and nothing overflows',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
        app((String q) async => const SiteSearchAnswer(items: found)));
    await pressSearchShortcut(tester);
    await tester.enterText(find.byType(TextField), 'cache');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(SiteSearchPanel)).width, 390);
    expect(find.text('Close'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the header button opens it too, and is a magnifier on a phone',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp.router(
      theme: dartvelSiteTheme(Brightness.light),
      routerConfig: GoRouter(routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext context, GoRouterState state) =>
              const Scaffold(body: SiteHeader()),
        ),
      ]),
    ));
    await tester.pump();
    expect(find.bySemanticsLabel('Search the site'), findsOneWidget);
    expect(find.text('Ctrl K'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
