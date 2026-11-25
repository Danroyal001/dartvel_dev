// DVModifier's gesture helpers, so an application names the gesture rather
// than building a detector: onTap, onPressed, onLongPress, onDoubleTap,
// onSwipeLeft/Right/Up/Down, and onGesture for a custom drag, pinch or
// rotate. Each swipe is offered to a screen reader as a scroll action.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _page(DVModifier modifier) => MaterialApp(
      home: Scaffold(
        body: Center(child: DVBox(const SizedBox(width: 300, height: 300, child: Text('Pad')), modifier)),
      ),
    );

void main() {
  testWidgets('a double tap', (WidgetTester tester) async {
    int doubles = 0;
    await tester.pumpWidget(_page(DVModifier().onDoubleTap(() => doubles++)));
    await tester.tap(find.text('Pad'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Pad'));
    await tester.pumpAndSettle();
    expect(doubles, 1);
  });

  testWidgets('each swipe calls its own direction and no other', (WidgetTester tester) async {
    final List<String> swipes = <String>[];
    await tester.pumpWidget(_page(DVModifier()
        .onSwipeLeft(() => swipes.add('left'))
        .onSwipeRight(() => swipes.add('right'))
        .onSwipeUp(() => swipes.add('up'))
        .onSwipeDown(() => swipes.add('down'))));
    await tester.fling(find.text('Pad'), const Offset(-200, 0), 1000);
    await tester.fling(find.text('Pad'), const Offset(200, 0), 1000);
    await tester.fling(find.text('Pad'), const Offset(0, -200), 1000);
    await tester.fling(find.text('Pad'), const Offset(0, 200), 1000);
    await tester.pumpAndSettle();
    expect(swipes, ['left', 'right', 'up', 'down']);
  });

  testWidgets('a slow drag is not a swipe', (WidgetTester tester) async {
    int swipes = 0;
    await tester.pumpWidget(_page(DVModifier().onSwipeUp(() => swipes++)));
    await tester.timedDrag(find.text('Pad'), const Offset(0, -20), const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(swipes, 0);
  });

  testWidgets('a screen reader is offered each swipe as a scroll action', (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    int ups = 0;
    await tester.pumpWidget(_page(DVModifier().semanticLabel('Home').onSwipeUp(() => ups++)));
    final SemanticsNode node = tester.getSemantics(find.bySemanticsLabel('Home'));
    // Swiping up moves content up, which is scrolling toward the end.
    expect(node.getSemanticsData().hasAction(SemanticsAction.scrollUp), isTrue);
    tester.binding.pipelineOwner.semanticsOwner!.performAction(node.id, SemanticsAction.scrollUp);
    await tester.pump();
    expect(ups, 1);
    handle.dispose();
  });

  testWidgets('onGesture: a custom drag, pinch or rotate with its start, update and end', (WidgetTester tester) async {
    final List<String> seen = <String>[];
    double lastScale = 1;
    await tester.pumpWidget(_page(DVModifier().onGesture(DVGesture(
      onStart: (ScaleStartDetails _) => seen.add('start'),
      onUpdate: (ScaleUpdateDetails details) => lastScale = details.scale,
      onEnd: (ScaleEndDetails _) => seen.add('end'),
    ))));
    await tester.drag(find.text('Pad'), const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(seen, ['start', 'end']);
    expect(lastScale, 1, reason: 'one finger drags; it does not scale');
  });

  testWidgets('the helpers stack with onTap', (WidgetTester tester) async {
    int taps = 0;
    int lefts = 0;
    await tester.pumpWidget(_page(DVModifier().tooltip('Pad').onTap(() => taps++).onSwipeLeft(() => lefts++)));
    await tester.tap(find.text('Pad'));
    await tester.fling(find.text('Pad'), const Offset(-200, 0), 1000);
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(lefts, 1);
  });

  testWidgets('text takes the same helpers as a box', (WidgetTester tester) async {
    int doubles = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: DVText('Like').modifier(DVModifier().onDoubleTap(() => doubles++))))));
    await tester.tap(find.text('Like'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Like'));
    await tester.pumpAndSettle();
    expect(doubles, 1);
  });

  group('over a box that scrolls', () {
    // A scrolling list claims every vertical drag (a primary ListView on a
    // phone always scrolls, even when everything fits), so a swipe down on a
    // home screen whose content scrolls never reached onSwipeDown. A pull
    // past the list's top is that swipe, as on every launcher; past its end,
    // a swipe up.
    Widget scrolling(DVModifier modifier, {int rows = 3}) => MaterialApp(
          home: Scaffold(
            body: DVBox(
              DVBox.list(<Widget>[for (int row = 0; row < rows; row++) SizedBox(height: 120, child: Text('Row $row'))]).scrollable(),
              modifier,
            ),
          ),
        );

    testWidgets('a swipe down at the top of the list is onSwipeDown, once', (WidgetTester tester) async {
      int downs = 0;
      await tester.pumpWidget(scrolling(DVModifier().onSwipeDown(() => downs++)));
      await tester.fling(find.text('Row 0'), const Offset(0, 250), 1500);
      await tester.pumpAndSettle();
      expect(downs, 1);
    });

    testWidgets('a long list scrolled down is scrolled back by a swipe down, not swiped', (WidgetTester tester) async {
      int downs = 0;
      await tester.pumpWidget(scrolling(DVModifier().onSwipeDown(() => downs++), rows: 40));
      await tester.drag(find.text('Row 2'), const Offset(0, -600));
      await tester.pumpAndSettle();
      await tester.drag(find.text('Row 7'), const Offset(0, 300));
      await tester.pumpAndSettle();
      expect(downs, 0, reason: 'the list scrolled back and still had room above');
    });

    testWidgets('a swipe up at the end of a list is onSwipeUp', (WidgetTester tester) async {
      int ups = 0;
      await tester.pumpWidget(scrolling(DVModifier().onSwipeUp(() => ups++)));
      await tester.fling(find.text('Row 2'), const Offset(0, -250), 1500);
      await tester.pumpAndSettle();
      expect(ups, 1);
    });

    testWidgets('with a custom gesture too, and a pinch still reaches it', (WidgetTester tester) async {
      int downs = 0;
      double smallest = 1;
      await tester.pumpWidget(scrolling(DVModifier().onSwipeDown(() => downs++).onGesture(DVGesture(onUpdate: (ScaleUpdateDetails details) {
        if (details.pointerCount >= 2 && details.scale < smallest) smallest = details.scale;
      }))));
      await tester.fling(find.text('Row 0'), const Offset(0, 250), 1500);
      await tester.pumpAndSettle();
      expect(downs, 1);
      final TestGesture first = await tester.startGesture(const Offset(100, 200), pointer: 7);
      final TestGesture second = await tester.startGesture(const Offset(300, 200), pointer: 8);
      for (int step = 0; step < 10; step++) {
        await first.moveBy(const Offset(7, 0));
        await second.moveBy(const Offset(-7, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      expect(smallest, lessThan(0.6), reason: 'two fingers closing over the list are a pinch');
    });
  });
}
