// A page that is taller than the screen.
//
// Almost every screen in a design is: a phone frame is 844 tall and the
// content runs to 1800. A page document could not say so, so an imported
// design rendered with the yellow-and-black overflow stripe across the
// bottom -- the app looks broken at the first scroll, on the first screen.
// DVBox has scrolled since it was written; the document had no name for it.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DVPageDocument pageWith(
  Map<String, Object?> properties, {
  String layout = 'list',
  int children = 40,
}) {
  // The screen itself, because that is what scrolls: a scrolling box inside
  // a column that does not scroll overflows the column instead.
  final DVPageDocument document = DVPageDocument(route: '/tall');
  DVPageNode box = DVPageNode.box(layout: layout);
  properties.forEach((String name, Object? value) {
    box = box.withProperty(name, value);
  });
  document.root = box;
  final DVPageDocumentEditor editor = DVPageDocumentEditor(document);
  for (int i = 0; i < children; i++) {
    editor.insert(DVPageNode.text('row $i'), parent: box.id);
  }
  return document;
}

Future<void> pump(WidgetTester tester, DVPageDocument document) =>
    tester.pumpWidget(MaterialApp(home: DVPageDocumentRenderer(document)));

void main() {
  testWidgets('a list that says it scrolls does', (WidgetTester tester) async {
    await pump(tester, pageWith(const <String, Object?>{'scroll': true}));

    expect(tester.takeException(), isNull);
    final ScrollableState state = tester.state(find.byType(Scrollable).first);
    expect(state.position.axisDirection, AxisDirection.down);
  });

  testWidgets('a row that says it scrolls scrolls sideways',
      (WidgetTester tester) async {
    // Its own axis, which is the only reading that makes sense: a row that
    // scrolled down would not move at all.
    await pump(tester,
        pageWith(const <String, Object?>{'scroll': true}, layout: 'row'));

    expect(tester.takeException(), isNull);
    final ScrollableState state = tester.state(find.byType(Scrollable).first);
    expect(state.position.axisDirection, AxisDirection.right);
  });

  testWidgets('a list that does not say so still does not scroll',
      (WidgetTester tester) async {
    // The default has to stay put: a page inside a page that scrolled would
    // give a screen two scroll positions and the outer one would stop
    // working.
    await pump(tester, pageWith(const <String, Object?>{}, children: 2));

    expect(find.byType(Scrollable), findsNothing);
  });

  test('the export says it too', () {
    final String source =
        pageWith(const <String, Object?>{'scroll': true}, children: 2)
            .toDartSource();

    expect(source, contains('.scrollable()'));
  });

  test('a scrolling row exports as one', () {
    final String source = pageWith(const <String, Object?>{'scroll': true},
            layout: 'row', children: 2)
        .toDartSource();

    expect(source, contains('DVBox.horizontalScrollable('));
  });
}
