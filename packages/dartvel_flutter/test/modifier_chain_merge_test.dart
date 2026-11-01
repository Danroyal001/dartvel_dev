// `.modifier()` replaced the box's modifier instead of adding to it, so
// `DVBox.list(children, modifier: DVModifier().maxWidth(1120))
//   .modifier(DVModifier().align(.topCenter))` dropped the maximum width and
// a "capped" reading column ran the full width of a 4K screen.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a chained modifier keeps the bounds set before it',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: const DVBox.list(
            <Widget>[DVText('column')],
          )
              .modifier(const DVModifier().maxWidth(600))
              .modifier(const DVModifier().padding(8)),
        ),
      ),
    );
    expect(tester.getSize(find.byType(DVBox)).width, lessThanOrEqualTo(600));
  });

  testWidgets('a later modifier still wins where both set the same field',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: const DVText('word')
              .modifier(const DVModifier().fontSize(10))
              .modifier(const DVModifier().fontSize(30)),
        ),
      ),
    );
    final Text text = tester.widget<Text>(find.text('word'));
    expect(text.style?.fontSize, 30);
  });

  testWidgets('a chained text modifier keeps the colour set before it',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: const DVText('word')
              .modifier(const DVModifier().color(Color(0xFF123456)))
              .modifier(const DVModifier().fontSize(30)),
        ),
      ),
    );
    final Text text = tester.widget<Text>(find.text('word'));
    expect(text.style?.color, const Color(0xFF123456));
  });
}
