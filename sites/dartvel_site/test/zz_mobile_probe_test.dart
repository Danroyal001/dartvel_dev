import 'package:dartvel_site/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (String name, Size size) in <(String, Size)>[
    ('iPhone SE', Size(375, 667)),
    ('iPhone 14', Size(390, 844)),
    ('Pixel 7', Size(412, 915)),
    ('iPad', Size(820, 1180)),
  ]) {
    testWidgets('$name renders without overflow', (WidgetTester tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: const FeaturesPageGeneratedPage()),
      ));
      await tester.pump();
      final Object? error = tester.takeException();
      if (error != null) print('OVERFLOW $name: ${error.toString().split("\n").first}');
      expect(error, isNull, reason: '$name overflowed');
    });
  }
}
