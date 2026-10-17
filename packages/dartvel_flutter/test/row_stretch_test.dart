import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A row asked for crossAlign: .stretch gives its children the full height.
/// It used to be turned into .center, so a side rail beside an Expanded page
/// left the page shrink-wrapped and centred vertically: Dartvel
/// Authenticator's vault showed a large empty band above its content. A row
/// that says nothing still centres its children, as headers and button pairs
/// want.
void main() {
  Future<double> topOf(WidgetTester tester, Widget row) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(height: 500, child: row))));
    return tester.getTopLeft(find.byKey(const ValueKey('page'))).dy;
  }

  Widget page() => SingleChildScrollView(child: Container(key: const ValueKey('page'), height: 300));

  testWidgets('explicit stretch fills the height', (tester) async {
    final double top = await topOf(tester, DVBox.row(<Widget>[const SizedBox(width: 80), Expanded(child: page())], crossAlign: DVCrossAlign.stretch));
    expect(top, 0);
    expect(tester.getSize(find.byType(SingleChildScrollView)).height, 500);
  });

  testWidgets('a row that says nothing still centres', (tester) async {
    final double top = await topOf(tester, DVBox.row(<Widget>[const SizedBox(width: 80, height: 10), Expanded(child: SizedBox(height: 300, child: Container(key: const ValueKey('page'))))]));
    expect(top, 100);
  });
}
