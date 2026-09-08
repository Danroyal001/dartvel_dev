// A border on one side of a box.
//
// The document could say a colour and a width, and the width went to
// Border.all -- so a box with a rule under it was a box with a line on all
// four sides. That is not a missing style, it is a wrong one: the commonest
// border in any design is a single hairline under a header or between rows,
// and every one of them came through as a box.
//
// Four widths beside the colour, the same shape the corners and the shadow
// already use: the colour owns the decision and the sides are its
// companions, because a side applied on its own would be a line nobody chose
// a colour for.
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

/// The border on the box that has one, ignoring the containers around it.
Border? borderOf(WidgetTester tester) {
  for (final Element element in find.byType(Container).evaluate()) {
    final Container container = element.widget as Container;
    final Object? decoration = container.decoration;
    if (decoration is! BoxDecoration) continue;
    final BoxBorder? border = decoration.border;
    if (border is Border) return border;
  }
  return null;
}

void main() {
  testWidgets('a rule under a header is a rule under a header',
      (WidgetTester tester) async {
    await pump(
      tester,
      pageWith(const <String, Object?>{
        'borderColor': '#112233',
        'borderBottomWidth': 1,
      }),
    );

    final Border border = borderOf(tester)!;
    expect(border.bottom.width, 1);
    expect(border.bottom.color, const Color(0xFF112233));
    expect(border.top, BorderSide.none);
    expect(border.left, BorderSide.none);
    expect(border.right, BorderSide.none);
  });

  testWidgets('two sides is two sides', (WidgetTester tester) async {
    await pump(
      tester,
      pageWith(const <String, Object?>{
        'borderColor': '#112233',
        'borderLeftWidth': 4,
        'borderBottomWidth': 1,
      }),
    );

    final Border border = borderOf(tester)!;
    expect(border.left.width, 4);
    expect(border.bottom.width, 1);
    expect(border.top, BorderSide.none);
  });

  testWidgets('the plain width still draws all four',
      (WidgetTester tester) async {
    // The document that says one width means a box, and every page already
    // written that way has to keep meaning it.
    await pump(
      tester,
      pageWith(const <String, Object?>{
        'borderColor': '#112233',
        'borderWidth': 2,
      }),
    );

    final Border border = borderOf(tester)!;
    expect(border.top.width, 2);
    expect(border.bottom.width, 2);
    expect(border.left.width, 2);
    expect(border.right.width, 2);
  });

  testWidgets('a side without a colour draws nothing',
      (WidgetTester tester) async {
    // A width on its own is a line nobody chose a colour for, and choosing
    // one would put a rule in the design that nobody asked for.
    await pump(
      tester,
      pageWith(const <String, Object?>{'borderBottomWidth': 1}),
    );

    expect(borderOf(tester), isNull);
  });

  test('the sides are exported, and once', () {
    final DVPageDocument document = pageWith(const <String, Object?>{
      'borderColor': '#112233',
      'borderBottomWidth': 1,
    });

    final String source = document.toDartSource();
    expect(source, contains('.border('));
    expect(source, contains('bottom'));
    // The colour owns the decision, so exactly one border call comes out of
    // it however many sides were set.
    expect('.border('.allMatches(source).length, 1);
  });
}
