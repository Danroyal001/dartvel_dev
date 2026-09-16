// A deep link straight to a page pushed inside a tab.
//
// The tab's stack is built whole: the coffee on top and the shelf under it,
// covered. Both are selectable pages, and a covered page is not laid out --
// which the selection area asked the size of anyway.
import 'package:dartvel_example/dartvel_client/dartvel_client.dart';
import 'package:dartvel_example/main.dart';
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

  testWidgets('opens on the coffee, with the shelf under it to go back to', (
    WidgetTester tester,
  ) async {
    configureDartvelExample();
    final GoRouter router = createDartvelRouter();
    addTearDown(router.dispose);
    router.go('/coffee/yirgacheffe');
    await tester.pumpWidget(
      ProviderScope(child: MaterialApp.router(routerConfig: router)),
    );
    await settle(tester);

    expect(find.text('Add to bag · \$19.00'), findsOneWidget);
    expect(DV.Navigation.canGoBack, isTrue);
    DV.Navigation.back<void>();
    await settle(tester);
    expect(find.byKey(const Key('coffee-yirgacheffe')), findsOneWidget);
    expect(DV.Navigation.currentPath, '/');
  });
}
