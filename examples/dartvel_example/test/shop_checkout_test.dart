// Checkout: a guard that asks for a sign-in, an order that is placed, and a
// status that moves on screen while nobody touches it.
import 'package:dartvel_example/components/shop_ui.dart';
import 'package:dartvel_example/dartvel_client/dartvel_client.dart';
import 'package:dartvel_example/shop/appearance.dart';
import 'package:dartvel_example/shop/cart.dart';
import 'package:dartvel_example/shop/orders.dart';
import 'package:dartvel_example/theme/palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shop_test_support.dart';

void main() {
  tearDown(() => Roastery.instance.stop());

  testWidgets('signed out, checkout asks for a sign-in; the order then moves live',
      (WidgetTester tester) async {
    await pumpShop(tester);

    // Nobody signed in: the Orders tab says so rather than showing nothing.
    await tester.tap(find.widgetWithText(NavigationDestination, 'Orders'));
    await settle(tester);
    expect(find.text('Sign in to see your orders'), findsOneWidget);

    updateCart((Cart cart) => cart.add('huila').add('yirgacheffe'));
    DV.Navigation.navigate(DVRoutes.checkout);
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    expect(DV.Navigation.currentPath, startsWith('/sign-in'));

    // The demo account is filled in; signing in returns to checkout.
    await tester.tap(find.byKey(const Key('sign-in-submit')));
    await tester.pump(const Duration(seconds: 1));
    await settle(tester, 40);
    expect(DV.Navigation.currentPath, '/checkout');
    expect(find.text('\$36.00'), findsWidgets);

    await tester.tap(find.byKey(const Key('place-order')));
    await settle(tester, 40);
    expect(DV.Navigation.currentPath, matches(RegExp(r'^/orders/OAK-\d+$')));
    expect(tester.widget<StatusTracker>(find.byType(StatusTracker)).status,
        'placed');

    // Nobody taps anything: the roastery saves the order and the screen hears.
    await tester.pump(Roastery.instance.step);
    await settle(tester);
    expect(tester.widget<StatusTracker>(find.byType(StatusTracker)).status,
        'roasting');

    // Dark is the same screens from the other palette.
    setAppearance(ThemeMode.dark);
    await settle(tester);
    final BuildContext context = tester.element(find.byType(StatusTracker));
    expect(Theme.of(context).brightness, Brightness.dark);
    expect(Theme.of(context).scaffoldBackgroundColor, Palette.dark.canvas);

    Roastery.instance.stop();
    expect(tester.takeException(), isNull);
  });
}
