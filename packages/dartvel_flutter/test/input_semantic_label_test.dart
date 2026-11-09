// A named input field that could not be typed into.
//
// `DVText(value).modifier(DVModifier().input(...).semanticLabel('Search'))`
// is the natural way to give a search box a name for screen readers. The
// semantic label path excluded the child's semantics, and the child here is
// the text field itself: the tree held one empty node with no text-field
// flag, no label and no tap action. On the web, where Dartvel turns
// semantics on, that empty node sat over the field and took the click, so
// the box on sigmadev.digital/tools never focused and nothing could be typed.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) =>
      tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

  testWidgets('a labelled input is still a text field in the semantics tree',
      (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await pump(
      tester,
      DVText('').modifier(
        DVModifier()
            .input(hint: 'Search 177 tools…', onChanged: (_) {})
            .semanticLabel('Search the tools'),
      ),
    );

    final SemanticsNode field = tester.getSemantics(find.byType(TextField));
    final SemanticsData data = field.getSemanticsData();
    expect(data.flagsCollection.isTextField, isTrue,
        reason: 'the field has to reach a screen reader and the web as a '
            'text field, or the web build puts an empty node over it');
    expect(data.label, contains('Search the tools'));
    expect(data.hasAction(SemanticsAction.tap), isTrue,
        reason: 'a field with no tap action cannot be focused through the '
            'semantics tree');
    handle.dispose();
  });

  testWidgets('a labelled input takes typing', (WidgetTester tester) async {
    String typed = '';
    await pump(
      tester,
      DVText('').modifier(
        DVModifier()
            .input(hint: 'Search', onChanged: (String value) => typed = value)
            .semanticLabel('Search the tools'),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'margin');
    expect(typed, 'margin');
  });

  testWidgets('a labelled plain text still owns its label',
      (WidgetTester tester) async {
    // The exclusion is right for plain text: the label replaces the words.
    final SemanticsHandle handle = tester.ensureSemantics();
    await pump(
      tester,
      DVText('★★★★☆').modifier(DVModifier().semanticLabel('Four stars')),
    );

    expect(tester.getSemantics(find.text('★★★★☆')).label, 'Four stars');
    handle.dispose();
  });
}
