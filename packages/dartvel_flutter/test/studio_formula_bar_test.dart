// The formula bar across the top of the Studio editor.
//
// Select an element and its content is in the bar as a formula; pick
// another field from the box on the left; type; Enter applies it through
// the editor, as one undoable edit, and Esc puts back what was there. A
// formula that is wrong is refused where it is wrong and the page is left
// alone. What the bar writes is what the inspector writes: there is one
// document and one history.
import 'package:dartvel_flutter/src/studio/page_document.dart';
import 'package:dartvel_flutter/src/studio/studio_editor.dart';
import 'package:dartvel_flutter/src/studio/studio_formula.dart';
import 'package:dartvel_flutter/src/studio/studio_formula_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

DVStudioEditorController editor() {
  final DVPageNode root = DVPageNode(type: 'box', children: <DVPageNode>[
    DVPageNode.text('Welcome').withProperty('fontSize', 18),
  ]);
  return DVStudioEditorController(DVPageDocument(route: '/home', root: root));
}

String firstLeaf(DVStudioEditorController c) => c.document.root.children.first.id;

Future<void> pumpBar(WidgetTester tester, DVStudioEditorController c) =>
    tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DVStudioFormulaBar(
          controller: c,
          vocabulary: const DVFormulaVocabulary(routes: <String>['/home', '/pricing']),
        ),
      ),
    ));

Finder input() => find.byKey(DVStudioFormulaBar.inputKey);

/// Picks [name] in the name box, scrolling its menu to it: an element has
/// some thirty fields and the menu builds the ones on screen.
Future<void> pickField(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(DVStudioFormulaBar.fieldKey));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.text(name), 120,
      scrollable: find.byType(Scrollable).last);
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('with nothing selected the bar says so and takes no input',
      (WidgetTester tester) async {
    await pumpBar(tester, editor());
    expect(find.text('Select an element to edit it here'), findsOneWidget);
    expect(tester.widget<TextField>(input()).enabled, isFalse);
  });

  testWidgets('Enter applies a formula as one undoable edit', (WidgetTester tester) async {
    final DVStudioEditorController c = editor();
    await pumpBar(tester, c);
    c.select(firstLeaf(c));
    await tester.pump();
    expect(tester.widget<TextField>(input()).controller!.text, '"Welcome"');

    await tester.enterText(input(), '"Hello there"');
    await tester.testTextInput.receiveAction(.done);
    await tester.pump();
    expect(c.selectedNode!.properties['text'], 'Hello there');

    c.undo();
    await tester.pump();
    expect(c.document.root.children.first.properties['text'], 'Welcome');
    expect(tester.widget<TextField>(input()).controller!.text, '"Welcome"');
  });

  testWidgets('another field is picked from the name box', (WidgetTester tester) async {
    final DVStudioEditorController c = editor();
    await pumpBar(tester, c);
    c.select(firstLeaf(c));
    await tester.pump();
    await pickField(tester, 'fontSize');
    expect(tester.widget<TextField>(input()).controller!.text, '18');

    await tester.enterText(input(), '=12 * 2');
    await tester.testTextInput.receiveAction(.done);
    await tester.pump();
    expect(c.selectedNode!.properties['fontSize'], 24);
  });

  testWidgets('a wrong formula is refused and the page is left alone',
      (WidgetTester tester) async {
    final DVStudioEditorController c = editor();
    await pumpBar(tester, c);
    c.select(firstLeaf(c));
    await tester.pump();
    await pickField(tester, 'color');
    await tester.enterText(input(), '#GG0000');
    await tester.testTextInput.receiveAction(.done);
    await tester.pump();
    expect(find.byKey(DVStudioFormulaBar.errorKey), findsOneWidget);
    expect(find.textContaining('A colour is'), findsOneWidget);
    expect(c.selectedNode!.properties.containsKey('color'), isFalse);
    expect(c.canUndo, isFalse);
  });

  testWidgets('Esc puts back what was there', (WidgetTester tester) async {
    final DVStudioEditorController c = editor();
    await pumpBar(tester, c);
    c.select(firstLeaf(c));
    await tester.pump();
    await tester.tap(input());
    await tester.enterText(input(), '"Changed my mind"');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(tester.widget<TextField>(input()).controller!.text, '"Welcome"');
    expect(c.selectedNode!.properties['text'], 'Welcome');
  });

  testWidgets('completions are offered and a tap takes one', (WidgetTester tester) async {
    final DVStudioEditorController c = editor();
    await pumpBar(tester, c);
    c.select(firstLeaf(c));
    await tester.pump();
    await pickField(tester, 'action');
    await tester.tap(input());
    await tester.enterText(input(), 'Navigate("/pr');
    await tester.pump();
    expect(find.text('/pricing'), findsOneWidget);
    await tester.tap(find.text('/pricing'));
    await tester.pump();
    expect(tester.widget<TextField>(input()).controller!.text, 'Navigate("/pricing');
  });

  test('the formula is highlighted by kind', () {
    final DVFormulaTextController text = DVFormulaTextController(text: 'Navigate("/x")');
    final TextSpan span = text.buildTextSpan(
        context: _FakeContext(), withComposing: false);
    final List<InlineSpan> runs = span.children!;
    expect(runs.length, greaterThanOrEqualTo(3));
    final Color? function = (runs.first as TextSpan).style?.color;
    final Color? string = (runs[2] as TextSpan).style?.color;
    expect(function, isNotNull);
    expect(string, isNot(function));
  });
}

class _FakeContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
