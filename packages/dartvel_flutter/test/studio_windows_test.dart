// The Studio window inspector: every window the application has open,
// with a way to close one, following the window manager as windows come
// and go. Free, like the rest of Studio: what is open is not a Pro secret.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder key(String k) => find.byKey(ValueKey<String>(k));

void main() {
  late SqliteDVDatabaseAdapter database;
  setUp(() {
    database = SqliteDVDatabaseAdapter.memory();
    DV.Database.configure(database);
    DVPageStore.resetCache();
    DVWindowManager.reset();
    DVWindowManager.capabilityOverride = const DVWindowingCapability(multiWindow: true, sameEngine: true, tearOut: true);
    int n = 0;
    DVNativeBridge.register('window.open', (Object? a) => 'win-${++n}');
    DVNativeBridge.register('window.close', (Object? a) => true);
  });
  tearDown(() {
    DVWindowManager.reset();
    DVNativeBridge.unregister('window.open');
    DVNativeBridge.unregister('window.close');
    database.close();
    DVPageStore.resetCache();
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: Material(child: DVStudioScreen())));
    await tester.pumpAndSettle();
    await tester.tap(key('dv-studio-section-windows'));
    await tester.pumpAndSettle();
  }

  testWidgets('the Windows tab is part of free Studio, and starts empty', (WidgetTester tester) async {
    await open(tester);
    expect(key('dv-studio-windows'), findsOneWidget);
    expect(find.textContaining('No windows'), findsOneWidget);
  });

  testWidgets('lists every open window with its route and kind, and follows opens and closes', (WidgetTester tester) async {
    await open(tester);
    final DVWindow orders = await DV.Platform.Window.open(const DVRouteTarget('/orders'));
    await DV.Platform.Window.open(const DVRouteTarget('/stock'));
    await tester.pumpAndSettle();

    expect(key('dv-studio-window-${orders.nativeId}'), findsOneWidget);
    expect(find.textContaining('/orders'), findsOneWidget);
    expect(find.textContaining('/stock'), findsOneWidget);
    expect(find.textContaining(orders.kind.name), findsWidgets);

    await tester.tap(key('dv-studio-window-close-${orders.nativeId}'));
    await tester.pumpAndSettle();
    expect(find.textContaining('/orders'), findsNothing);
    expect(DV.Platform.Window.all.value.map((DVWindow w) => w.route.path), <String>['/stock']);
  });
}
