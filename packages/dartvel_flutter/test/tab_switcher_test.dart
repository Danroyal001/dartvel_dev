// The tab strip on a TV and on a watch: a switcher, not a strip.
//
// The spec: on TV and watch the strip renders as a platform-appropriate
// switcher and reorder is a context action. A TV has a D-pad and no
// pointer, so tabs are focusable tiles moved between with left and right
// and chosen with select; a watch has a small round face, so tabs stack
// and one is tapped. Neither has a drag, so moving or closing a tab is an
// action on the tab's menu. The presentation is chosen from the device,
// and a page can name it outright.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const DVRouteTarget orders = DVRouteTarget('/orders');
const DVRouteTarget customers = DVRouteTarget('/customers');
const DVRouteTarget reports = DVRouteTarget('/reports');

DVTabWorkspaceController threeTabs() => DVTabWorkspaceController(
      tabs: const <DVTab>[DVTab(orders), DVTab(customers), DVTab(reports)],
    );

List<String> paths(DVTabWorkspaceController c) => c.tabs.map((DVTab t) => t.route.path).toList();

Finder key(String k) => find.byKey(ValueKey<String>(k));

Widget host(DVTabWorkspaceController c, DVTabPresentation p) => MaterialApp(
      home: Scaffold(body: DVTabWorkspace(controller: c, presentation: p)),
    );

void main() {
  setUp(DVWindowManager.reset);
  tearDown(DVWindowManager.reset);

  test('the presentation follows the device', () {
    expect(dvTabPresentationFor(isTV: true, isWatch: false), DVTabPresentation.tv);
    expect(dvTabPresentationFor(isTV: false, isWatch: true), DVTabPresentation.watch);
    expect(dvTabPresentationFor(isTV: false, isWatch: false), DVTabPresentation.strip);
  });

  group('on a TV', () {
    testWidgets('left and right move between tiles; select chooses', (WidgetTester tester) async {
      final DVTabWorkspaceController c = threeTabs();
      await tester.pumpWidget(host(c, DVTabPresentation.tv));
      await tester.pump();
      expect(key('dv-tab-tile-0'), findsOneWidget);
      expect(key('dv-tab-tile-2'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(c.activeIndex, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(c.activeIndex, 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(c.activeIndex, 1);
    });

    testWidgets('the menu key opens the tab\'s actions: move and close', (WidgetTester tester) async {
      final DVTabWorkspaceController c = threeTabs();
      await tester.pumpWidget(host(c, DVTabPresentation.tv));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(key('dv-tab-actions'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pump();
      expect(key('dv-tab-actions'), findsOneWidget);

      await tester.tap(key('dv-tab-move-right'));
      await tester.pump();
      expect(paths(c), <String>['/orders', '/reports', '/customers']);
      await tester.tap(key('dv-tab-move-left'));
      await tester.pump();
      expect(paths(c), <String>['/orders', '/customers', '/reports']);
      await tester.tap(key('dv-tab-close'));
      await tester.pump();
      expect(paths(c), <String>['/orders', '/reports']);
      expect(key('dv-tab-actions'), findsNothing, reason: 'done, the menu goes');
    });

    testWidgets('there is no drag', (WidgetTester tester) async {
      await tester.pumpWidget(host(threeTabs(), DVTabPresentation.tv));
      await tester.pump();
      expect(find.byType(Draggable<int>), findsNothing);
    });
  });

  group('on a watch', () {
    testWidgets('tabs stack; a tap chooses; a long press opens the actions', (WidgetTester tester) async {
      final DVTabWorkspaceController c = threeTabs();
      await tester.pumpWidget(host(c, DVTabPresentation.watch));
      await tester.pump();
      final Offset first = tester.getCenter(key('dv-tab-tile-0'));
      final Offset second = tester.getCenter(key('dv-tab-tile-1'));
      expect(second.dy, greaterThan(first.dy), reason: 'stacked, not side by side');
      expect(second.dx, first.dx);

      await tester.tap(key('dv-tab-tile-2'));
      await tester.pump();
      expect(c.activeIndex, 2);

      await tester.longPress(key('dv-tab-tile-2'));
      await tester.pump();
      expect(key('dv-tab-actions'), findsOneWidget);
      await tester.tap(key('dv-tab-move-left'));
      await tester.pump();
      expect(paths(c), <String>['/orders', '/reports', '/customers']);
      expect(find.byType(Draggable<int>), findsNothing);
    });
  });

  testWidgets('the strip is still the strip', (WidgetTester tester) async {
    await tester.pumpWidget(host(threeTabs(), DVTabPresentation.strip));
    await tester.pump();
    expect(find.byType(Draggable<int>), findsNWidgets(3));
    expect(key('dv-tab-tile-0'), findsNothing);
  });
}
