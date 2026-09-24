// A row in a Studio list is one thing, and it is called what it says.
//
// The title, the subtitle and the icon were three loose nodes in the
// semantics tree with nothing saying they belong together, so a screen
// reader read "table rows", "Product", "9 fields" and never said the row
// could be opened. On the web that also left the row with no accessible
// name: its node's text was the whole line, "Product 9 fields", which is
// why the Studio capture could not find the model it was told to open and
// photographed the first one instead.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpRow(
  WidgetTester tester, {
  String? subtitle,
  VoidCallback? onTap,
}) =>
    tester.pumpWidget(MaterialApp(
      home: Material(
        child: DVStudioListRow(
          title: 'Product',
          subtitle: subtitle,
          icon: Icons.table_rows_outlined,
          onTap: onTap,
        ),
      ),
    ));

void main() {
  testWidgets('the row is one node, named by its title', (tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await pumpRow(tester, subtitle: '9 fields', onTap: () {});

    // Exactly what a caller looking for the Product row should find: one
    // node, called Product, and not "Product 9 fields".
    expect(
      tester.getSemantics(find.bySemanticsLabel('Product')),
      isNotNull,
    );
    expect(find.bySemanticsLabel('Product 9 fields'), findsNothing);
    handle.dispose();
  });

  testWidgets('what it says beside the title is its value', (tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await pumpRow(tester, subtitle: '9 fields', onTap: () {});

    expect(
      tester.getSemantics(find.bySemanticsLabel('Product')).value,
      '9 fields',
    );
    handle.dispose();
  });

  testWidgets('a row that opens something says it is a button',
      (tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await pumpRow(tester, subtitle: '9 fields', onTap: () {});

    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Product'))
          .hasFlag(SemanticsFlag.isButton),
      isTrue,
    );
    handle.dispose();
  });

  testWidgets('a row with nothing to open is not a button', (tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await pumpRow(tester, subtitle: '9 fields');

    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Product'))
          .hasFlag(SemanticsFlag.isButton),
      isFalse,
    );
    handle.dispose();
  });

  testWidgets('it carries an identifier automation can find it by',
      (tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await pumpRow(tester, subtitle: '9 fields', onTap: () {});

    // On the web this becomes a flt-semantics-identifier attribute, which is
    // exact. A label is not: Flutter web renders the label and the value into
    // the element, so the row's own text reads "Product 9 fields", and the
    // Studio capture looking for "Product" found nothing.
    expect(
      tester.getSemantics(find.bySemanticsLabel('Product')).identifier,
      'Product',
    );
    handle.dispose();
  });

  testWidgets('tapping it still runs the callback', (tester) async {
    int taps = 0;
    await pumpRow(tester, subtitle: '9 fields', onTap: () => taps++);

    await tester.tap(find.byType(DVStudioListRow));
    expect(taps, 1);
  });
}
