// A header bar is the most common layout on any page: a wordmark and some
// links at the left, one or two links at the right. DVBox could not express
// it -- DVBox.row is mainAxisSize.min with no alignment -- so the site's
// header was a raw Row with a Spacer, and the same for every band that had to
// centre a reading column inside a full-width tinted background.
//
// Two gaps, both of which forced raw Flutter into the one file that should be
// the showcase for not needing it.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> show(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  group('row alignment', () {
    testWidgets('spaceBetween pushes the ends apart',
        (WidgetTester tester) async {
      await show(
        tester,
        DVBox.row(
          const <Widget>[DVText('left'), DVText('right')],
          align: DVAlign.spaceBetween,
          spacing: 0,
        ),
      );

      final double screen = tester.getSize(find.byType(DVBox)).width;
      final double leftEdge = tester.getTopLeft(find.text('left')).dx;
      final double rightEdge = tester.getTopRight(find.text('right')).dx;

      expect(leftEdge, lessThan(4));
      expect(rightEdge, greaterThan(screen - 4));
    });

    testWidgets('the default stays packed to its content',
        (WidgetTester tester) async {
      // Existing rows must not suddenly spread across the window.
      await show(
        tester,
        DVBox.row(const <Widget>[DVText('a'), DVText('b')], spacing: 0),
      );

      // The box itself stays narrow. Measuring the gap between the children
      // instead would have compared the row against its own packed width,
      // which is true whatever the alignment does.
      expect(tester.getSize(find.byType(DVBox)).width, lessThan(200),
          reason: 'a default row must not spread across an 800pt window');
    });

    testWidgets('centre', (WidgetTester tester) async {
      await show(
        tester,
        DVBox.row(
          const <Widget>[DVText('mid')],
          align: DVAlign.center,
          spacing: 0,
        ),
      );

      final Size screen = tester.getSize(find.byType(DVBox));
      final Offset centre = tester.getCenter(find.text('mid'));
      expect((centre.dx - screen.width / 2).abs(), lessThan(2));
    });

    testWidgets('a list takes the same alignment', (WidgetTester tester) async {
      await show(
        tester,
        SizedBox(
          height: 400,
          child: DVBox.list(
            const <Widget>[DVText('top'), DVText('bottom')],
            align: DVAlign.spaceBetween,
            spacing: 0,
          ),
        ),
      );

      expect(tester.getTopLeft(find.text('top')).dy, lessThan(4));
      expect(tester.getBottomLeft(find.text('bottom')).dy, greaterThan(396));
    });
  });

  group('centred in its parent', () {
    testWidgets('a max-width column sits in the middle',
        (WidgetTester tester) async {
      // The band is full width and tinted; the prose inside it is 400 wide
      // and centred. Aligning the child inside the box is a different thing
      // and gives a 400-wide column pinned to the left of a 800 screen.
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await show(
        tester,
        DVBox(
          const DVText('column'),
          const DVModifier().maxWidth(400).centered(),
        ),
      );

      // Measured on the constrained box, not on DVBox: centred() puts a
      // Center inside the DVBox element, and a Center is full width by
      // definition, so DVBox reports 800 however well it centres.
      final Finder column = find.descendant(
        of: find.byType(DVBox),
        matching: find.byType(ConstrainedBox),
      );
      expect((tester.getCenter(column.first).dx - 400).abs(), lessThan(2));
      expect(tester.getSize(column.first).width, lessThanOrEqualTo(400));
    });

    testWidgets('without it the box is not centred',
        (WidgetTester tester) async {
      // The control. If a max-width box centred on its own, centred() would be
      // asserting nothing.
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await show(
        tester,
        Align(
          alignment: Alignment.topLeft,
          child: DVBox(
            const DVText('column'),
            const DVModifier().maxWidth(400),
          ),
        ),
      );

      final Finder column = find.descendant(
        of: find.byType(DVBox),
        matching: find.byType(ConstrainedBox),
      );
      expect(tester.getCenter(column.first).dx, lessThan(300),
          reason: 'without centred() it stays at the left edge');
    });
  });
  group('cross-axis alignment', () {
    testWidgets('a list stretches by default', (WidgetTester tester) async {
      // The existing behaviour, pinned so the new option cannot quietly
      // change it: a column of cards should fill the column it is given.
      await show(
        tester,
        SizedBox(
          width: 400,
          child: DVBox.list(const <Widget>[DVText('a')], spacing: 0),
        ),
      );
      expect(tester.getSize(find.text('a')).width, 400);
    });

    testWidgets('start shrinks to its content', (WidgetTester tester) async {
      // Needed wherever a list is laid out by something that measures it --
      // inside a wrap, a row, or anything unbounded. A stretched column there
      // takes the whole line, so a row of four figures stacks into a column.
      await show(
        tester,
        SizedBox(
          width: 400,
          child: DVBox.list(
            const <Widget>[DVText('a')],
            spacing: 0,
            crossAlign: DVCrossAlign.start,
          ),
        ),
      );
      expect(tester.getSize(find.text('a')).width, lessThan(400));
    });

    testWidgets('a stretched list inside a wrap is what start fixes',
        (WidgetTester tester) async {
      // The concrete bug. Four figures meant to sit in a row, each a small
      // column of number over label.
      await show(
        tester,
        SizedBox(
          width: 600,
          child: Wrap(
            children: <Widget>[
              for (final String n in <String>['1', '2', '3'])
                DVBox.list(
                  <Widget>[DVText(n), DVText('label $n')],
                  spacing: 0,
                  crossAlign: DVCrossAlign.start,
                ),
            ],
          ),
        ),
      );

      // All three on the same line, which is only possible if each shrank.
      final double first = tester.getTopLeft(find.text('1')).dy;
      expect(tester.getTopLeft(find.text('2')).dy, first);
      expect(tester.getTopLeft(find.text('3')).dy, first);
    });

    testWidgets('centre', (WidgetTester tester) async {
      await show(
        tester,
        SizedBox(
          width: 400,
          child: DVBox.list(
            const <Widget>[DVText('a')],
            spacing: 0,
            crossAlign: DVCrossAlign.center,
          ),
        ),
      );
      final Offset centre = tester.getCenter(find.text('a'));
      final double boxCentre = tester.getCenter(find.byType(DVBox)).dx;
      expect((centre.dx - boxCentre).abs(), lessThan(2));
    });
  });

}