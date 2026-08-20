// Tab workspaces.
//
// The rules worth getting right are all about what happens to the *selection*
// and to an emptied window, so they live on the controller and are tested
// there. The capability gating matters just as much: reordering works on every
// target, and tear-out must be absent rather than broken where the platform
// cannot do it.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const orders = DVRouteTarget('/orders');
const customers = DVRouteTarget('/customers');
const reports = DVRouteTarget('/reports');

DVTabWorkspaceController threeTabs({DVWindow? window}) =>
    DVTabWorkspaceController(
      tabs: const <DVTab>[DVTab(orders), DVTab(customers), DVTab(reports)],
      window: window,
    );

List<String> paths(DVTabWorkspaceController c) =>
    c.tabs.map((DVTab t) => t.route.path).toList();

void main() {
  setUp(DVWindowManager.reset);
  tearDown(() {
    DVWindowManager.reset();
    DVNativeBridge.unregister('window.open');
    DVNativeBridge.unregister('window.close');
  });

  void grantTearOut() {
    DVWindowManager.capabilityOverride = const DVWindowingCapability(
      multiWindow: true, sameEngine: true, tearOut: true,
    );
    DVNativeBridge.register('window.open', (Object? a) => 'win-1');
    DVNativeBridge.register('window.close', (Object? a) => true);
  }

  group('a tab is a route', () {
    test('two tabs on one route are the same tab', () {
      expect(const DVTab(orders), const DVTab(orders));

      final c = DVTabWorkspaceController(tabs: const <DVTab>[DVTab(orders)]);
      c.add(const DVTab(orders));

      expect(c.tabs.length, 1, reason: 'adding an open route activates it');
    });

    test('the label defaults to the last route segment', () {
      expect(const DVTab(orders).title, 'orders');
      expect(const DVTab(DVRouteTarget('/')).title, '/');
      expect(const DVTab(orders, label: 'Open orders').title, 'Open orders');
    });
  });

  group('reorder works with no windowing at all', () {
    setUp(() {
      DVWindowManager.capabilityOverride = const DVWindowingCapability();
    });

    test('moves a tab and follows it with the selection', () {
      final c = threeTabs()..activate(0);

      c.reorder(0, 2);

      expect(paths(c), <String>['/customers', '/reports', '/orders']);
      expect(c.active, const DVTab(orders),
          reason: 'the moved tab stays selected');
    });

    test('a move past the active tab shifts the selection index', () {
      final c = threeTabs()..activate(1);

      c.reorder(0, 2);

      expect(c.active, const DVTab(customers),
          reason: 'the selected tab is unchanged, only its index moved');
    });

    test('out-of-range and no-op moves change nothing', () {
      final c = threeTabs();
      final before = paths(c);

      c..reorder(-1, 1)..reorder(9, 0)..reorder(1, 1);

      expect(paths(c), before);
    });
  });

  group('closing a tab', () {
    setUp(() {
      DVWindowManager.capabilityOverride = const DVWindowingCapability();
    });

    test('leaves the user on a neighbour, not back at the start', () {
      final c = threeTabs()..activate(1);

      c.removeAt(1);

      expect(c.active, const DVTab(reports));
    });

    test('closing the last tab empties the selection', () {
      final c = DVTabWorkspaceController(tabs: const <DVTab>[DVTab(orders)]);

      c.removeAt(0);

      expect(c.isEmpty, isTrue);
      expect(c.active, isNull);
    });

    test('closing before the active tab keeps the same tab selected', () {
      final c = threeTabs()..activate(2);

      c.removeAt(0);

      expect(c.active, const DVTab(reports));
    });
  });

  group('tear-out is gated, not broken', () {
    test('does nothing where the platform cannot detach', () async {
      DVWindowManager.capabilityOverride =
          const DVWindowingCapability(multiWindow: true); // tearOut false
      final c = threeTabs();

      final window = await c.tearOut(0);

      expect(window, isNull);
      expect(c.tabs.length, 3, reason: 'the tab must not leave the strip');
      expect(c.offersTearOut, isFalse);
      expect(c.offersNewWindow, isTrue,
          reason: 'the explicit affordance is still right to offer');
    });

    test('detaches into a window where it can', () async {
      grantTearOut();
      final c = threeTabs();

      final window = await c.tearOut(0);

      expect(window, isNotNull);
      expect(window!.route, orders);
      expect(paths(c), <String>['/customers', '/reports']);
    });

    test('an emptied workspace window closes itself', () async {
      grantTearOut();
      final host = await DV.Platform.Window.open(reports);
      final c = DVTabWorkspaceController(
        tabs: const <DVTab>[DVTab(orders)],
        window: host,
      );

      await c.tearOut(0);

      expect(c.isEmpty, isTrue);
      expect(host.lifecycle.value, DVWindowLifecycle.closed);
    });

    test('the main workspace does not close when emptied', () async {
      grantTearOut();
      final c = DVTabWorkspaceController(tabs: const <DVTab>[DVTab(orders)]);

      await c.tearOut(0);

      expect(c.isEmpty, isTrue, reason: 'no window to close, and no crash');
    });
  });

  group('re-dock by adoption', () {
    setUp(() {
      DVWindowManager.capabilityOverride = const DVWindowingCapability();
    });

    test('the receiver gains the tab and the source lets it go', () async {
      final source = threeTabs();
      final destination =
          DVTabWorkspaceController(tabs: const <DVTab>[DVTab(DVRouteTarget('/inbox'))]);

      await source.moveTo(destination, 0);

      expect(paths(source), <String>['/customers', '/reports']);
      expect(paths(destination), <String>['/inbox', '/orders']);
    });

    test('adopting a route the receiver already shows does not duplicate',
        () async {
      final source = DVTabWorkspaceController(tabs: const <DVTab>[DVTab(orders)]);
      final destination =
          DVTabWorkspaceController(tabs: const <DVTab>[DVTab(orders)]);

      await source.moveTo(destination, 0);

      expect(destination.tabs.length, 1);
    });
  });

  group('the widget', () {
    setUp(() {
      DVWindowManager.capabilityOverride = const DVWindowingCapability();
    });

    testWidgets('renders a strip and the active tab', (WidgetTester t) async {
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: DVTabWorkspace(initialTabs: <DVTab>[
            DVTab(orders),
            DVTab(customers),
          ]),
        ),
      ));

      expect(find.text('orders'), findsOneWidget);
      expect(find.text('customers'), findsOneWidget);
      expect(find.text('/orders'), findsOneWidget,
          reason: 'the active tab supplies the content');
    });

    testWidgets('tapping a tab activates it', (WidgetTester t) async {
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: DVTabWorkspace(initialTabs: <DVTab>[
            DVTab(orders),
            DVTab(customers),
          ]),
        ),
      ));

      await t.tap(find.byKey(const ValueKey<String>('dv-tab-/customers')));
      await t.pump();

      expect(find.text('/customers'), findsOneWidget);
    });

    testWidgets('an empty workspace says so', (WidgetTester t) async {
      await t.pumpWidget(const MaterialApp(
        home: Scaffold(body: DVTabWorkspace()),
      ));

      expect(find.text('No tabs open.'), findsOneWidget);
    });
  });
}
