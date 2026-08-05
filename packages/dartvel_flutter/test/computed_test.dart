// `context.computed(...)` is the spec's derived-signal API. Reactivity rides
// on the source signals: reading `a.value` inside the computation subscribes
// the element, so a source change rebuilds the widget and the computed
// re-evaluates. These tests drive real widgets to prove that chain.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('computed derives from signals and stays reactive',
      (WidgetTester tester) async {
    late DVSignal<int> a;
    late DVSignal<int> b;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (BuildContext context) {
              a = context.signal(1);
              b = context.signal(2);
              final sum = context.computed(() => a.value + b.value);
              return Text('sum:${sum.value}');
            },
          ),
        ),
      ),
    );
    expect(find.text('sum:3'), findsOneWidget);

    a.value = 10;
    await tester.pump();
    expect(find.text('sum:12'), findsOneWidget);

    b.value = 5;
    await tester.pump();
    expect(find.text('sum:15'), findsOneWidget);
  });

  testWidgets('read() returns the current value without extra ceremony',
      (WidgetTester tester) async {
    late int observed;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (BuildContext context) {
              final n = context.signal(21);
              final doubled = context.computed(() => n.value * 2);
              observed = doubled.read();
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(observed, 42);
  });

  testWidgets('a computed of a computed follows the chain',
      (WidgetTester tester) async {
    late DVSignal<int> base;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (BuildContext context) {
              base = context.signal(2);
              final squared = context.computed(() => base.value * base.value);
              final label = context.computed(() => 'sq:${squared.value}');
              return Text(label.value);
            },
          ),
        ),
      ),
    );
    expect(find.text('sq:4'), findsOneWidget);

    base.value = 3;
    await tester.pump();
    expect(find.text('sq:9'), findsOneWidget);
  });
}
