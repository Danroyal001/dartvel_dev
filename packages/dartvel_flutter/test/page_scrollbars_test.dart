// Every page's scrollbar is always on screen, whatever theme the application
// brings. The defaults lived only in dartvelDefaultTheme, so an app with its
// own theme (Authenticator, EatingToday) got Flutter's: a thumb that appears
// while scrolling and fades away.

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ScrollbarThemeData> scrollbarsInPage(WidgetTester tester, ThemeData theme) async {
  late ScrollbarThemeData seen;
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    home: DVPageShell(
      spec: const DVPageScaffoldSpec(title: 'Long'),
      child: Builder(builder: (BuildContext context) {
        seen = ScrollbarTheme.of(context);
        return const SizedBox(height: 4000);
      }),
    ),
  ));
  return seen;
}

void main() {
  testWidgets('an application theme of its own still keeps the scrollbar on screen', (WidgetTester tester) async {
    final ScrollbarThemeData seen = await scrollbarsInPage(tester, ThemeData(colorSchemeSeed: Colors.green));
    expect(seen.thumbVisibility?.resolve(<WidgetState>{}), isTrue);
    expect(seen.trackVisibility?.resolve(<WidgetState>{}), isTrue);
    expect(seen.interactive, isTrue);
    expect(seen.thumbColor, isNotNull, reason: 'falls back to Dartvel\'s quiet colours');
  });

  testWidgets("the application's own scrollbar colours are kept", (WidgetTester tester) async {
    final ScrollbarThemeData seen = await scrollbarsInPage(
      tester,
      ThemeData(scrollbarTheme: ScrollbarThemeData(thumbColor: WidgetStateProperty.all(const Color(0xFF00FF00)))),
    );
    expect(seen.thumbColor?.resolve(<WidgetState>{}), const Color(0xFF00FF00));
    expect(seen.thumbVisibility?.resolve(<WidgetState>{}), isTrue);
  });
}
