// Tabs from files through the example's real generated router.
//
// lib/pages/(tabs) has a DartvelTabsLayout naming /library and /saved, and
// /library/:book beside the list. Each tab keeps its own stack and its
// state, and back -- the iOS edge swipe and the Android button -- pops inside
// the tab on screen before anything else.
import 'package:dartvel_example/dartvel_client/dartvel_client.dart';
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
    try {
      final GoRouter router = createDartvelRouter();
      addTearDown(router.dispose);
      router.go('/library');
      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)),
      );
      await settle(tester);
      expect(find.text('Book dune'), findsOneWidget);

      // A detail page, pushed inside the Library tab.
      DV.Navigation.navigate(DVRoutes.libraryBook(book: 'dune'));
      await settle(tester);
      expect(find.text('Reading dune'), findsOneWidget);

      // The iOS edge swipe goes back to the list, still in the tab.
      final TestGesture swipe = await tester.startGesture(const Offset(2, 300));
      await swipe.moveBy(const Offset(500, 0));
      await swipe.up();
      await settle(tester);
      expect(find.text('Reading dune'), findsNothing);
      expect(find.text('Book dune'), findsOneWidget);
      expect(DV.Navigation.currentPath, '/library');

      // Into the book again, then over to the Saved tab and save twice.
      DV.Navigation.navigate(DVRoutes.libraryBook(book: 'emma'));
      await settle(tester);
      await tester.tap(find.text('Saved').last);
      await settle(tester);
      await tester.tap(find.byKey(const Key('save-button')));
      await tester.tap(find.byKey(const Key('save-button')));
      await settle(tester);
      expect(find.text('Saved 2 times'), findsOneWidget);

      // Back to Library: still on the book it was left on.
      await tester.tap(find.text('Library').last);
      await settle(tester);
      expect(find.text('Reading emma'), findsOneWidget);
      expect(DV.Navigation.currentPath, '/library/emma');

      // The Android back button pops inside the tab too.
      expect(await tester.binding.handlePopRoute(), isTrue);
      await settle(tester);
      expect(find.text('Book emma'), findsOneWidget);
      expect(DV.Navigation.currentPath, '/library');

      // And Saved kept its count while Library was on screen.
      await tester.tap(find.text('Saved').last);
      await settle(tester);
      expect(find.text('Saved 2 times'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
