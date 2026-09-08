// The features page is a comparison, and a card that runs for a thousand
// pixels stops it being one.
//
// Each entry carries the repository's own record of what is built, and some
// of those records are three thousand words. Printed in full they made a grid
// where one card was twenty-five times the height of the one beside it: half
// the page was a wall of prose and the other half was the white space left
// over next to it. Nobody compares thirty-six things that way, and nobody
// reads three thousand words to find out whether routing is done.
//
// So the record is folded, not cut. The opening sentences are what a reader
// scanning the page needs, and the whole thing is one tap away for the reader
// who wants it.
import 'package:dartvel_site/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final String _long =
    'One layout primitive with a fluent modifier chain, and a great deal '
    'more to say about it than fits in a card. ' * 30;

const String _short = 'A file under lib/pages is a route.';

Future<void> pump(WidgetTester tester, String body) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: FeatureRow(
                area: 'UI',
                surface: 'DVBox and DVText',
                body: body,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a long record is folded, and the card stays a card',
      (WidgetTester tester) async {
    await pump(tester, _long);

    // The body is 3,900 characters. Unfolded in a 440 point column that is
    // most of a screen; folded it has to be something you can put beside
    // another one.
    expect(tester.getSize(find.byType(FeatureRow)).height, lessThan(260));
  });

  testWidgets('and it says so, and opens', (WidgetTester tester) async {
    await pump(tester, _long);
    final double folded = tester.getSize(find.byType(FeatureRow)).height;

    final Finder more = find.text('Read the whole record');
    expect(more, findsOneWidget);

    await tester.tap(more);
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(FeatureRow)).height,
        greaterThan(folded * 2));
    expect(find.text('Show less'), findsOneWidget);
  });

  testWidgets('and folds again', (WidgetTester tester) async {
    await pump(tester, _long);
    final double folded = tester.getSize(find.byType(FeatureRow)).height;

    await tester.tap(find.text('Read the whole record'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Show less'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show less'));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(FeatureRow)).height, folded);
  });

  // The control is the promise that there is more. Offering it over a record
  // that is already whole is a promise the tap cannot keep.
  testWidgets('a record that already fits has nothing to open',
      (WidgetTester tester) async {
    await pump(tester, _short);

    expect(find.text('Read the whole record'), findsNothing);
    expect(find.text('Show less'), findsNothing);
    expect(find.text(_short), findsOneWidget);
  });
}
