// A navigation stack per tab that keeps its state.
//
// go_router's two most-reacted issues are multiple stacks (#99126) and
// keeping their state (#99124); StatefulShellRoute is the answer, and these
// hold Dartvel's tabs to it. Each tab keeps its own stack and its widgets'
// state while another is shown, and back -- the Android button and the iOS
// edge swipe -- pops inside the tab on screen before it does anything else.
import 'dart:async';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class Counter extends StatefulWidget {
  const Counter({super.key});

  @override
  State<Counter> createState() => _CounterState();
}

class _CounterState extends State<Counter> {
  int taps = 0;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => setState(() => taps++),
    child: Text('inbox taps $taps'),
  );
}

List<DVRouteNode> tabs() => <DVRouteNode>[
  DVStatefulShellRoute(
    builder:
        (
          BuildContext context,
          DVRouteState state,
          DVShellNavigation shell,
        ) => Scaffold(
          body: shell,
          bottomNavigationBar: Row(
            children: <Widget>[
              TextButton(
                onPressed: () => shell.goBranch(0),
                child: Text('feed tab${shell.currentIndex == 0 ? ' *' : ''}'),
              ),
              TextButton(
                onPressed: () => shell.goBranch(1),
                child: Text('inbox tab${shell.currentIndex == 1 ? ' *' : ''}'),
              ),
            ],
          ),
        ),
    branches: <DVShellBranch>[
      DVShellBranch(
        routes: <DVRouteNode>[
          DVRoute(
            path: '/feed',
            builder: (BuildContext context, DVRouteState state) =>
                const Center(child: Text('feed list')),
            routes: <DVRouteNode>[
              DVRoute(
                path: ':post',
                builder: (BuildContext context, DVRouteState state) =>
                    Center(child: Text('post ${state.params['post']}')),
              ),
            ],
          ),
        ],
      ),
      DVShellBranch(
        routes: <DVRouteNode>[
          DVRoute(
            path: '/inbox',
            builder: (BuildContext context, DVRouteState state) =>
                const Center(child: Counter()),
          ),
        ],
      ),
    ],
  ),
];

Future<GoRouter> pump(WidgetTester tester) async {
  final GoRouter router = GoRouter(
    initialLocation: '/feed',
    routes: dvOrderGoRoutes(
      dvConfigRoutes(
        tabs(),
        // The project default a page gets. A route pushed inside a stack takes
        // the platform's push instead, which is what carries the iOS swipe.
        transition: PageTransitionSpec.none,
      ),
    ),
  );
  addTearDown(router.dispose);
  DVNavigation.attach(router);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  return router;
}

