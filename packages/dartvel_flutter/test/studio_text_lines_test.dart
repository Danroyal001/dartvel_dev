// Text that has to fit.
//
// A design says how many lines a title gets and what happens to the rest: a
// card title is one line with an ellipsis, a description is three. A page
// document said nothing, so an imported card with a long title pushed
// everything below it down the screen or overflowed the box it was drawn in
// -- and the design it came from shows neither.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DVPageDocument pageWith(Map<String, Object?> properties) {
  final DVPageDocument document = DVPageDocument(route: '/clipped');
  final DVPageDocumentEditor editor = DVPageDocumentEditor(document);
  DVPageNode text = DVPageNode.text('A title long enough to need more room');
  properties.forEach((String name, Object? value) {
    text = text.withProperty(name, value);
  });
  editor.insert(text, parent: document.root.id);
  return document;
}

Text textIn(WidgetTester tester) =>
    tester.widget<Text>(find.byType(Text).first);

Future<void> pump(WidgetTester tester, DVPageDocument document) =>
    tester.pumpWidget(MaterialApp(home: DVPageDocumentRenderer(document)));

void main() {
  testWidgets('a node that names its lines gets them',
      (WidgetTester tester) async {
    await pump(tester, pageWith(const <String, Object?>{'maxLines': 1}));

    expect(textIn(tester).maxLines, 1);
    // And the ellipsis with it: a line limit that clips mid-word looks like
    // a rendering fault, and every design that sets one means the ellipsis.
    expect(textIn(tester).overflow, TextOverflow.ellipsis);
  });

  testWidgets('a node that names none is not limited',
      (WidgetTester tester) async {
    await pump(tester, pageWith(const <String, Object?>{}));

    expect(textIn(tester).maxLines, isNull);
  });

  testWidgets('clipping without an ellipsis is possible, and asked for',
      (WidgetTester tester) async {
    await pump(tester, pageWith(
        const <String, Object?>{'maxLines': 2, 'overflow': 'clip'}));

    expect(textIn(tester).maxLines, 2);
    expect(textIn(tester).overflow, TextOverflow.clip);
  });

  test('the limit is in the exported source', () {
    final String source =
        pageWith(const <String, Object?>{'maxLines': 1}).toDartSource();

    expect(source, contains('.maxLines(1)'));
  });
}
