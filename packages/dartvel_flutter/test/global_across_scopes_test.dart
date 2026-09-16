// A global replaced after the scope that read it has gone.
//
// An application started twice in one process -- every integration test
// that pumps the real entrypoint does -- registers its globals again, while
// DV.global still holds the container of the ProviderScope the first run
// mounted and has since disposed. Writing to it threw "Tried to read a
// provider from a ProviderContainer that was already disposed", so the
// second test of the example's link suite never got past main().
//
// And a global registered before any widget read it kept the first value it
// was ever given: its provider closed over that instance rather than reading
// the registry.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Basket {
  const _Basket(this.label);
  final String label;
}

class _ShowsBasket extends StatelessWidget {
  const _ShowsBasket();

  @override
  Widget build(BuildContext context) => Text(
        context.global<_Basket>().label,
        textDirection: TextDirection.ltr,
      );
}

void main() {
  testWidgets('a global can be replaced after its scope is disposed',
      (WidgetTester tester) async {
    DV.global<_Basket>(const _Basket('first run'));
    await tester.pumpWidget(const ProviderScope(child: _ShowsBasket()));
    expect(find.text('first run'), findsOneWidget);

    // The first run's scope goes away.
    await tester.pumpWidget(const SizedBox.shrink());

    // The second run registers again, and mounts a scope of its own.
    DV.global<_Basket>(const _Basket('second run'));
    await tester.pumpWidget(const ProviderScope(child: _ShowsBasket()));
    expect(find.text('second run'), findsOneWidget);

    // And replacing it now still rebuilds what read it.
    DV.global<_Basket>(const _Basket('changed'));
    await tester.pump();
    expect(find.text('changed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
