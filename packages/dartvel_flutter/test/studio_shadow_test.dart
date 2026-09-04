// A box's shadow.
//
// Every card in every design has one, and a page document could not say it:
// an imported design came out flat, which reads as a rendering bug rather
// than as a property nobody carried across. DVModifier has taken a shadow
// list since it was written; the document, the inspector and the export
// simply had no name for it.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DVPageDocument pageWith(Map<String, Object?> properties) {
  final DVPageDocument document = DVPageDocument(route: '/shadowed');
  final DVPageDocumentEditor editor = DVPageDocumentEditor(document);
  DVPageNode box = DVPageNode.box(layout: 'list');
  properties.forEach((String name, Object? value) {
    box = box.withProperty(name, value);
  });
  editor.insert(box, parent: document.root.id);
  editor.insert(DVPageNode.text('inside'), parent: box.id);
  return document;
}

/// The shadows the built box actually paints.
List<BoxShadow> shadowsIn(WidgetTester tester) {
  final Iterable<Container> boxes = tester.widgetList<Container>(find.ancestor(
    of: find.text('inside'),
    matching: find.byType(Container),
  ));
  for (final Container box in boxes) {
    final Decoration? decoration = box.decoration;
    if (decoration is BoxDecoration && decoration.boxShadow != null) {
      return decoration.boxShadow!;
    }
  }
  return const <BoxShadow>[];
}

Future<void> pump(WidgetTester tester, DVPageDocument document) =>
    tester.pumpWidget(MaterialApp(home: DVPageDocumentRenderer(document)));

void main() {
  testWidgets('a box with a shadow colour casts one', (WidgetTester tester) async {
    await pump(tester, pageWith(const <String, Object?>{
      'shadowColor': '#33000000',
      'shadowY': 4,
      'shadowBlur': 12,
    }));

    final List<BoxShadow> shadows = shadowsIn(tester);
    expect(shadows, hasLength(1));
    expect(shadows.single.color, const Color(0x33000000));
    expect(shadows.single.offset, const Offset(0, 4));
    expect(shadows.single.blurRadius, 12);
  });

  testWidgets('a spread comes across too', (WidgetTester tester) async {
    await pump(tester, pageWith(const <String, Object?>{
      'shadowColor': '#33000000',
      'shadowSpread': 2,
    }));

    expect(shadowsIn(tester).single.spreadRadius, 2);
  });

  testWidgets('no colour is no shadow', (WidgetTester tester) async {
    // A blur with nothing to blur is not a shadow. Drawing black by default
    // would put a shadow under every box that named a radius.
    await pump(tester, pageWith(const <String, Object?>{'shadowBlur': 12}));

    expect(shadowsIn(tester), isEmpty);
  });

  test('the shadow is exported once, with all of its parts', () {
    final String source = pageWith(const <String, Object?>{
      'shadowColor': '#33000000',
      'shadowX': 1,
      'shadowY': 4,
      'shadowBlur': 12,
      'shadowSpread': 2,
    }).toDartSource();

    expect(
        source,
        contains('.shadow(<BoxShadow>[BoxShadow(color: Color(0x33000000), '
            'offset: Offset(1.0, 4.0), blurRadius: 12.0, spreadRadius: 2.0)])'));
    expect('.shadow('.allMatches(source).length, 1);
  });
}
