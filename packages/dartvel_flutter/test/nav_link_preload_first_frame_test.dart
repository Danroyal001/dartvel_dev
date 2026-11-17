// A link's preload waits until the page is on screen.
//
// On the web the first frame is held back while the initial route loads
// (deferFirstFrame), but frames still build and lay out behind the splash, so
// post-frame callbacks run. A link that preloaded from one fetched other
// pages' documents, images and deferred modules while the visitor was still
// looking at the splash. Measured on sigmadev.digital, Fast 3G, CPU 4x:
// /contact and /pricing-plans-and-services with 29 deferred wasm modules
// were fetched and compiled before the home page's first frame, competing
// with it for the network and the CPU.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/routing/first_frame_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

GoRouter routerWith(Widget subject) => GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext context, GoRouterState state) =>
              Scaffold(body: subject),
        ),
        GoRoute(
          path: '/docs',
          builder: (BuildContext context, GoRouterState state) =>
              const Scaffold(body: Text('docs page')),
        ),
      ],
    );

Future<void> pump(WidgetTester tester, Widget subject) async {
  final GoRouter router = routerWith(subject);
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
  });

  testWidgets('an immediate link waits for the first frame on screen',
      (WidgetTester tester) async {
    int loads = 0;
    await pump(tester, DVNavLink(
      to: const DVRouteTarget('/docs'),
      preload: DVLinkPreload.immediate,
      onPreload: () async => loads++,
      child: const DVText('Docs'),
    ));
    await tester.pump(const Duration(seconds: 2));
    expect(loads, 0,
        reason: 'the splash is still up: nothing may compete with the page');

    dvDebugMarkFirstFrameShown();
    await tester.pump();
    expect(loads, 1);
  });

  testWidgets('a visible link waits for the first frame, then its moment',
      (WidgetTester tester) async {
    int loads = 0;
    await pump(tester, DVNavLink(
      to: const DVRouteTarget('/docs'),
      preload: DVLinkPreload.visible,
      onPreload: () async => loads++,
      child: const DVText('Docs'),
    ));
    await tester.pump(const Duration(seconds: 2));
    expect(loads, 0, reason: 'on screen behind the splash is not on screen');

    dvDebugMarkFirstFrameShown();
    await tester.pump();
    await tester.pump(dvLinkVisibleDelay + const Duration(milliseconds: 50));
    expect(loads, 1);
  });

  testWidgets('without a held first frame a link preloads as before',
      (WidgetTester tester) async {
    dvDebugWebFirstFrame = false;
    int loads = 0;
    await pump(tester, DVNavLink(
      to: const DVRouteTarget('/docs'),
      preload: DVLinkPreload.immediate,
      onPreload: () async => loads++,
      child: const DVText('Docs'),
    ));
    await tester.pump();
    expect(loads, 1, reason: 'devices and tests draw their first frame at once');
  });
}
