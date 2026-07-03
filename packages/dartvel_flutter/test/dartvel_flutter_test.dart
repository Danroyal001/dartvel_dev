import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mix/mix.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';

void main() {
  testWidgets('DVBox and DVText render correctly with style modifiers', (WidgetTester tester) async {
    final style = const DVStyleModifier()
        .padding(12)
        .backgroundColor(Colors.blue)
        .color(Colors.white);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DVBox(
            modifier: style,
            child: const DVText('Save'),
          ),
        ),
      ),
    );

    expect(find.byType(DVBox), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('DVSignal reacts to state updates within ProviderScope', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, child) {
                final counter = context.signal(0);
                return Column(
                  children: [
                    Text('Count: ${counter.value}'),
                    ElevatedButton(
                      onPressed: () {
                        counter.value = counter.value + 1;
                      },
                      child: const Text('Increment'),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('Count: 0'), findsOneWidget);

    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();

    expect(find.text('Count: 1'), findsOneWidget);
  });
}
