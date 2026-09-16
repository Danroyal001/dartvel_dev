// The shop on a desktop or a browser window: a side rail instead of tabs.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'shop_test_support.dart';

void main() {
  testWidgets('a wide window gets a side rail and a multi-column grid',
      (WidgetTester tester) async {
    await pumpShop(tester, physical: const Size(1280, 800), ratio: 1);

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    // Four across: the first and the fourth coffee share a row.
    final Rect first = tester.getRect(find.byKey(const Key('coffee-huila')));
    final Rect fourth =
        tester.getRect(find.byKey(const Key('coffee-harbour-blend')));
    expect(fourth.top, first.top);
    expect(fourth.left, greaterThan(first.right));

    expect(tester.takeException(), isNull);
  });
}
