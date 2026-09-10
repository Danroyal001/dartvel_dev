// A feature card is a summary, and summaries are one line.
//
// This card has been three things. It carried the whole record, six thousand
// characters of it, and the grid had one card twenty-five times the height of
// the one beside it. Then it carried a folded record, which was a wall with a
// lid on. Then a paragraphed one with headings, which was a tidier wall.
//
// Every version was an answer to "how do we lay this text out", and the
// question was wrong. Thirty-six cards in a grid are there to be compared, and
// nobody compares four hundred characters against four hundred characters.
// Laravel gives each of its products a name and about a dozen words and puts
// the record in the docs; the record here is further down the same page, under
// a heading, where somebody who wants it has said so by scrolling to it.
//
// So what is asserted now is that the card stays a card whatever it is handed.
import 'package:dartvel_site/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final String _long =
    'One layout primitive with a fluent modifier chain, and a great deal '
    'more to say about it than fits in a card. ' * 30;

const String _short = 'A file under lib/pages is a route.';

const String _twoHalves = 'Present: the policy, the state machine and the '
    'enforcement matrix. Absent: iPadOS, Tizen and webOS.';

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
  testWidgets('a card barely knows how long its record is', (
    WidgetTester tester,
  ) async {
    // The property, rather than a number I picked. What made the old grid
    // unreadable was one card twenty-five times the height of its neighbour,
    // so what matters is that 3,900 characters and 34 produce cards of about
    // the same size -- not that either is under some particular figure.
    await pump(tester, _short);
    final double small = tester.getSize(find.byType(FeatureRow)).height;

    await pump(tester, _long);
    final double large = tester.getSize(find.byType(FeatureRow)).height;

    // A hundred and fourteen times the text, and at most two more lines of it.
    expect(large - small, lessThan(80));
  });

  testWidgets('and it is the opening sentence, not a cut', (
    WidgetTester tester,
  ) async {
    await pump(tester, _long);

    // Whole, and ending in a full stop -- not an ellipsis where a clamp fell.
    expect(
      find.text(
        'One layout primitive with a fluent modifier chain, and a great deal '
        'more to say about it than fits in a card.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a record that is already one sentence is left alone', (
    WidgetTester tester,
  ) async {
    await pump(tester, _short);
    expect(find.text(_short), findsOneWidget);
  });

  testWidgets('the Present label never reaches the card', (
    WidgetTester tester,
  ) async {
    // It is a heading in the record further down the page. On a card it would
    // be a word printed for a reader who has no second half to compare it to.
    await pump(tester, _twoHalves);

    expect(find.textContaining('Present:'), findsNothing);
    expect(find.textContaining('Absent:'), findsNothing);
    expect(
      find.text('The policy, the state machine and the enforcement matrix.'),
      findsOneWidget,
    );
  });

  testWidgets('nothing on a card claims there is more behind it', (
    WidgetTester tester,
  ) async {
    // The control that used to open the record is gone with the record. An
    // affordance that opens nothing is worse than no affordance.
    await pump(tester, _long);

    expect(find.text('Read the whole record'), findsNothing);
    expect(find.text('Show less'), findsNothing);
  });
}
