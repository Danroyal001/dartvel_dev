// The layouts a page document can ask for.
//
// The renderer and the Dart exporter each carry their own switch over the
// layout name, which is the arrangement the property table was fixed for:
// two lists of the same thing drift, and the drift is silent because an
// unknown name falls through to a column in both. A wrapping row was missing
// from both -- DVBox.wrapLine has existed the whole time -- so a chip row or
// a tag list, which is the commonest wrapping thing in any design, came
// through as a single row that runs off the side of a phone.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DVPageDocument pageWith(String layout) {
  final DVPageDocument document = DVPageDocument(route: '/laid-out');
  final DVPageDocumentEditor editor = DVPageDocumentEditor(document);
  final DVPageNode box = DVPageNode.box(layout: layout);
  editor.insert(box, parent: document.root.id);
  editor.insert(DVPageNode.text('one'), parent: box.id);
  editor.insert(DVPageNode.text('two'), parent: box.id);
  return document;
}

void main() {
  testWidgets('a wrapping row wraps', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: DVPageDocumentRenderer(pageWith('wrap'))),
    );

    expect(find.byType(Wrap), findsOneWidget);
    expect(find.text('one'), findsOneWidget);
    expect(find.text('two'), findsOneWidget);
  });

  test('a wrapping row exports as one', () {
    // An export that compiles and lays out differently is the failure this
    // whole path exists to stop: it is noticed after somebody has started
    // editing the exported page, by which time going back means losing it.
    expect(pageWith('wrap').toDartSource(), contains('DVBox.wrapLine('));
  });

  testWidgets('every layout the document names renders and exports',
      (WidgetTester tester) async {
    // The guard the two switches needed. A name handled in one of them is a
    // page that previews correctly and exports to something else, and
    // nothing says so, because both fall through to a column.
    for (final String layout in dvStudioLayouts) {
      final DVPageDocument document = pageWith(layout);

      await tester.pumpWidget(
        MaterialApp(home: DVPageDocumentRenderer(document)),
      );
      expect(tester.takeException(), isNull, reason: '$layout did not render');
      expect(find.text('one'), findsOneWidget,
          reason: '$layout dropped a child');

      expect(document.toDartSource(), contains('DVBox'),
          reason: '$layout exported nothing');
    }
  });

  test('the catalogue names the layouts the builder can produce', () {
    expect(
      dvStudioLayouts,
      containsAll(<String>['list', 'row', 'wrap', 'grid', 'stack', 'single']),
    );
  });

  test('the palette offers a box for every layout but one', () {
    // Four hand-written entries were a fourth list of the same thing, and the
    // wrapping row was missing from every one of them. `single` is left out
    // on purpose: it is what a box with one child already is, rather than
    // something anybody drags in.
    final Set<String> offered = DVStudioPaletteItem.defaults
        .map((DVStudioPaletteItem item) => item.create())
        .where((DVPageNode node) => node.type == 'box')
        .map((DVPageNode node) => node.layout)
        .toSet();

    expect(offered, dvStudioLayouts.toSet().difference(<String>{'single'}));
  });

  test('the column keeps the name people call it', () {
    // Its name in a document is `list`, because it is the default and a page
    // written before there were others has no layout at all. Nobody drags a
    // "List" into a canvas expecting a column.
    expect(dvStudioLayoutLabel('list'), 'Column');
    expect(dvStudioLayoutLabel('wrap'), 'Wrap');
  });
}
