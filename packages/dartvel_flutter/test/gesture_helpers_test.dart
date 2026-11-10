// DVModifier's gesture helpers, so an application names the gesture rather
// than building a detector: onTap, onPressed, onLongPress, onDoubleTap,
// onSwipeLeft/Right/Up/Down, and onGesture for a custom drag, pinch or
// rotate. Each swipe is offered to a screen reader as a scroll action.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
