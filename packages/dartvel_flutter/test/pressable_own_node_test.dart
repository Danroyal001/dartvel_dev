// A tappable box is a control of its own, wherever it sits.
//
// sigmadev.digital, 26 Nov 2026: a "Buy this tool" button (a DVBox with
// .onTap()) inside a page column that is a semantics group did not get a
// node of its own. Its button role and its tap merged up into the column,
// so the whole page read as one button, the button had no box of its own in
// the server-rendered page, and a click on it landed on the column.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a tappable DVBox inside a group is its own button node, and the group stays a group', (tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Semantics(
          container: true,
          child: Column(children: [
            const Text('Customer acquisition cost'),
            DVBox(
              const Text('Buy this tool'),
              DVModifier().semanticButton().semanticLabel('Buy this tool').tooltip('Buy this tool').onTap(() => taps++),
            ),
            const Text('Pay by bank transfer.'),
          ]),
        ),
      ),
    ));
    final SemanticsNode button = tester.getSemantics(find.text('Buy this tool'));
    expect(button.label, 'Buy this tool');
    expect(button.flagsCollection.isButton, isTrue);
    expect(button.label, isNot(contains('Customer acquisition cost')), reason: 'merged into the group');
    final SemanticsNode group = tester.getSemantics(find.text('Customer acquisition cost'));
    expect(group.flagsCollection.isButton, isFalse, reason: 'the group became a button');
    await tester.tap(find.text('Buy this tool'));
    expect(taps, 1);
    semantics.dispose();
  });
}