void main() {
  tearDown(DVNavigation.detach);

  testWidgets('each tab keeps its own stack and its state', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    DV.Navigation.navigate(const DVRouteTarget('/feed/7'));
    await tester.pumpAndSettle();
    expect(find.text('post 7'), findsOneWidget);

    await tester.tap(find.text('inbox tab'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('inbox taps 0'));
    await tester.pumpAndSettle();
    expect(find.text('inbox taps 1'), findsOneWidget);

    // Back to the feed tab: still on the post it was left on.
    await tester.tap(find.text('feed tab'));
    await tester.pumpAndSettle();
    expect(find.text('post 7'), findsOneWidget);
    expect(DV.Navigation.currentPath, '/feed/7');

    // And the inbox kept its count while it was hidden.
    await tester.tap(find.text('inbox tab'));
    await tester.pumpAndSettle();
    expect(find.text('inbox taps 1'), findsOneWidget);
  });

  testWidgets('the Android back button pops inside the tab first', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    DV.Navigation.navigate(const DVRouteTarget('/feed/7'));
    await tester.pumpAndSettle();

    final bool handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(handled, isTrue);
    expect(find.text('feed list'), findsOneWidget);
    expect(find.text('feed tab *'), findsOneWidget);
    expect(DV.Navigation.currentPath, '/feed');
  });

  testWidgets('a selectable page still swipes back on iOS', (
    WidgetTester tester,
  ) async {
    // Every generated page is inside DVPageShell, whose text is selectable by
    // default. The selection area took the edge swipe for itself, so no page
    // in a Dartvel app on iOS could be swiped back from.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final GoRouter router = GoRouter(
        initialLocation: '/list',
        routes: dvConfigRoutes(<DVRouteNode>[
          DVRoute(
            path: '/list',
            builder: (BuildContext context, DVRouteState state) =>
                const DVPageShell(
                  spec: DVPageScaffoldSpec(),
                  child: Center(child: Text('list')),
                ),
            routes: <DVRouteNode>[
              DVRoute(
                path: ':item',
                builder: (BuildContext context, DVRouteState state) =>
                    const DVPageShell(
                      spec: DVPageScaffoldSpec(),
                      child: Center(child: Text('detail')),
                    ),
              ),
            ],
          ),
        ], transition: PageTransitionSpec.none),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      router.go('/list/1');
      await tester.pumpAndSettle();
      expect(find.text('detail'), findsOneWidget);

      final TestGesture swipe = await tester.startGesture(const Offset(2, 300));
      await swipe.moveBy(const Offset(500, 0));
      await swipe.up();
      await tester.pumpAndSettle();

      expect(find.text('detail'), findsNothing);
      expect(find.text('list'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('a deep link to a selectable page over another builds both', (
    WidgetTester tester,
  ) async {
    // The page underneath is covered, so it is not laid out, and its selection
    // area asked its text for sizes: the deep link threw.
    final GoRouter router = GoRouter(
      initialLocation: '/list/1',
      routes: dvConfigRoutes(<DVRouteNode>[
        DVRoute(
          path: '/list',
          builder: (BuildContext context, DVRouteState state) =>
              const DVPageShell(
                spec: DVPageScaffoldSpec(),
                child: Column(children: <Widget>[Text('the list'), Counter()]),
              ),
          routes: <DVRouteNode>[
            DVRoute(
              path: ':item',
              builder: (BuildContext context, DVRouteState state) =>
                  const DVPageShell(
                    spec: DVPageScaffoldSpec(),
                    child: Center(child: Text('detail')),
                  ),
            ),
          ],
        ),
      ], transition: PageTransitionSpec.none),
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('detail'), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('inbox taps 0'));
    await tester.pumpAndSettle();

    // Covered again and uncovered: the page keeps its state across the
    // selection switching off and on.
    unawaited(router.push<void>('/list/2'));
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('inbox taps 1'), findsOneWidget);
  });

  testWidgets('a selectable page with a grid can be covered and uncovered', (
    WidgetTester tester,
  ) async {
    // A lazy list or grid keeps each child alive through a widget that turns
    // into a selection scope when a selection registrar is above it and back
    // when there is none. Turning selection off beneath a covering route took
    // the registrar away, every grid child rebuilt into a different widget
    // outside the grid's own layout, and the sliver asserted: the example's
    // home page, a DVBox.grid, threw as soon as a link was tapped.
    final GoRouter router = GoRouter(
      initialLocation: '/list',
      routes: dvConfigRoutes(<DVRouteNode>[
        DVRoute(
          path: '/list',
          builder: (BuildContext context, DVRouteState state) => DVPageShell(
            spec: const DVPageScaffoldSpec(),
            child: GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              children: const <Widget>[Counter(), Text('one'), Text('two')],
            ),
          ),
          routes: <DVRouteNode>[
            DVRoute(
              path: ':item',
              builder: (BuildContext context, DVRouteState state) =>
                  const DVPageShell(
                    spec: DVPageScaffoldSpec(),
                    child: Center(child: Text('detail')),
                  ),
            ),
          ],
        ),
      ], transition: PageTransitionSpec.none),
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('inbox taps 0'));
    await tester.pumpAndSettle();

    unawaited(router.push<void>('/list/1'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('detail'), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('inbox taps 1'), findsOneWidget);
  });

  testWidgets('the iOS edge swipe pops inside the tab first', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await pump(tester);
      DV.Navigation.navigate(const DVRouteTarget('/feed/7'));
      await tester.pumpAndSettle();
      expect(find.text('post 7'), findsOneWidget);

      final TestGesture swipe = await tester.startGesture(const Offset(2, 300));
      await swipe.moveBy(const Offset(500, 0));
      await swipe.up();
      await tester.pumpAndSettle();

      expect(find.text('post 7'), findsNothing);
      expect(find.text('feed list'), findsOneWidget);
      expect(find.text('feed tab *'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
