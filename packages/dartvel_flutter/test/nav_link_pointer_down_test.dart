// A link opens on the press, not the release -- for a mouse.
//
// A click is two events a hundred-odd milliseconds apart, and a link that
// waits for the second has spent that time doing nothing. NextFaster
// navigates on mousedown; so does this now, for a mouse's primary button.
//
// Only a mouse. A finger that lands on a link is as often starting a scroll as
// choosing the link, so touch still waits for the tap -- navigating on a touch
// press would follow every link a scroll happened to begin on. Ctrl and cmd
// still open beside the page rather than replacing it, and a link that
// outlives the navigation must not be followed a second time when the release
// arrives as a tap on it.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

int docsVisits = 0;

String? _count(BuildContext context, GoRouterState state) {
  if (state.uri.path == '/docs') docsVisits++;
  return null;
}

DVNavLink link() => const DVNavLink(
      to: DVRouteTarget('/docs'),
      preload: DVLinkPreload.none,
      child: DVText('Docs'),
    );

/// The link on the home page, replaced by the page it leads to.
Future<void> pumpOnPage(WidgetTester tester) async {
  docsVisits = 0;
  final router = GoRouter(
    initialLocation: '/',
    redirect: _count,
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (BuildContext c, GoRouterState s) =>
            Scaffold(body: SelectionArea(child: Center(child: link()))),
      ),
      GoRoute(
        path: '/docs',
        builder: (BuildContext c, GoRouterState s) =>
            const Scaffold(body: Text('docs page')),
      ),
    ],
  );
  DVNavigation.attach(router);
  addTearDown(DVNavigation.detach);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pump();
}

/// The link in a shell that survives navigation, the way a header does.
Future<void> pumpInShell(WidgetTester tester) async {
  docsVisits = 0;
  final router = GoRouter(
    initialLocation: '/',
    redirect: _count,
    routes: <RouteBase>[
      ShellRoute(
        builder: (BuildContext c, GoRouterState s, Widget child) => Scaffold(
          body: Column(children: <Widget>[link(), Expanded(child: child)]),
        ),
        routes: <RouteBase>[
          GoRoute(
            path: '/',
            builder: (BuildContext c, GoRouterState s) =>
                const Text('home page'),
          ),
          GoRoute(
            path: '/docs',
            builder: (BuildContext c, GoRouterState s) =>
                const Text('docs page'),
          ),
        ],
      ),
    ],
  );
  DVNavigation.attach(router);
  addTearDown(DVNavigation.detach);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pump();
}

void main() {
  testWidgets('control: a plain tap navigates exactly once',
      (WidgetTester tester) async {
    // Proves the counter counts. Without this the "once" below could pass on
    // an instrument that never sees a navigation at all.
    await pumpOnPage(tester);
    await tester.tap(find.text('Docs'));
    await tester.pump();

    expect(DV.Navigation.currentPath, '/docs');
    expect(docsVisits, 1);
  });

  testWidgets('a mouse press navigates before the button comes up',
      (WidgetTester tester) async {
    await pumpOnPage(tester);
    final TestGesture press = await tester.startGesture(
      tester.getCenter(find.text('Docs')),
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await tester.pump();

    expect(DV.Navigation.currentPath, '/docs',
        reason: 'the button is still down and the page should already be here');
    await press.up();
    await tester.pump();
  });

  testWidgets('a link that outlives the navigation is not followed twice',
      (WidgetTester tester) async {
    await pumpInShell(tester);
    final TestGesture press = await tester.startGesture(
      tester.getCenter(find.text('Docs')),
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await tester.pump();
    await press.up();
    await tester.pump();

    expect(DV.Navigation.currentPath, '/docs');
    expect(docsVisits, 1,
        reason: 'the press navigated; the release must not arrive as a second tap');
  });

  testWidgets('a touch still waits for the tap', (WidgetTester tester) async {
    // A finger landing on a link is as often starting a scroll as choosing it.
    await pumpOnPage(tester);
    final TestGesture finger = await tester.startGesture(
      tester.getCenter(find.text('Docs')),
      kind: PointerDeviceKind.touch,
    );
    await tester.pump();
    expect(DV.Navigation.currentPath, '/');

    await finger.up();
    await tester.pump();
    expect(DV.Navigation.currentPath, '/docs');
  });

  testWidgets('a press with ctrl held is not followed in place',
      (WidgetTester tester) async {
    await pumpOnPage(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    final TestGesture press = await tester.startGesture(
      tester.getCenter(find.text('Docs')),
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
    );
    await tester.pump();

    expect(DV.Navigation.currentPath, '/',
        reason: 'ctrl asks for a new tab; replacing this page would lose it');
    await press.cancel();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  });

  testWidgets('the right button navigates nowhere', (WidgetTester tester) async {
    await pumpOnPage(tester);
    final TestGesture press = await tester.startGesture(
      tester.getCenter(find.text('Docs')),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pump();

    expect(DV.Navigation.currentPath, '/');
    await press.cancel();
  });
}
