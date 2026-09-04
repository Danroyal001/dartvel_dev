// Borders and opacity in a page document.
//
// DVModifier has drawn borders and faded boxes since it was written; a page
// document had no way to ask for either. A design's bordered card, its
// outlined input and its half-faded overlay all came through as plain boxes
// -- rendered, plausible, and not the design.
//
// A border is two values that make one decision. Colour and width apply
// separately in the property table, and separately they cannot compose: a
// width with no colour is a border nobody can see, and a colour applied first
// then overwritten by a width is a border of the wrong thickness. The apply
// step is given the whole property map for that reason.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DVPageDocument pageWith(Map<String, Object?> properties) {
  final DVPageDocument document = DVPageDocument(route: '/bordered');
  final DVPageDocumentEditor editor = DVPageDocumentEditor(document);
  DVPageNode box = DVPageNode.box();
  properties.forEach((String name, Object? value) {
    box = box.withProperty(name, value);
  });
  editor.insert(box, parent: document.root.id);
  editor.insert(DVPageNode.text('inside'), parent: box.id);
  return document;
}

Future<void> pump(WidgetTester tester, DVPageDocument document) =>
    tester.pumpWidget(MaterialApp(home: DVPageDocumentRenderer(document)));

/// The decoration of the box the properties were put on.
BoxDecoration? decorationIn(WidgetTester tester) {
  for (final Element element in find.byType(Container).evaluate()) {
    final Container container = element.widget as Container;
    final Decoration? decoration = container.decoration;
    if (decoration is BoxDecoration && decoration.border != null) {
      return decoration;
    }
  }
  return null;
}

void main() {
  testWidgets('a bordered box is drawn with the colour and width it names',
      (WidgetTester tester) async {
    await pump(tester, pageWith(const <String, Object?>{
      'borderColor': '#112233',
      'borderWidth': 2,
    }));

    final BoxDecoration? decoration = decorationIn(tester);
    expect(decoration, isNotNull, reason: 'nothing drew a border');
    final BorderSide side = (decoration!.border! as Border).top;
    expect(side.color, const Color(0xFF112233));
    expect(side.width, 2);
  });

  testWidgets('a colour with no width still draws', (WidgetTester tester) async {
    // A designer who set a colour and left the default width means one point,
    // not nothing.
    await pump(tester, pageWith(const <String, Object?>{'borderColor': '#112233'}));

    expect(decorationIn(tester), isNotNull);
  });

  testWidgets('a width with no colour draws nothing', (WidgetTester tester) async {
    // A border nobody can see is not a border, and picking a colour for the
    // designer would put a line in the design that nobody chose.
    await pump(tester, pageWith(const <String, Object?>{'borderWidth': 4}));

    expect(decorationIn(tester), isNull);
  });

  testWidgets('a faded box is faded', (WidgetTester tester) async {
    await pump(tester, pageWith(const <String, Object?>{'opacity': 0.5}));

    final Iterable<Opacity> faded =
        tester.widgetList<Opacity>(find.byType(Opacity));
    expect(faded.map((Opacity o) => o.opacity), contains(0.5));
  });

  testWidgets('an opacity outside the range does not black the box out',
      (WidgetTester tester) async {
    // Flutter asserts on an opacity above one, which would take the whole
    // page down over a value a document can easily carry.
    await pump(tester, pageWith(const <String, Object?>{'opacity': 4}));

    expect(find.text('inside'), findsOneWidget);
  });

  test('both are offered by the inspector', () {
    final Iterable<String> names =
        dvStudioProperties.map((DVStudioProperty p) => p.name);

    expect(names, containsAll(<String>['borderColor', 'borderWidth', 'opacity']));
  });

  test('the exported source carries them', () {
    final String source = pageWith(const <String, Object?>{
      'borderColor': '#112233',
      'borderWidth': 2,
      'opacity': 0.5,
    }).toDartSource();

    expect(source, contains('border'));
    expect(source, contains('opacity'));
  });
}
