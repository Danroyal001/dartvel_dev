// The page is on screen, not merely in the tree.
//
// Every section on this site is wrapped in revealOnScroll, which starts it at
// opacity zero and animates it in -- and deliberately keeps its semantics
// while it is invisible, so a crawler still sees a section the reader has not
// scrolled to. That is right for a crawler and it is exactly what hides this
// class of bug from every other test here: the widget is found, the text is
// found, the layout does not overflow, and nothing at all is painted.
//
// The front page had already shown what that costs. Its prose was laid into
// boxes a point tall for weeks: present in the tree, read out by a screen
// reader, invisible to everybody else, and no test failed.
//
// So this one asks the only question that matters to a reader -- is it
// actually visible -- and asks it at a phone width, because a reveal decides
// what to do from the viewport's own height.
import 'package:dartvel_site/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'responsive_layout_test.dart' show routed;

/// The opacity every ancestor of [finder] multiplies together.
///
/// A reveal that never fired leaves its section at zero, and a section at zero
/// is a blank page however complete the tree under it is.
double visibility(WidgetTester tester, Finder finder) {
  double opacity = 1;
  for (final Widget widget in tester.widgetList(
    find.ancestor(of: finder, matching: find.byType(Opacity)),
  )) {
    opacity *= (widget as Opacity).opacity;
  }
  return opacity;
}

void main() {
  // The pages are deferred, and the cache the generated page keeps is per
  // zone -- so it is loaded once here and dropped before each test, exactly
  // as the responsive suite does it.
  setUpAll(FeaturesPageGeneratedPage.loadLibrary);
  setUp(dvResetDeferredPages);

  for (final (String name, Size size) device in const <(String, Size)>[
    ('a phone', Size(390, 844)),
    ('a small phone', Size(320, 640)),
    ('a tablet', Size(820, 1180)),
    ('a laptop', Size(1440, 900)),
  ]) {
    testWidgets('the features page is visible on ${device.$1}',
        (WidgetTester tester) async {
      tester.view.physicalSize = device.$2;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(routed(const FeaturesPageGeneratedPage()));
      await tester.pumpAndSettle();

      final Finder heading = find.text('Thirty-six shipped sections.');
      expect(heading, findsOneWidget);
      expect(visibility(tester, heading), 1,
          reason: 'the heading is in the tree and not on the screen');
    });
  }
}
