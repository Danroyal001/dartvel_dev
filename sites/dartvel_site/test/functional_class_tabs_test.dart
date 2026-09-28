// Dartvel writes widgets and pages as annotated functions, and supports the
// class shape for a reader who prefers classes. Every sample that shows the
// function shape also shows the class one, behind the same two tabs, with
// the function shape first.
import 'package:dartvel_site/components/docs_samples.dart';
import 'package:dartvel_site/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A sample that writes a widget or a page as an annotated function.
bool isFunctional(List<String> lines) => lines.any((String l) =>
    l.contains('@DVFunctionalWidget()') ||
    RegExp(r'^@DVPage\(').hasMatch(l) &&
        lines.any((String w) => RegExp(r'^Widget _').hasMatch(w)));

void main() {
  test('every function-shaped sample has its class alternative', () {
    final List<String> missing = <String>[
      for (final MapEntry<String, List<String>> s in kDocsSamples.entries)
        if (!s.key.endsWith('-class') &&
            isFunctional(s.value) &&
            !kDocsSamples.containsKey('${s.key}-class'))
          s.key,
    ];
    expect(missing, isEmpty);
  });

  test('a class alternative is written as a class, not a function', () {
    for (final MapEntry<String, List<String>> s in kDocsSamples.entries) {
      if (!s.key.endsWith('-class')) continue;
      final String code = s.value.join('\n');
      expect(code, contains(RegExp(r'^class ', multiLine: true)),
          reason: s.key);
      expect(code, isNot(contains('@DVFunctionalWidget')), reason: s.key);
    }
  });

  testWidgets('the function shape shows first, and the class one on a tap',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(
          child: DocsCode('ui-functional-widget'))),
    ));
    final String functional = kDocsSamples['ui-functional-widget']!
        .firstWhere((String l) => l.startsWith('Widget _'));
    final String asClass = kDocsSamples['ui-functional-widget-class']!
        .firstWhere((String l) => l.startsWith('class '));

    expect(find.text('Functional'), findsOneWidget);
    expect(find.text('Class'), findsOneWidget);
    expect(find.textContaining(functional, findRichText: true), findsOneWidget);
    expect(find.textContaining(asClass, findRichText: true), findsNothing);

    await tester.tap(find.text('Class'));
    await tester.pumpAndSettle();
    expect(find.textContaining(asClass, findRichText: true), findsOneWidget);
    expect(find.textContaining(functional, findRichText: true), findsNothing);
  });

  testWidgets('the tabs say which is selected to assistive technology',
      (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(
          child: DocsCode('ui-functional-widget'))),
    ));
    expect(
      tester.getSemantics(find.text('Functional')),
      matchesSemantics(
          label: 'Functional',
          isSelected: true,
          hasSelectedState: true,
          isButton: true,
          hasTapAction: true,
          isFocusable: true,
          hasFocusAction: true,
          hasEnabledState: true,
          isEnabled: true),
    );
    handle.dispose();
  });

  testWidgets('a sample with no alternative is a plain block',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: DocsCode('ui-theme'))),
    ));
    expect(find.text('Class'), findsNothing);
  });
}
