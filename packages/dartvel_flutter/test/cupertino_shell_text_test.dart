// On Apple platforms `DVPageShell` builds a `CupertinoPageScaffold`, and unlike
// Material's `Scaffold` it establishes no `DefaultTextStyle`. Every `DVText`
// under it therefore fell back to Flutter's built-in default — black, unscaled,
// with the yellow double underline Flutter uses to say "you have no text style
// here".
//
// It shipped because no test and no build check renders on an Apple platform.
// It was found by photographing the running app on macOS and iOS and noticing
// that both looked wrong in a way Linux, Windows, Android and web did not.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// The style the *body* text resolves to, as rendered.
  ///
  /// Found by its content, not by position. The first attempt took
  /// `find.byType(RichText).last` and measured the navigation bar title, which
  /// CupertinoNavigationBar styles itself — so the test passed while the body
  /// text was still falling back.
  TextStyle resolvedStyleOf(WidgetTester tester) {
    final rich = tester.widget<RichText>(
      find.descendant(
        of: find.text('body text'),
        matching: find.byType(RichText),
        matchRoot: true,
      ),
    );
    return rich.text.style!;
  }

  Future<void> pumpOn(WidgetTester tester, TargetPlatform platform) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: platform),
        home: const DVPageShell(
          spec: DVPageScaffoldSpec(title: 'Title'),
          child: DVText('body text'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('text under the Cupertino shell has a real style', (tester) async {
    await pumpOn(tester, TargetPlatform.macOS);

    // The tell. Flutter's no-style fallback is the only thing that draws a
    // double underline, so asserting its absence is asserting the bug is gone
    // rather than asserting a particular design.
    final style = resolvedStyleOf(tester);
    expect(style.decoration, isNot(TextDecoration.underline),
        reason: 'the yellow double underline is Flutter saying there is no '
            'DefaultTextStyle above this text');
    expect(style.fontSize, isNotNull,
        reason: 'a resolved style has a size; the fallback does not inherit one');
  });

  testWidgets('every Apple platform gets one, not just macOS', (tester) async {
    for (final platform in <TargetPlatform>[
      TargetPlatform.macOS,
      TargetPlatform.iOS,
    ]) {
      await pumpOn(tester, platform);
      expect(resolvedStyleOf(tester).decoration,
          isNot(TextDecoration.underline),
          reason: '$platform builds the Cupertino shell too');
    }
  });

  testWidgets('the Material shell is unaffected', (tester) async {
    // It was never broken, and the fix must not reach into it.
    await pumpOn(tester, TargetPlatform.linux);
    expect(resolvedStyleOf(tester).decoration, isNot(TextDecoration.underline));
  });
}
