// A design's typography, as far as the page can carry it.
//
// A text node could say its size, weight, spacing and colour and nothing
// else. Two things a designer sets on nearly every text layer had nowhere to
// go: the typeface, and the line height. An import wrote the family into the
// document, where nothing read it -- so every screen came out in the default
// font -- and paragraphs came out at the font's own leading, which is what
// makes an imported page look cramped next to the design it came from.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DVPageDocument pageWith(Map<String, Object?> properties) {
  final DVPageDocument document = DVPageDocument(route: '/typed');
  final DVPageDocumentEditor editor = DVPageDocumentEditor(document);
  DVPageNode text = DVPageNode.text('Hello');
  properties.forEach((String name, Object? value) {
    text = text.withProperty(name, value);
  });
  editor.insert(text, parent: document.root.id);
  return document;
}

TextStyle styleIn(WidgetTester tester) =>
    tester.widget<Text>(find.text('Hello')).style!;

Future<void> pump(WidgetTester tester, DVPageDocument document) =>
    tester.pumpWidget(MaterialApp(home: DVPageDocumentRenderer(document)));

void main() {
  testWidgets('a named typeface is the one that renders',
      (WidgetTester tester) async {
    await pump(tester, pageWith(const <String, Object?>{'fontFamily': 'Inter'}));

    expect(styleIn(tester).fontFamily, 'Inter');
  });

  testWidgets('line height is a multiple of the size, as Flutter reads it',
      (WidgetTester tester) async {
    await pump(tester,
        pageWith(const <String, Object?>{'fontSize': 16, 'lineHeight': 1.5}));

    expect(styleIn(tester).height, 1.5);
  });

  testWidgets('a text node that says neither still renders',
      (WidgetTester tester) async {
    await pump(tester, pageWith(const <String, Object?>{'fontSize': 16}));

    expect(styleIn(tester).fontFamily, isNull);
    expect(styleIn(tester).height, isNull);
  });

  test('both are in the exported source', () {
    final String source = pageWith(const <String, Object?>{
      'fontFamily': 'Inter',
      'lineHeight': 1.5,
    }).toDartSource();

    expect(source, contains(".fontFamily('Inter')"));
    expect(source, contains('.lineHeight(1.5)'));
  });
}
