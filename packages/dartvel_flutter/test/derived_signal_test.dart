// Operating on signals yields a signal. There is no `computed` constructor:
// `a + b` is already reactive, tracks both sources, and can be operated on
// again. Reactivity rides on the sources — reading `a.value` inside the
// derivation subscribes the element, so a source change rebuilds the widget
// and the derivation re-evaluates. These tests drive real widgets to prove
// that chain rather than calling the closure directly.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('adding two signals gives a signal that tracks both',
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
              final sum = a + b;
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

  testWidgets('a signal combines with a plain number', (WidgetTester t) async {
    late DVSignal<int> n;

    await t.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (BuildContext context) {
              n = context.signal(21);
              return Text('${(n * 2).value}');
            },
          ),
        ),
      ),
    );
    expect(find.text('42'), findsOneWidget);

    n.value = 50;
    await t.pump();
    expect(find.text('100'), findsOneWidget);
  });

  testWidgets('derivations compose, because a derivation is a signal',
      (WidgetTester tester) async {
    late DVSignal<int> base;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (BuildContext context) {
              base = context.signal(2);
              // The point of the change: the result of an operation is itself
              // operable, so this needs no separate construct.
              final scaled = (base * base) + 1;
              return Text('v:${scaled.value}');
            },
          ),
        ),
      ),
    );
    expect(find.text('v:5'), findsOneWidget);

    base.value = 3;
    await tester.pump();
    expect(find.text('v:10'), findsOneWidget);
  });

  testWidgets('read() gets the value without subscribing',
      (WidgetTester tester) async {
    late num observed;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (BuildContext context) {
              final n = context.signal(21);
              observed = (n * 2).read();
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(observed, 42);
  });

  testWidgets('comparison yields a boolean signal', (WidgetTester t) async {
    late DVSignal<int> stock;

    await t.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (BuildContext context) {
              stock = context.signal(0);
              final inStock = stock > 0;
              return Text(inStock.value ? 'in stock' : 'sold out');
            },
          ),
        ),
      ),
    );
    expect(find.text('sold out'), findsOneWidget);

    stock.value = 4;
    await t.pump();
    expect(find.text('in stock'), findsOneWidget);
  });

  testWidgets('boolean signals combine with & and |',
      (WidgetTester t) async {
    late DVSignal<bool> agreed;
    late DVSignal<bool> paid;

    await t.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (BuildContext context) {
              agreed = context.signal(false);
              paid = context.signal(false);
              final canShip = agreed & paid;
              return Text(canShip.value ? 'ship' : 'hold');
            },
          ),
        ),
      ),
    );
    expect(find.text('hold'), findsOneWidget);

    agreed.value = true;
    await t.pump();
    expect(find.text('hold'), findsOneWidget);

    paid.value = true;
    await t.pump();
    expect(find.text('ship'), findsOneWidget);
  });

  testWidgets('string signals concatenate', (WidgetTester t) async {
    late DVSignal<String> first;

    await t.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (BuildContext context) {
              first = context.signal('Ada');
              final last = context.signal('Lovelace');
              final full = first + ' ' + last;
              return Text(full.value);
            },
          ),
        ),
      ),
    );
    expect(find.text('Ada Lovelace'), findsOneWidget);

    first.value = 'Grace';
    await t.pump();
    expect(find.text('Grace Lovelace'), findsOneWidget);
  });
}
