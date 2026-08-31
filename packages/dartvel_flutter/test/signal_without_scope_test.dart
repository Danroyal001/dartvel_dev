// context.signal has to work without the application assembling Riverpod.
//
// It called ProviderScope.containerOf(context) directly, which asserts there
// is a ProviderScope above it. Nothing in Dartvel puts one there: a generated
// app is `runApp(createDartvelApp())` over a MaterialApp.router, and Dartvel's
// own site has no ProviderScope at all. So the spec's headline state
// primitive -- `final counter = context.signal(0)` -- threw in the exact
// application shape Dartvel generates.
//
// "Internally powered by Riverpod" is an implementation note. Riverpod being
// an implementation detail means the application never has to know it is
// there, which includes not having to mount its scope.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a signal works with no ProviderScope in the tree',
      (WidgetTester tester) async {
    late DVSignal<int> counter;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(builder: (BuildContext context) {
          counter = context.signal(0);
          return DVText('${counter.value}');
        }),
      ),
    );

    expect(find.text('0'), findsOneWidget);
  });

  testWidgets('and it still rebuilds', (WidgetTester tester) async {
    // Storing a value is half of it. If the fallback container is not the one
    // the listener was registered against, the write lands somewhere nothing
    // is watching and the UI silently never updates -- which is worse than
    // throwing.
    late DVSignal<int> counter;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(builder: (BuildContext context) {
          counter = context.signal(0);
          return DVText('${counter.value}');
        }),
      ),
    );

    counter.value = 7;
    await tester.pump();

    expect(find.text('7'), findsOneWidget);
  });

  testWidgets('two signals in one build stay separate',
      (WidgetTester tester) async {
    late DVSignal<int> first;
    late DVSignal<int> second;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(builder: (BuildContext context) {
          first = context.signal(1);
          second = context.signal(2);
          return DVText('${first.value}-${second.value}');
        }),
      ),
    );

    expect(find.text('1-2'), findsOneWidget);
    second.value = 9;
    await tester.pump();
    expect(find.text('1-9'), findsOneWidget);
  });

  testWidgets('an application that does mount a scope still uses that one',
      (WidgetTester tester) async {
    // The fallback must not shadow a real scope, or overrides an application
    // installed for a test would be ignored.
    late DVSignal<int> counter;
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(builder: (BuildContext context) {
            counter = context.signal(3);
            return DVText('${counter.value}');
          }),
        ),
      ),
    );

    expect(find.text('3'), findsOneWidget);
    expect(counter.container, same(container));
  });

  testWidgets('global works without a scope too', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(builder: (BuildContext context) {
          DV.global<String>('cart');
          return DVText(context.global<String>());
        }),
      ),
    );

    expect(find.text('cart'), findsOneWidget);
  });
  testWidgets('a global of an application type resolves',
      (WidgetTester tester) async {
    // context.global<Cart>() is the spec's reactive global, and it had no
    // test at all. The registry stores Object?, and the provider was being
    // cast to StateProvider<T> -- not a cast Dart permits -- so this threw a
    // TypeError for every type that was not Object?, which is every real use.
    DV.global<_Cart>(const _Cart(2));

    late _Cart seen;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(builder: (BuildContext context) {
          seen = context.global<_Cart>();
          return DVText("${seen.items}");
        }),
      ),
    );

    expect(seen.items, 2);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('replacing a global rebuilds what read it',
      (WidgetTester tester) async {
    DV.global<_Cart>(const _Cart(1));

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(builder: (BuildContext context) {
          return DVText("${context.global<_Cart>().items}");
        }),
      ),
    );
    expect(find.text('1'), findsOneWidget);

    DV.global<_Cart>(const _Cart(5));
    await tester.pump();

    expect(find.text('5'), findsOneWidget);
  });

}

class _Cart {
  const _Cart(this.items);
  final int items;
}
