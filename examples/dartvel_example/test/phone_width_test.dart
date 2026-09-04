// The example, at the width of the phone CI runs it on.
//
// The Android job builds this application and drives it on a 1080x2400
// emulator, and the integration suite failed there on "A RenderFlex
// overflowed by 8.1 pixels on the right" -- a layout error, which
// integration_test counts as a failure, so a real UI bug took down a test
// about links.
//
// It is a real bug either way: the framework's own demo, drawn on a phone,
// showing the yellow-and-black stripe. Nothing in the widget suite pumped it
// narrow enough to find out, because the test binding's default surface is
// 800x600 -- wider than any phone in portrait.
import 'package:dartvel_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A Pixel 6 in portrait: 1080x2400 at 2.625x, which is what the emulator
/// this application is driven on reports.
const Size _phone = Size(411.4, 914.3);

void main() {
  testWidgets('the home page lays out on a phone without overflowing',
      (WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1080, 2400)
      ..devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: _phone),
        child: createDartvelExampleApp(),
      ),
    );
    for (int i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // takeException() is how an overflow reaches a test: RenderFlex reports
    // it through FlutterError rather than by throwing where it happened.
    expect(tester.takeException(), isNull,
        reason: 'a layout error on a phone is what the emulator run hit');
  });
}
