// A box whose corners are not all the same.
//
// A sheet rounded at the top and square at the bottom, a card in a stack
// rounded only where it shows: every design system has them, and a page
// document could say one radius. The import that met one had to pick a
// number, so a bottom sheet came through as a floating rounded rectangle.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DVPageDocument pageWith(Map<String, Object?> properties) {
  final DVPageDocument document = DVPageDocument(route: '/rounded');
  final DVPageDocumentEditor editor = DVPageDocumentEditor(document);
  DVPageNode box = DVPageNode.box(layout: 'list');
  properties.forEach((String name, Object? value) {
    box = box.withProperty(name, value);
  });
  editor.insert(box, parent: document.root.id);
  editor.insert(DVPageNode.text('inside'), parent: box.id);
  return document;
}

BorderRadius? radiusIn(WidgetTester tester) {
  for (final Container box in tester.widgetList<Container>(find.ancestor(
    of: find.text('inside'),
    matching: find.byType(Container),
  ))) {
    final Decoration? decoration = box.decoration;
    if (decoration is BoxDecoration && decoration.borderRadius != null) {
      return decoration.borderRadius! as BorderRadius;
    }
  }
  return null;
}

Future<void> pump(WidgetTester tester, DVPageDocument document) =>
    tester.pumpWidget(MaterialApp(home: DVPageDocumentRenderer(document)));

void main() {
  testWidgets('one number is still every corner', (WidgetTester tester) async {
    await pump(tester, pageWith(const <String, Object?>{'rounded': 12}));

    expect(radiusIn(tester), BorderRadius.circular(12));
  });

  testWidgets('a sheet rounded at the top is square at the bottom',
      (WidgetTester tester) async {
    await pump(tester, pageWith(const <String, Object?>{
      'roundedTopLeft': 16,
      'roundedTopRight': 16,
    }));

    expect(
        radiusIn(tester),
        const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ));
  });

  testWidgets('a corner overrides the one number, and the rest keep it',
      (WidgetTester tester) async {
    await pump(tester, pageWith(const <String, Object?>{
      'rounded': 8,
      'roundedBottomRight': 0,
    }));

    expect(
        radiusIn(tester),
        const BorderRadius.only(
          topLeft: Radius.circular(8),
          topRight: Radius.circular(8),
          bottomLeft: Radius.circular(8),
        ));
  });

  test('the corners are exported once, all four of them', () {
    final String source = pageWith(const <String, Object?>{
      'roundedTopLeft': 16,
      'roundedTopRight': 16,
    }).toDartSource();

    expect(source, contains('.radius(BorderRadius.only('));
    expect(source, contains('topLeft: Radius.circular(16.0)'));
    expect('.radius('.allMatches(source).length, 1);
    expect(source, isNot(contains('.rounded(')));
  });

  test('one number still exports as one number', () {
    final String source =
        pageWith(const <String, Object?>{'rounded': 12}).toDartSource();

    expect(source, contains('.rounded(12.0)'));
    expect(source, isNot(contains('BorderRadius.only')));
  });
}
