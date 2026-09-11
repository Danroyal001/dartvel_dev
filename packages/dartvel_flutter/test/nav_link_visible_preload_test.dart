// A link fetches what it points at once it has been on screen a moment.
//
// Hover was the only trigger, and a hover is a desktop thing: on a phone
// there is no pointer to arrive, so no link on a touch screen preloaded
// anything unless it was marked `immediate`. NextFaster preloads a link that
// has sat in the viewport for 300 ms, and on hover as well, whichever comes
// first. That is `visible`, and it is the default now.
//
// The delay is the point. A link flicked past on the way down a long page
// should cost nothing; one that stays long enough to be read is likely to be
// the next tap.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

GoRouter routerWith(Widget subject) => GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext context, GoRouterState state) =>
              Scaffold(body: SelectionArea(child: subject)),
        ),
        GoRoute(
          path: '/docs',
          builder: (BuildContext context, GoRouterState state) =>
              const Scaffold(body: Text('docs page')),
        ),
      ],
    );

Future<void> pump(WidgetTester tester, Widget subject) async {
  final router = routerWith(subject);
  DVNavigation.attach(router);
  addTearDown(DVNavigation.detach);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pump();
}

/// A page with the link far below the fold, and a handle to scroll it.
Widget belowTheFold(ScrollController controller, VoidCallback onLoad) =>
    SingleChildScrollView(
      controller: controller,
      child: Column(children: <Widget>[
        const SizedBox(height: 3000),
        DVNavLink(
          to: const DVRouteTarget('/docs'),
          preload: DVLinkPreload.visible,
          onPreload: () async => onLoad(),
          child: const DVText('Docs'),
        ),
        const SizedBox(height: 3000),
      ]),
    );

void main() {
  testWidgets('a link on screen preloads once it has been there a moment',
      (WidgetTester tester) async {
    var loads = 0;
    await pump(tester, DVNavLink(
      to: const DVRouteTarget('/docs'),
      preload: DVLinkPreload.visible,
      onPreload: () async => loads++,
      child: const DVText('Docs'),
    ));

    await tester.pump(dvLinkVisibleDelay - const Duration(milliseconds: 100));
    expect(loads, 0, reason: 'too early: a link merely passed should cost nothing');

    await tester.pump(const Duration(milliseconds: 150));
    expect(loads, 1);
  });

  testWidgets('below the fold, nothing until it is scrolled into view',
      (WidgetTester tester) async {
    var loads = 0;
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await pump(tester, belowTheFold(controller, () => loads++));

    await tester.pump(const Duration(seconds: 2));
    expect(loads, 0, reason: 'the link is 3000 points down and off screen');

    controller.jumpTo(2800);
    await tester.pump();
    await tester.pump(dvLinkVisibleDelay + const Duration(milliseconds: 50));
    expect(loads, 1);
  });

  testWidgets('scrolled past before the moment is up, it is not fetched',
      (WidgetTester tester) async {
    var loads = 0;
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await pump(tester, belowTheFold(controller, () => loads++));

    controller.jumpTo(2800);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    controller.jumpTo(0);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(loads, 0, reason: 'on screen for 100 ms is a flick, not a read');
  });

  testWidgets('hovering still fetches at once', (WidgetTester tester) async {
    var loads = 0;
    await pump(tester, DVNavLink(
      to: const DVRouteTarget('/docs'),
      preload: DVLinkPreload.visible,
      onPreload: () async => loads++,
      child: const DVText('Docs'),
    ));

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.text('Docs')));
    await tester.pump();

    expect(loads, 1, reason: 'a pointer arriving is a stronger signal than time');
  });

  testWidgets('visible is the default', (WidgetTester tester) async {
    var loads = 0;
    await pump(tester, DVNavLink(
      to: const DVRouteTarget('/docs'),
      onPreload: () async => loads++,
      child: const DVText('Docs'),
    ));

    await tester.pump(dvLinkVisibleDelay + const Duration(milliseconds: 50));
    expect(loads, 1, reason: 'without it, no link on a touch screen preloads');
  });

  testWidgets('once, however long it stays and however often it returns',
      (WidgetTester tester) async {
    var loads = 0;
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await pump(tester, belowTheFold(controller, () => loads++));

    for (int i = 0; i < 3; i++) {
      controller.jumpTo(2800);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      controller.jumpTo(0);
      await tester.pump();
    }

    expect(loads, 1);
  });
}
