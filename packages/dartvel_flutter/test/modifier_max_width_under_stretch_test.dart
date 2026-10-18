// `.maxWidth()` is a promise about the box, and a column that stretches its
// children must not break it.
//
// The SigmaDev site set `.maxWidth(680)` on its lead paragraph so a line stays
// readable, and at 1366 pixels the paragraph ran the full 1,270: the page
// column stretches its children, a stretched child gets a tight width, and a
// tight width beats any maximum. Nothing failed and nothing overflowed; the
// text was just three lines of 150 characters.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      width: 400,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[child]),
    ),
  ),
);

void main() {
  testWidgets('a max width holds inside a column that stretches', (tester) async {
    await tester.pumpWidget(_host(DVBox(const Text('readable'), const DVModifier().maxWidth(100))));
    expect(tester.getSize(find.byType(DVBox)).width, 400, reason: 'the slot is the column width');
    expect(tester.getSize(find.byType(Container).last).width, 100, reason: 'the box keeps its maximum');
  });

  testWidgets('the bounded box sits at the start edge, in either direction', (tester) async {
    await tester.pumpWidget(_host(DVBox(const Text('left'), const DVModifier().maxWidth(100))));
    expect(tester.getTopLeft(find.text('left')).dx, 0);
    await tester.pumpWidget(_host(Directionality(
      textDirection: TextDirection.rtl,
      child: DVBox(const Text('right'), const DVModifier().maxWidth(100)),
    )));
    expect(tester.getTopRight(find.text('right')).dx, 400);
  });

  testWidgets('centered still centres a bounded box', (tester) async {
    await tester.pumpWidget(_host(DVBox(const SizedBox(width: 1000, height: 10), const DVModifier().maxWidth(100).centered())));
    expect(tester.getTopLeft(find.byType(SizedBox).last).dx, 150);
  });

  testWidgets('under loose constraints nothing changes', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: DVBox(const SizedBox(width: 50, height: 10), const DVModifier().maxWidth(100)))),
    ));
    expect(tester.getSize(find.byType(DVBox)).width, 50);
  });

  testWidgets('text in a stretched column wraps at the maximum', (tester) async {
    await tester.pumpWidget(_host(DVText('word ' * 12).modifier(const DVModifier().maxWidth(120))));
    expect(tester.getSize(find.byType(RichText).first).width, lessThanOrEqualTo(120));
  });
}
