// A box moved whole, which the chain could not do.
//
// Dev Launcher's app drawer is a full-screen panel that sits below the screen
// when closed and follows the finger up. With no way to move a box, it was
// pushed down by a top margin -- which leaves the panel no height, so Flutter
// squeezed it to nothing and reported an overflow on every frame it was
// closed. An offset moves the box after layout: it keeps its size, its
// children keep theirs, and taps land where it is drawn.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const Key panelKey = Key('panel');

Widget panelApp(DVModifier modifier) => MaterialApp(
  home: DVBox.stack(<Widget>[
    KeyedSubtree(
      key: panelKey,
      child: DVBox(const DVText('panel'), modifier.width(200).height(300)),
    ),
  ]),
);

void main() {
  testWidgets('an offset moves the box and keeps its size', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(panelApp(const DVModifier()));
    final Offset before = tester.getTopLeft(find.text('panel'));

    await tester.pumpWidget(panelApp(const DVModifier().offset(30, 500)));
    final Offset after = tester.getTopLeft(find.text('panel'));

    expect(after - before, const Offset(30, 500));
    expect(tester.getSize(find.byKey(panelKey)), const Size(200, 300));
    expect(
      tester.takeException(),
      isNull,
      reason: 'moved off-screen whole, nothing squeezed or overflowing',
    );
  });

  testWidgets('a tap lands on the box where it is drawn', (
    WidgetTester tester,
  ) async {
    int taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DVBox.stack(<Widget>[
          DVBox(
            const DVText('target'),
            const DVModifier()
                .width(100)
                .height(100)
                .offset(0, 200)
                .onTap(() => taps++),
          ),
        ]),
      ),
    );
    await tester.tapAt(const Offset(50, 250));
    expect(taps, 1);
  });

  testWidgets('an animated box slides to its new offset', (
    WidgetTester tester,
  ) async {
    DVModifier at(double dy) => const DVModifier()
        .offset(0, dy)
        .animate(const Duration(milliseconds: 200));
    await tester.pumpWidget(panelApp(at(0)));
    final double start = tester.getTopLeft(find.text('panel')).dy;

    await tester.pumpWidget(panelApp(at(400)));
    await tester.pump(const Duration(milliseconds: 100));
    final double midway = tester.getTopLeft(find.text('panel')).dy;
    expect(midway, greaterThan(start));
    expect(midway, lessThan(start + 400), reason: 'still on its way');

    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('panel')).dy, start + 400);
  });

  test('a later offset wins when chains merge', () {
    final DVModifier merged = const DVModifier()
        .offset(1, 2)
        .merge(const DVModifier().offset(3, 4));
    expect(merged.offsetValue, const Offset(3, 4));
    expect(const DVModifier().offset(0, 9).hasBoxStyling, isTrue);
  });
}
