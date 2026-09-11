// The home page scrolls like every other page.
//
// It used to be a deck: one section per flick, snapped by PageScrollPhysics,
// with a rail and a wheel handler holding a cooldown. On a phone that is a page
// that fights your finger. A short drag springs back, a long one jumps a whole
// section, and there is no way to read the bottom of one section and the top
// of the next together -- which on a narrow screen is most of reading.
//
// Asserted as a gesture rather than as the absence of a type, because the
// complaint was about what a thumb does to the page. A drag of a fifth of the
// screen has to move the page by about that much and leave it there. A
// snapping deck returns that drag to zero.
import 'package:dartvel_site/dartvel_client/dartvel_client.dart';
import 'package:dartvel_site/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Finder _pageScroll() => find
    .byWidgetPredicate((Widget w) =>
        w is Scrollable && w.axisDirection == AxisDirection.down)
    .first;

void main() {
  testWidgets('a short drag on a phone moves the page and stays moved', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;

      await tester.pumpWidget(MaterialApp(
        theme: dartvelSiteTheme(Brightness.light),
        scrollBehavior: const DartvelSiteScrollBehavior(),
        home: const Scaffold(body: IndexPageGeneratedPage()),
      ));
      // Pumped rather than settled: the bands reveal themselves as they come
      // into view, so the tree is never completely still.
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final ScrollableState page = tester.state<ScrollableState>(_pageScroll());
      expect(page.position.pixels, 0);

      // Slow enough to be a drag rather than a fling, so no ballistic motion
      // afterwards decides the answer for us.
      final TestGesture gesture =
          await tester.startGesture(tester.getCenter(_pageScroll()));
      for (int i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(0, -16));
        await tester.pump(const Duration(milliseconds: 40));
      }
      await gesture.up();
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(page.position.pixels, greaterThan(100),
          reason: 'the drag was undone -- the page snapped back');
      expect(page.position.pixels, lessThan(400),
          reason: 'the drag jumped a whole section instead of moving with it');
    } finally {
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });
}
