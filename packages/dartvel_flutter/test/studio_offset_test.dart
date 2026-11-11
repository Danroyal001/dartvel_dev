// A moved layer in a page document.
//
// DVModifier.offset moves a box after layout; a page built in Studio has to
// be able to say the same thing, or a design made there and the same design
// written in code draw different pages. Two numbers, x and y, because that is
// what an inspector shows -- and one call in the export, because it is one
// modifier.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DVPageDocument pageWith(Map<String, Object?> properties) {
  final DVPageDocument document = DVPageDocument(route: '/moved');
  final DVPageDocumentEditor editor = DVPageDocumentEditor(document);
  DVPageNode box = DVPageNode.box();
  properties.forEach((String name, Object? value) {
    box = box.withProperty(name, value);
  });
  editor.insert(box, parent: document.root.id);
  editor.insert(DVPageNode.text('inside'), parent: box.id);
  return document;
}

Future<Offset> drawnAt(
  WidgetTester tester,
  Map<String, Object?> properties,
) async {
  await tester.pumpWidget(
    MaterialApp(home: DVPageDocumentRenderer(pageWith(properties))),
  );
  return tester.getTopLeft(find.text('inside'));
}

DVStudioProperty property(String name) =>
    dvStudioProperties.firstWhere((DVStudioProperty p) => p.name == name);

void main() {
  testWidgets('x and y move the layer by that many pixels', (
    WidgetTester tester,
  ) async {
    final Offset home = await drawnAt(tester, <String, Object?>{});
    expect(
      await drawnAt(tester, <String, Object?>{'offsetX': 12, 'offsetY': 40}) -
          home,
      const Offset(12, 40),
    );
    expect(
      await drawnAt(tester, <String, Object?>{'offsetY': 40}) - home,
      const Offset(0, 40),
      reason: 'y alone moves it down only',
    );
    expect(
      await drawnAt(tester, <String, Object?>{'offsetX': 'far'}) - home,
      Offset.zero,
      reason: 'a value that is not a number moves nothing',
    );
  });

  test('the export writes one offset call for the pair', () {
    final Map<String, Object?> both = <String, Object?>{
      'offsetX': 12,
      'offsetY': 40,
    };
    final List<String> written = <String>[
      for (final String name in <String>['offsetX', 'offsetY'])
        if (property(name).source(both[name], both) case final String call)
          call,
    ];
    expect(written, <String>['.offset(12.0, 40.0)']);

    final Map<String, Object?> yOnly = <String, Object?>{'offsetY': 40};
    expect(property('offsetY').source(40, yOnly), '.offset(0.0, 40.0)');
  });
}
