// DVNavLink: a link, rather than a GestureDetector someone remembered to wire.
//
// The site's links were hand-rolled twice and dead once, because a tap handler
// on text is easy to write and easy to write wrongly. A link is a thing with
// behaviour — it navigates, it says where it goes, it looks clickable, and it
// can fetch what it points at before you ask for it.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

GoRouter routerWith(Widget subject) => GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext context, GoRouterState state) =>
              // Wrapped as a real page is: every Dartvel page sits inside a
              // SelectionArea, and a link that only works outside one is a
              // link that does not work.
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

void main() {
  group('navigating', () {
    testWidgets('a tap goes to the target', (WidgetTester tester) async {
      await pump(tester, const DVNavLink(
        to: DVRouteTarget('/docs'),
        child: DVText('Docs'),
      ));

      await tester.tap(find.text('Docs'));
      await tester.pump();

      expect(DV.Navigation.currentPath, '/docs');
    });

    testWidgets('the padding around the label is part of the target',
        (WidgetTester tester) async {
      // Bare glyphs mean the gaps between letters do nothing, and a click
      // that looks on-target misses.
      await pump(tester, const DVNavLink(
        to: DVRouteTarget('/docs'),
        child: DVText('Docs'),
      ));

      final rect = tester.getRect(find.text('Docs'));
      await tester.tapAt(Offset(rect.left - 3, rect.center.dy));
      await tester.pump();

      expect(DV.Navigation.currentPath, '/docs');
    });

    testWidgets('a disabled link does not navigate',
        (WidgetTester tester) async {
      await pump(tester, const DVNavLink(
        to: DVRouteTarget('/docs'),
        enabled: false,
        child: DVText('Docs'),
      ));

      await tester.tap(find.text('Docs'), warnIfMissed: false);
      await tester.pump();

      expect(DV.Navigation.currentPath, '/');
    });
  });

  group('saying where it goes', () {
    testWidgets('it is a link to assistive technology, with its destination',
        (WidgetTester tester) async {
      // A screen reader should hear a link and its target, not a tappable
      // piece of text.
      final SemanticsHandle handle = tester.ensureSemantics();
      await pump(tester, const DVNavLink(
        to: DVRouteTarget('/docs'),
        child: DVText('Docs'),
      ));

      // containsSemantics, not matchesSemantics: the latter is exhaustive and
      // would fail for every action a focusable link legitimately adds.
      expect(
        tester.getSemantics(find.byType(DVNavLink)),
        containsSemantics(isLink: true, hasTapAction: true),
      );
      handle.dispose();
    });

    testWidgets('hovering reports the destination for a preview',
        (WidgetTester tester) async {
      // What a browser shows in the corner. Dartvel renders to a canvas, so
      // nothing provides it unless the link does.
      String? previewed;
      await pump(tester, DVNavLink(
        to: const DVRouteTarget('/docs'),
        onPreview: (String? path) => previewed = path,
        child: const DVText('Docs'),
      ));

      final gesture =
          await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      await gesture.moveTo(tester.getCenter(find.text('Docs')));
      await tester.pump();
      expect(previewed, '/docs');

      await gesture.moveTo(const Offset(2000, 2000));
      await tester.pump();
      expect(previewed, isNull, reason: 'leaving should clear the preview');
    });
  });

  group('preloading', () {
    testWidgets('nothing is fetched before it is needed',
        (WidgetTester tester) async {
      var loads = 0;
      await pump(tester, DVNavLink(
        to: const DVRouteTarget('/docs'),
        preload: DVLinkPreload.hover,
        onPreload: () async => loads++,
        child: const DVText('Docs'),
      ));

      expect(loads, 0);
    });

    testWidgets('hovering fetches the route once, not on every frame',
        (WidgetTester tester) async {
      // A preload that refires on each pointer event turns a hover into a
      // burst of requests.
      var loads = 0;
      await pump(tester, DVNavLink(
        to: const DVRouteTarget('/docs'),
        preload: DVLinkPreload.hover,
        onPreload: () async => loads++,
        child: const DVText('Docs'),
      ));

      final gesture =
          await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      final centre = tester.getCenter(find.text('Docs'));
      await gesture.moveTo(centre);
      await tester.pump();
      await gesture.moveTo(centre + const Offset(1, 1));
      await tester.pump();
      await gesture.moveTo(const Offset(2000, 2000));
      await tester.pump();
      await gesture.moveTo(centre);
      await tester.pump();

      expect(loads, 1, reason: 'preloading should happen once per link');
    });

    testWidgets('immediate preloads on build', (WidgetTester tester) async {
      var loads = 0;
      await pump(tester, DVNavLink(
        to: const DVRouteTarget('/docs'),
        preload: DVLinkPreload.immediate,
        onPreload: () async => loads++,
        child: const DVText('Docs'),
      ));
      await tester.pump();

      expect(loads, 1);
    });

    testWidgets('none never preloads, however much you hover',
        (WidgetTester tester) async {
      var loads = 0;
      await pump(tester, DVNavLink(
        to: const DVRouteTarget('/docs'),
        preload: DVLinkPreload.none,
        onPreload: () async => loads++,
        child: const DVText('Docs'),
      ));

      final gesture =
          await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.text('Docs')));
      await tester.pump();

      expect(loads, 0);
    });

    testWidgets('a failing preload is reported and does not break the link',
        (WidgetTester tester) async {
      // Preloading is an optimisation, so a failure must not stop the tap
      // that follows. It is reported rather than swallowed: a preload that
      // silently never works is a performance bug nobody can see.
      await pump(tester, DVNavLink(
        to: const DVRouteTarget('/docs'),
        preload: DVLinkPreload.immediate,
        onPreload: () async => throw StateError('offline'),
        child: const DVText('Docs'),
      ));
      await tester.pump();

      expect(tester.takeException(), isA<StateError>(),
          reason: 'the failure should reach the developer');

      await tester.tap(find.text('Docs'));
      await tester.pump();

      expect(DV.Navigation.currentPath, '/docs',
          reason: 'a failed preload must not stop navigation');
    });
  });

  // What people expect of a link, and what Flutter gives them by default:
  // nothing. The app is a canvas, so there is no anchor for the browser to
  // act on -- no middle-click, no modifier-click, no keyboard focus, no URL in
  // the corner. Each of these has to be built.
  group('behaving like a link', () {
    testWidgets('it is focusable, and Enter activates it',
        (WidgetTester tester) async {
      // Focused through the link's own node rather than by tabbing: tab order
      // is the framework's business, and what matters here is that a link has
      // a node to focus and answers the keyboard once it does.
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);

      await pump(tester, DVNavLink(
        to: const DVRouteTarget('/docs'),
        focusNode: focusNode,
        child: const DVText('Docs'),
      ));

      expect(focusNode.canRequestFocus, isTrue,
          reason: 'a link should be reachable by keyboard');

      focusNode.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(DV.Navigation.currentPath, '/docs');
    });

    testWidgets('a middle click opens a new tab rather than navigating',
        (WidgetTester tester) async {
      // The reflex that costs nothing on a real site and does nothing on a
      // Flutter one.
      String? openedExternally;
      await pump(tester, DVNavLink(
        to: const DVRouteTarget('/docs'),
        openInNewTab: (String path) => openedExternally = path,
        child: const DVText('Docs'),
      ));

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Docs')),
        kind: PointerDeviceKind.mouse,
        buttons: kMiddleMouseButton,
      );
      await gesture.up();
      await tester.pump();

      expect(openedExternally, '/docs');
      expect(DV.Navigation.currentPath, '/',
          reason: 'a middle click must not navigate this tab');
    });

    testWidgets('a modifier click opens a new tab too',
        (WidgetTester tester) async {
      String? openedExternally;
      await pump(tester, DVNavLink(
        to: const DVRouteTarget('/docs'),
        openInNewTab: (String path) => openedExternally = path,
        child: const DVText('Docs'),
      ));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(find.text('Docs'));
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

      expect(openedExternally, '/docs');
      expect(DV.Navigation.currentPath, '/');
    });

    testWidgets('an ordinary click still navigates in place',
        (WidgetTester tester) async {
      // The check that stops the two above from breaking the common case.
      String? openedExternally;
      await pump(tester, DVNavLink(
        to: const DVRouteTarget('/docs'),
        openInNewTab: (String path) => openedExternally = path,
        child: const DVText('Docs'),
      ));

      await tester.tap(find.text('Docs'));
      await tester.pump();

      expect(openedExternally, isNull);
      expect(DV.Navigation.currentPath, '/docs');
    });
  });

  // Link previews. iOS gives them to Safari and Expo exposes them there; every
  // other platform gets nothing, and a Flutter app gets nothing anywhere,
  // because the app is a canvas with no anchor for the OS to act on.
  //
  // Dartvel already knows how to build the destination -- it built the router
  // -- so it can render the page it points at. That works the same on a
  // desktop, a phone, a television and the web, which is the point.
  group('previewing the destination', () {
    Widget previewable(Widget child) => DVNavLink(
          to: const DVRouteTarget('/docs'),
          child: child,
        );

    setUp(() {
      DVRoutePreviews.clear();
      DVRoutePreviews.register(
        '/docs',
        (BuildContext context) => const Text('the docs page'),
      );
    });
    tearDown(DVRoutePreviews.clear);

    testWidgets('nothing is shown until the pointer rests',
        (WidgetTester tester) async {
      await pump(tester, previewable(const DVText('Docs')));

      final gesture =
          await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      await gesture.moveTo(tester.getCenter(find.text('Docs')));
      await tester.pump();

      // Passing over a link on the way somewhere else must not flash a card.
      expect(find.text('the docs page'), findsNothing);
    });

    testWidgets('resting on a link shows the page it points at',
        (WidgetTester tester) async {
      await pump(tester, previewable(const DVText('Docs')));

      final gesture =
          await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      await gesture.moveTo(tester.getCenter(find.text('Docs')));
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.text('the docs page'), findsOneWidget);
    });

    testWidgets('leaving takes it away', (WidgetTester tester) async {
      await pump(tester, previewable(const DVText('Docs')));

      final gesture =
          await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      await gesture.moveTo(tester.getCenter(find.text('Docs')));
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('the docs page'), findsOneWidget);

      await gesture.moveTo(const Offset(2000, 2000));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('the docs page'), findsNothing);
    });

    testWidgets('a long press shows it where there is no pointer',
        (WidgetTester tester) async {
      // Touch. The reason this is not simply a hover feature.
      await pump(tester, previewable(const DVText('Docs')));

      await tester.longPress(find.text('Docs'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('the docs page'), findsOneWidget);
    });

    testWidgets('a route with nothing registered previews nothing, quietly',
        (WidgetTester tester) async {
      DVRoutePreviews.clear();
      await pump(tester, previewable(const DVText('Docs')));

      final gesture =
          await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.text('Docs')));
      await tester.pump(const Duration(milliseconds: 700));

      expect(tester.takeException(), isNull);
      expect(find.text('the docs page'), findsNothing);
    });

    testWidgets('the preview cannot be clicked through to the real page',
        (WidgetTester tester) async {
      // It is a picture of a destination, not the destination. A stray tap
      // inside it must not activate whatever it happens to be showing.
      DVRoutePreviews.clear();
      var tapped = false;
      DVRoutePreviews.register(
        '/docs',
        (BuildContext context) => GestureDetector(
          onTap: () => tapped = true,
          child: const Text('the docs page'),
        ),
      );

      await pump(tester, previewable(const DVText('Docs')));
      final gesture =
          await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.text('Docs')));
      await tester.pump(const Duration(milliseconds: 700));

      await tester.tap(find.text('the docs page'), warnIfMissed: false);
      await tester.pump();

      expect(tapped, isFalse);
    });

    testWidgets('previews can be turned off', (WidgetTester tester) async {
      await pump(tester, const DVNavLink(
        to: DVRouteTarget('/docs'),
        preview: DVLinkPreview.none,
        child: DVText('Docs'),
      ));

      final gesture =
          await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.text('Docs')));
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.text('the docs page'), findsNothing);
    });
  });
}
