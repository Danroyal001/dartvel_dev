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

  test('both brightnesses carry it', () {
    for (final Brightness b in Brightness.values) {
      expect(_resolve(dartvelSiteTheme(b).scrollbarTheme.thumbVisibility), isTrue,
          reason: '$b');
    }
  });
}

bool _resolve(WidgetStateProperty<bool?>? property) =>
    property?.resolve(<WidgetState>{}) ?? false;
