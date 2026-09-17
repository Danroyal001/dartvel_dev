// Tabs from files through the example's real generated router.
//
// lib/pages/(tabs) has a DartvelTabsLayout naming /, /orders, /saved and
// /account, with /coffee/:slug and /cart beside the shop. Each tab keeps its
// own stack and its state, and back -- the iOS edge swipe and the Android
// button -- pops inside the tab on screen before anything else.
import 'package:dartvel_example/dartvel_client/dartvel_client.dart';
import 'package:dartvel_example/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  tearDown(DVNavigation.detach);

  testWidgets('a stack per tab, state kept, back pops inside the tab', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    // A phone, so the tabs are along the bottom and the page runs to the
    // left edge the back swipe starts from.
    tester.view
      ..physicalSize = const Size(1179, 2556)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    try {
      configureDartvelExample();
      final GoRouter router = createDartvelRouter();
      addTearDown(router.dispose);
      router.go('/');
      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)),
      );
      await settle(tester);
      expect(find.byKey(const Key('coffee-huila')), findsOneWidget);

      // A coffee, pushed inside the Shop tab.
      DV.Navigation.navigate(DVRoutes.coffee(slug: 'huila'));
      await settle(tester);
      expect(find.byKey(const Key('add-to-bag')), findsOneWidget);

      // The iOS edge swipe goes back to the shelf, still in the tab.
      final TestGesture swipe = await tester.startGesture(const Offset(2, 300));
      await swipe.moveBy(const Offset(500, 0));
      await swipe.up();
      await settle(tester);
      expect(find.byKey(const Key('add-to-bag')), findsNothing);
      expect(find.byKey(const Key('coffee-huila')), findsOneWidget);
      expect(DV.Navigation.currentPath, '/');

      // Into a coffee again, then over to Saved and save it from nowhere:
      // Saved shows what the Shop tab's page saved.
      DV.Navigation.navigate(DVRoutes.coffee(slug: 'nyeri'));
      await settle(tester);
      await tester.ensureVisible(find.byKey(const Key('save-coffee')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('save-coffee')));
      await settle(tester);
      await tester.tap(find.text('Saved').last);
      await settle(tester);
      expect(DV.Navigation.currentPath, '/saved');
      expect(find.byKey(const Key('coffee-nyeri')), findsOneWidget);

      // Back to Shop: still on the coffee it was left on.
      await tester.tap(find.text('Shop').last);
      await settle(tester);
      expect(find.byKey(const Key('add-to-bag')), findsOneWidget);
      expect(DV.Navigation.currentPath, '/coffee/nyeri');

      // The Android back button pops inside the tab too.
      expect(await tester.binding.handlePopRoute(), isTrue);
      await settle(tester);
      expect(find.byKey(const Key('coffee-nyeri')), findsOneWidget);
      expect(DV.Navigation.currentPath, '/');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
