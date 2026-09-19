// A button that takes a long page to its bottom, and back to the top once
// you are there.
//
// The site's pages are long -- the docs index, Features, the CLI reference --
// and a reader who wants the footer, or the top again, scrolled the whole way.
// The page layout owns the page's scroll controller, so one button serves
// every page, and a page too short to scroll shows none.
import 'package:dartvel_site/components/scroll_jump.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget page(double height) => MaterialApp(
      home: Scaffold(
        body: PageScroll(
          child: SingleChildScrollView(child: SizedBox(height: height)),
        ),
      ),
    );

ScrollPosition position(WidgetTester tester) =>
    tester.state<ScrollableState>(find.byType(Scrollable).first).position;

void main() {
  testWidgets('goes to the bottom, then back to the top',
      (WidgetTester tester) async {
    await tester.pumpWidget(page(5000));
    await tester.pumpAndSettle();

    expect(find.byTooltip('To the bottom'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('scroll-jump')));
    await tester.pumpAndSettle();
    expect(position(tester).pixels, position(tester).maxScrollExtent);

    expect(find.byTooltip('Back to top'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('scroll-jump')));
    await tester.pumpAndSettle();
    expect(position(tester).pixels, 0);
  });

  testWidgets('turns into Back to top when the reader scrolls down',
      (WidgetTester tester) async {
    await tester.pumpWidget(page(5000));
    await tester.pumpAndSettle();

    position(tester).jumpTo(position(tester).maxScrollExtent);
    await tester.pumpAndSettle();

    expect(find.byTooltip('Back to top'), findsOneWidget);
  });

  testWidgets('a page too short to scroll has no button',
      (WidgetTester tester) async {
    await tester.pumpWidget(page(300));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('scroll-jump')), findsNothing);
  });
}
