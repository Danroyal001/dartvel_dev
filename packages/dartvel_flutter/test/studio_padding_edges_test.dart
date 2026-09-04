// Padding on four sides.
//
// A page document could say one padding number, and a design almost never
// has one: 24 across against 8 down is the shape of a card, and the import
// that had to collapse it kept the largest -- so every card came out with
// three times the vertical padding the designer drew. Flutter has had
// EdgeInsets since the beginning and DVModifier has paddingOnly; the page
// document was the only thing that could not say it.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DVPageDocument pageWith(Map<String, Object?> properties) {
  final DVPageDocument document = DVPageDocument(route: '/padded');
  final DVPageDocumentEditor editor = DVPageDocumentEditor(document);
  DVPageNode box = DVPageNode.box(layout: 'list');
  properties.forEach((String name, Object? value) {
    box = box.withProperty(name, value);
  });
  editor.insert(box, parent: document.root.id);
  editor.insert(DVPageNode.text('inside'), parent: box.id);
  return document;
}

/// What the built box actually leaves round its child.
EdgeInsets insetsIn(WidgetTester tester) {
  final Padding padding = tester
      .widgetList<Padding>(find.ancestor(
        of: find.text('inside'),
        matching: find.byType(Padding),
      ))
      .firstWhere((Padding p) => p.padding != EdgeInsets.zero);
  return padding.padding as EdgeInsets;
}

Future<void> pump(WidgetTester tester, DVPageDocument document) =>
    tester.pumpWidget(MaterialApp(home: DVPageDocumentRenderer(document)));

void main() {
  testWidgets('one number is still all four sides', (WidgetTester tester) async {
    await pump(tester, pageWith(const <String, Object?>{'padding': 16}));

    expect(insetsIn(tester), const EdgeInsets.all(16));
  });

  testWidgets('each side can be its own', (WidgetTester tester) async {
    await pump(tester, pageWith(const <String, Object?>{
      'paddingLeft': 24,
      'paddingTop': 8,
      'paddingRight': 24,
      'paddingBottom': 12,
    }));

    expect(insetsIn(tester),
        const EdgeInsets.only(left: 24, top: 8, right: 24, bottom: 12));
  });

  testWidgets('a side overrides the one number, and the rest keep it',
      (WidgetTester tester) async {
    // The way a designer works: a gutter everywhere and one edge different.
    await pump(tester, pageWith(const <String, Object?>{
      'padding': 16,
      'paddingBottom': 0,
    }));

    expect(insetsIn(tester),
        const EdgeInsets.only(left: 16, top: 16, right: 16, bottom: 0));
  });

  test('the exported source says the four sides once', () {
    final DVPageDocument document = pageWith(const <String, Object?>{
      'paddingLeft': 24,
      'paddingTop': 8,
      'paddingRight': 24,
      'paddingBottom': 12,
    });

    final String source = document.toDartSource();

    expect(source,
        contains('.paddingOnly(left: 24.0, top: 8.0, right: 24.0, bottom: 12.0)'));
    // Not four calls, each undoing the last: a modifier replaces the padding
    // it is given, so the last one written would be the only one that ran.
    expect('.paddingOnly('.allMatches(source).length, 1);
    expect(source, isNot(contains('.padding(')));
  });

  test('one number still exports as one number', () {
    final String source =
        pageWith(const <String, Object?>{'padding': 16}).toDartSource();

    expect(source, contains('.padding(16.0)'));
    expect(source, isNot(contains('paddingOnly')));
  });
}
