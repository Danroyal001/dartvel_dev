// The shop on a phone: tabs at the bottom, the catalogue from the store, and
// a coffee's page adding to the bag.
import 'package:dartvel_example/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shop_test_support.dart';

void main() {
  testWidgets('a phone gets the catalogue, bottom tabs and a working bag',
      (WidgetTester tester) async {
    await pumpShop(tester);

    // Navigation for a thumb, not a rail.
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    for (final String tab in <String>['Shop', 'Orders', 'Saved', 'Account']) {
      expect(find.widgetWithText(NavigationDestination, tab), findsOneWidget);
    }

    // The catalogue, read from the store rather than typed into the page.
    expect(find.byKey(const Key('coffee-huila')), findsOneWidget);
    expect(find.text('Yirgacheffe'), findsWidgets);

    // The links the device suites tap are on screen before any scrolling.
    final Rect screen = Offset.zero & tester.view.physicalSize / phoneRatio;
    for (final String link in <String>['link-about', 'link-pricing']) {
      final Rect rect = tester.getRect(find.byKey(Key(link)));
      expect(screen.contains(rect.center), isTrue,
          reason: '$link is off screen on a phone');
    }

    // A filter is a signal: only dark roasts are left.
    await tester.tap(find.byKey(const Key('roast-dark')));
    await settle(tester);
    expect(find.byKey(const Key('coffee-harbour-blend')), findsOneWidget);
    expect(find.byKey(const Key('coffee-nyeri')), findsNothing);
    await tester.tap(find.byKey(const Key('roast-all')));
    await settle(tester);

    // A coffee's page, pushed inside the Shop tab.
    DV.Navigation.navigate(DVRoutes.coffee(slug: 'nyeri'));
    await settle(tester);
    expect(DV.Navigation.currentPath, '/coffee/nyeri');
    expect(find.text('Add to bag · \$21.00'), findsOneWidget);

    // The button's price is quantity times price: a derived signal.
    await tester.ensureVisible(find.byKey(const Key('quantity-increase')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('quantity-increase')));
    await settle(tester);
    expect(find.text('Add to bag · \$42.00'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('add-to-bag')));
    await tester.tap(find.byKey(const Key('add-to-bag')));
    await settle(tester);
    expect(find.byKey(const Key('bag-count')), findsWidgets);
    expect(
      find.descendant(
        of: find.byKey(const Key('bag-count')).first,
        matching: find.text('2'),
      ),
      findsOneWidget,
    );

    // The bag itself, with shipping free over the line.
    DV.Navigation.navigate(DVRoutes.cart);
    await settle(tester);
    expect(find.text('Nyeri'), findsWidgets);
    expect(find.text('\$42.00'), findsWidgets);
    expect(find.text('Free'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });
}
