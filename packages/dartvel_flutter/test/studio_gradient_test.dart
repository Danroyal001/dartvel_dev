// A box painted with a gradient.
//
// Hero sections, buttons and cards are painted with them in every design
// system there is, and a page document could only say one flat colour -- so
// a gradient frame imported as nothing at all, because the fill it carries
// is not a solid one. DVModifier has taken a gradient since it was written.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DVPageDocument pageWith(Map<String, Object?> properties) {
  final DVPageDocument document = DVPageDocument(route: '/painted');
  final DVPageDocumentEditor editor = DVPageDocumentEditor(document);
  DVPageNode box = DVPageNode.box(layout: 'list');
  properties.forEach((String name, Object? value) {
    box = box.withProperty(name, value);
  });
  editor.insert(box, parent: document.root.id);
  editor.insert(DVPageNode.text('inside'), parent: box.id);
  return document;
}

LinearGradient? gradientIn(WidgetTester tester) {
  for (final Container box in tester.widgetList<Container>(find.ancestor(
    of: find.text('inside'),
    matching: find.byType(Container),
  ))) {
    final Decoration? decoration = box.decoration;
    if (decoration is BoxDecoration && decoration.gradient != null) {
      return decoration.gradient! as LinearGradient;
    }
  }
  return null;
}

Future<void> pump(WidgetTester tester, DVPageDocument document) =>
    tester.pumpWidget(MaterialApp(home: DVPageDocumentRenderer(document)));

void main() {
  testWidgets('two colours paint a gradient', (WidgetTester tester) async {
    await pump(tester, pageWith(const <String, Object?>{
      'gradientFrom': '#FF112233',
      'gradientTo': '#FF445566',
    }));

    final LinearGradient? gradient = gradientIn(tester);
    expect(gradient, isNotNull);
    expect(gradient!.colors,
        <Color>[const Color(0xFF112233), const Color(0xFF445566)]);
  });

  testWidgets('with no angle it runs down the box',
      (WidgetTester tester) async {
    // Figma's default and the one every hero uses.
    await pump(tester, pageWith(const <String, Object?>{
      'gradientFrom': '#FF112233',
      'gradientTo': '#FF445566',
    }));

    expect(gradientIn(tester)!.begin, Alignment.topCenter);
    expect(gradientIn(tester)!.end, Alignment.bottomCenter);
  });

  testWidgets('a quarter turn runs it across', (WidgetTester tester) async {
    await pump(tester, pageWith(const <String, Object?>{
      'gradientFrom': '#FF112233',
      'gradientTo': '#FF445566',
      'gradientAngle': 90,
    }));

    final LinearGradient gradient = gradientIn(tester)!;
    expect(gradient.begin, isA<Alignment>());
    expect((gradient.begin as Alignment).x, closeTo(-1, 0.001));
    expect((gradient.begin as Alignment).y, closeTo(0, 0.001));
    expect((gradient.end as Alignment).x, closeTo(1, 0.001));
  });

  testWidgets('one colour is not a gradient', (WidgetTester tester) async {
    // A gradient from a colour to nothing is not something a designer drew.
    await pump(tester,
        pageWith(const <String, Object?>{'gradientFrom': '#FF112233'}));

    expect(gradientIn(tester), isNull);
  });

  test('it is exported once, with both colours and its direction', () {
    final String source = pageWith(const <String, Object?>{
      'gradientFrom': '#FF112233',
      'gradientTo': '#FF445566',
      'gradientAngle': 90,
    }).toDartSource();

    expect(source, contains('.gradient(LinearGradient('));
    expect(source, contains('Color(0xFF112233)'));
    expect(source, contains('Color(0xFF445566)'));
    expect('.gradient('.allMatches(source).length, 1);
  });
}
