// Whether text on a Dartvel page can be selected.
//
// It could not. DVText renders a plain Text, and nothing in the page shell
// wrapped the tree in a SelectionArea, so every Dartvel page shipped text a
// visitor cannot select or copy. On a website that is not a rough edge: the
// install command is the one thing a visitor needs off the page, and they
// could not take it.
//
// Flutter has a widget for exactly this. Not using it was the bug.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget shell(DVPageScaffoldSpec spec, Widget child) => MaterialApp(
      home: DVPageShell(spec: spec, child: child),
    );

void main() {
  group('page text selection', () {
    testWidgets('a page is selectable by default', (WidgetTester tester) async {
      await tester.pumpWidget(shell(
        const DVPageScaffoldSpec(title: 'T'),
        const DVText('brew install dartvel_dev'),
      ));

      expect(find.byType(SelectionArea), findsOneWidget);
    });

    testWidgets('the text is still rendered inside it',
        (WidgetTester tester) async {
      // A SelectionArea that swallowed its child would pass the check above
      // and show an empty page.
      await tester.pumpWidget(shell(
        const DVPageScaffoldSpec(title: 'T'),
        const DVText('brew install dartvel_dev'),
      ));

      expect(find.text('brew install dartvel_dev'), findsOneWidget);
    });

    testWidgets('a page can opt out', (WidgetTester tester) async {
      // An app with its own drag gestures over text has a reason to, and a
      // default with no escape hatch is a worse default.
      await tester.pumpWidget(shell(
        const DVPageScaffoldSpec(title: 'T', selectable: false),
        const DVText('drag me'),
      ));

      expect(find.byType(SelectionArea), findsNothing);
      expect(find.text('drag me'), findsOneWidget);
    });

    testWidgets('it wraps inside the safe area, not outside',
        (WidgetTester tester) async {
      // Order matters: a SelectionArea above the SafeArea would let a drag
      // begin in the notch or the home indicator.
      await tester.pumpWidget(shell(
        const DVPageScaffoldSpec(title: 'T', safeArea: true),
        const DVText('x'),
      ));

      final safeArea = find.byType(SafeArea);
      expect(safeArea, findsWidgets);
      expect(
        find.descendant(of: safeArea.first, matching: find.byType(SelectionArea)),
        findsOneWidget,
      );
    });
  });
}
