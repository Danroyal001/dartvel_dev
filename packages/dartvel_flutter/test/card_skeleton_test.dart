// A card list or grid that is loading is the shape of what is coming.
//
// Error, Empty, and Loading States: skeletons are derived from the model's
// field layout, so the placeholder is the shape of what is coming rather than
// a spinner. The table had one; the generated card List and Grid did not, so
// a list still loading rendered as if it were empty.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _show(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  await tester.pump();
}

void main() {
  tearDown(DV.I18n.reset);

  testWidgets('one placeholder line per field, per card', (WidgetTester tester) async {
    await _show(
      tester,
      const DVSkeletonCards(fields: <String>['title', 'author', 'publishedAt'], count: 4),
    );
    expect(find.byType(DVSkeletonLine), findsNWidgets(4 * 3));
  });

  testWidgets('a grid lays its cards out in the columns asked for', (WidgetTester tester) async {
    await _show(
      tester,
      const DVSkeletonCards(fields: <String>['title'], count: 4, columns: 2),
    );
    final double first = tester.getTopLeft(find.byType(DVSkeletonLine).at(0)).dy;
    final double second = tester.getTopLeft(find.byType(DVSkeletonLine).at(1)).dy;
    final double third = tester.getTopLeft(find.byType(DVSkeletonLine).at(2)).dy;
    expect(second, first, reason: 'the first two cards share a row');
    expect(third, greaterThan(first), reason: 'the third starts the next row');
  });

  testWidgets('a screen reader is told it is loading, once, and never that it is empty',
      (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await _show(tester, const DVSkeletonCards(fields: <String>['title', 'body']));
    expect(find.bySemanticsLabel('Loading'), findsOneWidget);
    expect(find.text('Nothing here yet'), findsNothing);
    semantics.dispose();
  });

  testWidgets('the loading words are a framework string', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    DV.I18n.load(const DVTranslationCatalog(
      locale: LocaleTag.frFR,
      messages: <DVTranslationKey, String>{
        DVFrameworkStrings.collectionLoading: 'Chargement',
      },
    ));
    DV.I18n.useLocale(LocaleTag.frFR);
    await _show(tester, const DVSkeletonCards(fields: <String>['title']));
    expect(find.bySemanticsLabel('Chargement'), findsOneWidget);
    semantics.dispose();
  });
}
