// A child that takes the room the others leave.
//
// Dev Launcher's app drawer is a header (handle, title, search) over a list
// that scrolls. With no way to say "the list gets the rest", the header was
// given a fixed height and the list the screen minus it -- and the header's
// contents, which grow with the reader's font size, overflowed it by 22
// pixels at the default size. fill() is that missing sentence: in a
// DVBox.list it takes the height left, in a DVBox.row the width.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const Key restKey = Key('rest');

Widget framed(Widget child) => MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: 400, height: 600, child: child),
      ),
    );

void main() {
  testWidgets('in a list, the filling child gets the height left',
      (WidgetTester tester) async {
    await tester.pumpWidget(framed(DVBox.list(<Widget>[
      DVBox(const DVText('header'), const DVModifier().height(120)),
      KeyedSubtree(
        key: restKey,
        child: DVBox(const DVText('rest'), const DVModifier().fill()),
      ),
    ], spacing: 0)));

    expect(tester.getSize(find.byKey(restKey)).height, 480);
    expect(tester.getTopLeft(find.byKey(restKey)).dy, 120);
  });

  testWidgets('the header keeps the height its contents need',
      (WidgetTester tester) async {
    // Nothing fixed: the header is as tall as what is in it, whatever the
    // font size, and the list takes the rest without anything overflowing.
    await tester.pumpWidget(framed(DVBox.list(<Widget>[
      DVBox.list(<Widget>[
        for (int line = 0; line < 6; line++) DVText('line $line'),
      ]),
      KeyedSubtree(
        key: restKey,
        child: DVBox(
          DVBox.list(<Widget>[
            for (int row = 0; row < 80; row++) DVText('app $row'),
          ]).scrollable(),
          const DVModifier().fill(),
        ),
      ),
    ], spacing: 0)));

    expect(tester.takeException(), isNull);
    final Rect rest = tester.getRect(find.byKey(restKey));
    expect(rest.bottom, 600);
    expect(rest.top, greaterThan(0));
  });

  testWidgets('in a row, the filling child gets the width left',
      (WidgetTester tester) async {
    await tester.pumpWidget(framed(DVBox.row(<Widget>[
      DVBox(const DVText('icon'), const DVModifier().width(100)),
      DVBox(const DVText('label'), const DVModifier().fill()),
    ], spacing: 0, align: DVAlign.start)));

    final Finder rest = find.ancestor(of: find.text('label'), matching: find.byType(Expanded));
    expect(tester.getSize(rest).width, 300);
  });

  test('fill survives a merge and counts as box styling', () {
    expect(
      const DVModifier().fill().merge(const DVModifier().padding(4)).fillValue,
      isTrue,
    );
    expect(const DVModifier().fill().hasBoxStyling, isTrue);
  });
}
