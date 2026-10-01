import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('Studio preserves the app theme in $brightness', (
      tester,
    ) async {
      final theme = ThemeData(
        brightness: brightness,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF008577),
          brightness: brightness,
        ),
        scaffoldBackgroundColor: const Color(0xFF182930),
      );
      ThemeData? observed;
      ThemeData? inherited;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(builder: (context) {
            inherited = Theme.of(context);
            return DVStudioFrame(
            title: 'Custom project',
            home: Builder(
              builder: (context) {
                observed = Theme.of(context);
                return const Scaffold(body: Text('Studio'));
              },
            ),
          );
          }),
        ),
      );
      await tester.pumpAndSettle();
      expect(observed, inherited);
    });
  }
}
