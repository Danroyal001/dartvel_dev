// Declaring what a thing is, beyond label and heading.
//
// Flutter renders SelectableText as a <textarea> whose value it manages, so
// every code block on dartvel.dev was invisible: absent from the
// crawler-visible HTML and absent from the tree a screen reader reads. Nine of
// them on the docs page, the install commands among them.
//
// Flutter's Semantics has no role for code, so the role travels as an
// identifier. Flutter web puts that in the DOM, which is where the static
// build reads it.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) =>
      tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

  testWidgets('a role reaches the semantics tree', (tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await pump(
      tester,
      // ignore: prefer_const_constructors
      DVText('brew install dartvel_dev')
          .modifier(DVModifier().semanticRole('code')),
    );

    expect(
      // By widget, not by text: a role excludes the inner text's own node so
      // the identifier has somewhere to live, which means find.text walks
      // past it.
      tester.getSemantics(find.byType(DVText)).identifier,
      'dartvel:code',
    );
    handle.dispose();
  });

  testWidgets('the text is still the label', (tester) async {
    // A role that lost the content would be worse than no role: the whole
    // point is that the code is readable.
    final SemanticsHandle handle = tester.ensureSemantics();
    await pump(
      tester,
      // ignore: prefer_const_constructors
      DVText('dartvel dev').modifier(DVModifier().semanticRole('code')),
    );

    expect(tester.getSemantics(find.byType(DVText)).label, 'dartvel dev');
    handle.dispose();
  });

  testWidgets('no role means no identifier', (tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await pump(tester, const DVText('Ordinary'));

    expect(tester.getSemantics(find.byType(DVText)).identifier, isEmpty);
    handle.dispose();
  });

  test('a role is namespaced, so it cannot collide', () {
    // identifier is also used for test hooks and platform integrations. An
    // unprefixed "code" would be indistinguishable from an application's own.
    expect(const DVModifier().semanticRole('code').semanticRoleValue,
        'dartvel:code');
  });
}
