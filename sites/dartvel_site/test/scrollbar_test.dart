// The scrollbar stays on screen.
//
// Flutter's default fades the thumb out after a scroll and, on a touch input,
// never draws one at all. On a long documentation page that means a visitor
// has no standing indication of how much is left -- the page looks the same
// at the top of nine sections as it does at the bottom of one.
//
// Two things are needed and one alone is not enough. The theme makes the thumb
// persistent where a scrollbar exists; the scroll behaviour is what makes one
// exist for every input rather than only for a mouse.
import 'package:dartvel_site/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _tallPage() => MaterialApp(
      theme: dartvelSiteTheme(Brightness.light),
      scrollBehavior: const DartvelSiteScrollBehavior(),
      home: Scaffold(
        body: ListView(
          children: <Widget>[
            for (int i = 0; i < 60; i++) SizedBox(height: 80, child: Text('$i')),
          ],
        ),
      ),
    );

void main() {
  testWidgets('a scrollable carries a scrollbar', (WidgetTester tester) async {
    await tester.pumpWidget(_tallPage());
    await tester.pump();

    expect(find.byType(Scrollbar), findsWidgets);
  });

  testWidgets('and its thumb does not fade away', (WidgetTester tester) async {
    await tester.pumpWidget(_tallPage());
    await tester.pump();

    final Scrollbar bar = tester.widget<Scrollbar>(find.byType(Scrollbar).first);
    // Read from the theme rather than passed per call site, so every
    // scrollable on the site gets it without each page remembering to ask.
    final ScrollbarThemeData theme =
        dartvelSiteTheme(Brightness.light).scrollbarTheme;
    expect(bar.thumbVisibility ?? _resolve(theme.thumbVisibility), isTrue);
    expect(_resolve(theme.trackVisibility), isTrue);
  });

  testWidgets('on a touch platform too, where Flutter draws none by default', (
    WidgetTester tester,
  ) async {
    // The Material behaviour switches on platform inside buildScrollbar and
    // returns the child unwrapped for iOS and Android, so a tablet or a phone
    // browser got no indicator at all. Pumped as Android rather than asserted
    // against a flag, because the switch is the thing under test.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(_tallPage());
      await tester.pump();

      expect(find.byType(Scrollbar), findsWidgets);
    } finally {
      // Cleared inside the body, not in a tearDown. The framework asserts no
      // foundation debug variable survives the test, and a tearDown runs after
      // that check -- so the cleanup has to happen before the body returns.
      debugDefaultTargetPlatformOverride = null;
    }
  });

testWidgets('and on a phone, dragging the thumb moves the page', (
    WidgetTester tester,
  ) async {
    // Flutter resolves the thumb's draggability as
    // `interactive ?? theme.interactive ?? !_useAndroidScrollbar`, and a phone
    // browser reports Android, so the thumb was drawn and ignored every touch.
    // A visible control that does nothing when touched reads as broken, which
    // is what it was.
    //
    // Dragged downward from the top of the thumb. On the content that gesture
    // would pull toward the top, where the page already is, so the offset only
    // moves if the thumb took the drag.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(_tallPage());
      // Settled, not pumped once. The scrollbar registers its thumb-drag
      // recognizer only when the scroll position has reported its content
      // size, which happens a frame after the first build -- so a drag started
      // after a single pump lands on a scrollbar that has not asked for it yet,
      // and fails whether or not the thumb is interactive. The first version of
      // this test did exactly that, which is how it failed identically with
      // and without the fix and proved nothing either way.
      await tester.pumpAndSettle();

      final ScrollableState scrollable =
          tester.state<ScrollableState>(find.byType(Scrollable).first);
      final Size surface = tester.getSize(find.byType(Scrollable).first);

      final TestGesture gesture =
          await tester.startGesture(Offset(surface.width - 4, 20));
      for (int i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(0, 20));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 100));

      expect(scrollable.position.pixels, greaterThan(0),
          reason: 'the thumb did not respond to a touch drag');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('both brightnesses carry it', () {
    for (final Brightness b in Brightness.values) {
      expect(_resolve(dartvelSiteTheme(b).scrollbarTheme.thumbVisibility), isTrue,
          reason: '$b');
    }
  });
}

bool _resolve(WidgetStateProperty<bool?>? property) =>
    property?.resolve(<WidgetState>{}) ?? false;
