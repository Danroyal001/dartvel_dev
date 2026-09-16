import 'package:dartvel_example/dartvel_client/dartvel_client.dart';
import 'package:dartvel_example/shop/cart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shop_test_support.dart';

void main() {
  testWidgets('the app opens on the shop, and adding a coffee fills the bag',
      (WidgetTester tester) async {
    await pumpShop(tester, physical: const Size(1280, 900), ratio: 1);

    expect(find.text('This week’s coffee'), findsOneWidget);
    expect(find.text('The shelf'), findsOneWidget);
    // Seeded from the store, not written into the page.
    expect(find.byKey(const Key('coffee-night-shift-decaf')), findsOneWidget);
    // No debug banner in a screenshot of the demo.
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).debugShowCheckedModeBanner,
      isFalse,
    );

    await tester.tap(find.byKey(const Key('add-huila')));
    await settle(tester);
    expect(DV.global<Cart>().quantityOf('huila'), 1);
    expect(find.text('Huila is in your bag'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });
}
