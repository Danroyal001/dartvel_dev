// How an image fills the box it is in.
//
// A design says it per image: a photograph fills its frame and is cropped, a
// logo fits inside and is not. A page document said nothing, so every image
// took the renderer's default and half of them came out cropped or stretched
// -- which looks like a bad export rather than a property nobody carried.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DVPageDocument pageWith(Map<String, Object?> properties) {
  final DVPageDocument document = DVPageDocument(route: '/pictured');
  final DVPageDocumentEditor editor = DVPageDocumentEditor(document);
  DVPageNode image = DVPageNode.image('https://example.com/a.png');
  properties.forEach((String name, Object? value) {
    image = image.withProperty(name, value);
  });
  editor.insert(image, parent: document.root.id);
  return document;
}

BoxFit fitIn(WidgetTester tester) =>
    tester.widget<Image>(find.byType(Image)).fit!;

Future<void> pump(WidgetTester tester, DVPageDocument document) =>
    tester.pumpWidget(MaterialApp(home: DVPageDocumentRenderer(document)));

void main() {
  testWidgets('an image that names its fit gets it', (WidgetTester tester) async {
    await pump(tester, pageWith(const <String, Object?>{'fit': 'contain'}));

    expect(fitIn(tester), BoxFit.contain);
  });

  testWidgets('one that names none is still covered',
      (WidgetTester tester) async {
    // The default every document written before this relied on.
    await pump(tester, pageWith(const <String, Object?>{}));

    expect(fitIn(tester), BoxFit.cover);
  });

  testWidgets('a fit nobody recognises is the default, not a crash',
      (WidgetTester tester) async {
    // A document outlives the version that wrote it, and a page that will
    // not render because one word is misspelled is worse than one that
    // shows the picture.
    await pump(tester, pageWith(const <String, Object?>{'fit': 'squish'}));

    expect(fitIn(tester), BoxFit.cover);
  });

  test('the fit is in the exported source', () {
    final String source =
        pageWith(const <String, Object?>{'fit': 'contain'}).toDartSource();

    expect(source, contains('fit: BoxFit.contain'));
  });

  test('an image with the default fit exports no fit', () {
    // The export is the page as somebody would have written it, and nobody
    // writes the default.
    final String source = pageWith(const <String, Object?>{}).toDartSource();

    expect(source, isNot(contains('BoxFit')));
  });
}
