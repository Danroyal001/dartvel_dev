// Spacing on a column.
//
// DVBox.wrapLine took a `spacing` and DVBox.list did not, while both fed the
// same spacing machinery — the column just hard-coded 8. The asymmetry is only
// visible when you write a page with it: every vertical gap in a layout has to
// become a padding modifier on each child, which is the thing DVBox exists to
// avoid.
//
// Found by building the dartvel.dev site with Dartvel rather than by hand.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The height between the first and second child as laid out.
double gapBetweenChildren(WidgetTester tester) {
  final first = tester.getRect(find.byKey(const ValueKey<String>('a')));
  final second = tester.getRect(find.byKey(const ValueKey<String>('b')));
  return second.top - first.bottom;
}

Widget wrap(Widget child) => Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: child),
    );

void main() {
  group('DVBox.list spacing', () {
    testWidgets('it defaults to the same gap it always used',
        (WidgetTester tester) async {
      await tester.pumpWidget(wrap(const DVBox.list(<Widget>[
        SizedBox(key: ValueKey<String>('a'), height: 10, width: 10),
        SizedBox(key: ValueKey<String>('b'), height: 10, width: 10),
      ])));

      expect(gapBetweenChildren(tester), 8);
    });

    testWidgets('a given spacing is the gap that appears',
        (WidgetTester tester) async {
      await tester.pumpWidget(wrap(const DVBox.list(<Widget>[
        SizedBox(key: ValueKey<String>('a'), height: 10, width: 10),
        SizedBox(key: ValueKey<String>('b'), height: 10, width: 10),
      ], spacing: 24)));

      expect(gapBetweenChildren(tester), 24);
    });

    testWidgets('zero spacing means no gap, not the default',
        (WidgetTester tester) async {
      // The case a default-valued parameter gets wrong when it treats 0 as
      // "unset" and substitutes 8.
      await tester.pumpWidget(wrap(const DVBox.list(<Widget>[
        SizedBox(key: ValueKey<String>('a'), height: 10, width: 10),
        SizedBox(key: ValueKey<String>('b'), height: 10, width: 10),
      ], spacing: 0)));

      expect(gapBetweenChildren(tester), 0);
    });
  });
}
