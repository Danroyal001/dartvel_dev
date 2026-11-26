// While the build's page capture reads a page, its links preload nothing.
//
// A preload fetches the linked page's code (its deferred modules) without
// running it. The capture keys each route on the code its tab fetched, so
// that an edit re-reads only the routes that could have changed; with every
// header and footer link preloading, every route had fetched most of the
// site's modules, and a one-line edit to one page re-read all 225 routes of
// sigmadev.digital. What a page draws does not depend on what its links
// fetched ahead, so the capture marks the page (window.__dvCapture) and the
// links leave the fetching to the navigation that needs it.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/routing/first_frame_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pump(WidgetTester tester, Widget subject) async {
  final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (BuildContext context, GoRouterState state) => Scaffold(body: subject)),
      GoRoute(path: '/docs', builder: (BuildContext context, GoRouterState state) => const Scaffold(body: Text('docs page'))),
    ],
  );
  DVNavigation.attach(router);
  addTearDown(DVNavigation.detach);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pump();
}

void main() {
  setUp(() {
    dvDebugWebFirstFrame = true;
    dvDebugResetFirstFrameShown();
  });
  tearDown(() {
    dvDebugWebFirstFrame = null;
    dvDebugResetFirstFrameShown();
    DVRoutePrefetch.offForCapture = false;
  });

  testWidgets('a link preloads nothing while the capture reads the page', (WidgetTester tester) async {
    DVRoutePrefetch.offForCapture = true;
    int loads = 0;
    await pump(tester, DVNavLink(
      to: const DVRouteTarget('/docs'),
      preload: DVLinkPreload.immediate,
      onPreload: () async => loads++,
      child: const DVText('Docs'),
    ));
    dvDebugMarkFirstFrameShown();
    await tester.pump(const Duration(seconds: 2));
    expect(loads, 0);
    // The link still goes where it goes.
    await tester.tap(find.text('Docs'));
    await tester.pumpAndSettle();
    expect(find.text('docs page'), findsOneWidget);
  });

  testWidgets('and preloads as before for a visitor', (WidgetTester tester) async {
    int loads = 0;
    await pump(tester, DVNavLink(
      to: const DVRouteTarget('/docs'),
      preload: DVLinkPreload.immediate,
      onPreload: () async => loads++,
      child: const DVText('Docs'),
    ));
    dvDebugMarkFirstFrameShown();
    await tester.pump(const Duration(seconds: 2));
    expect(loads, 1);
  });
}
