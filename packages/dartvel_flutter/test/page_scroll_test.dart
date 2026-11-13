// The long-page "To the bottom / Back to top" button is an attribute, not a
// widget to nest (owner, 13 Nov 2026): `pageScroll: true` on a DVClassWidget
// or a DartvelLayout here, `@DVFunctionalWidget(pageScroll: true)` in the
// generator's tests. dartvel.dev had it as a component of its own, so other
// Dartvel sites did not.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Page extends DVClassWidget {
  const _Page({required this.height, super.pageScroll});
  final double height;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(child: SizedBox(height: height, child: const Text('page')));
}

class _Layout extends DartvelLayout {
  const _Layout({required super.child, super.pageScroll});
  @override
  Widget build(BuildContext context) => SingleChildScrollView(child: child);
}

Widget app(Widget page, {ThemeData? theme}) => MaterialApp(theme: theme, home: Scaffold(body: page));

void main() {
  testWidgets('off unless asked for', (WidgetTester tester) async {
    await tester.pumpWidget(app(const _Page(height: 5000)));
    await tester.pump();
    expect(find.byTooltip('To the bottom'), findsNothing);
  });

  testWidgets('a short page has no button: it would only cover the page', (WidgetTester tester) async {
    await tester.pumpWidget(app(const _Page(height: 700, pageScroll: true)));
    await tester.pump();
    expect(find.byTooltip('To the bottom'), findsNothing);
    expect(find.byTooltip('Back to top'), findsNothing);
  });

  testWidgets('a long page offers the bottom, then the top once there', (WidgetTester tester) async {
    await tester.pumpWidget(app(const _Page(height: 5000, pageScroll: true)));
    await tester.pump();
    expect(find.byTooltip('To the bottom'), findsOneWidget);

    await tester.tap(find.byTooltip('To the bottom'));
    await tester.pumpAndSettle();
    final ScrollPosition position = tester.state<ScrollableState>(find.byType(Scrollable)).position;
    expect(position.pixels, position.maxScrollExtent);
    expect(find.byTooltip('Back to top'), findsOneWidget);

    await tester.tap(find.byTooltip('Back to top'));
    await tester.pumpAndSettle();
    expect(position.pixels, 0);
  });

  testWidgets('on a layout, for every page inside it', (WidgetTester tester) async {
    await tester.pumpWidget(app(const _Layout(pageScroll: true, child: SizedBox(height: 5000))));
    await tester.pump();
    expect(find.byTooltip('To the bottom'), findsOneWidget);
  });

  testWidgets('a screen reader hears one button with one name', (WidgetTester tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    await tester.pumpWidget(app(const _Page(height: 5000, pageScroll: true)));
    await tester.pump();
    expect(find.bySemanticsLabel('To the bottom'), findsOneWidget);
    expect(tester.getSemantics(find.bySemanticsLabel('To the bottom')), matchesSemantics(label: 'To the bottom', isButton: true, hasTapAction: true));
    semantics.dispose();
  });

  testWidgets('it takes its colours from the app theme, light and dark', (WidgetTester tester) async {
    for (final Brightness brightness in Brightness.values) {
      final ThemeData theme = ThemeData(brightness: brightness, useMaterial3: true);
      await tester.pumpWidget(app(const _Page(height: 5000, pageScroll: true), theme: theme));
      await tester.pumpAndSettle(); // MaterialApp animates a theme change
      final Material button = tester.widget<Material>(find.byKey(const ValueKey<String>('dv-page-scroll')));
      expect(button.color, theme.colorScheme.surface, reason: brightness.name);
    }
  });
}
