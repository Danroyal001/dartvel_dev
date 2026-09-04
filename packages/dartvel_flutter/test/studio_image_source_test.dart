// Where a page's image comes from.
//
// A page document could describe exactly one kind of image: a URL. Assets,
// files and stored bytes were unreachable from a page, which made an imported
// design permanently dependent on somebody else's address staying up -- and a
// Figma import is handed URLs that expire.
//
// The node says which kind it is, and says nothing when it is a URL, so every
// document written before this reads exactly as it did.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DVPageDocument pageWith(Map<String, Object?> properties) {
  final DVPageDocument document = DVPageDocument(route: '/pictured');
  final DVPageDocumentEditor editor = DVPageDocumentEditor(document);
  DVPageNode node = DVPageNode.image('logo.png');
  properties.forEach((String name, Object? value) {
    node = node.withProperty(name, value);
  });
  editor.insert(node, parent: document.root.id);
  return document;
}

Future<ImageProvider<Object>?> providerIn(
  WidgetTester tester,
  DVPageDocument document,
) async {
  await tester.pumpWidget(MaterialApp(home: DVPageDocumentRenderer(document)));
  final Iterable<Image> images = tester.widgetList<Image>(find.byType(Image));
  return images.isEmpty ? null : images.first.image;
}

void main() {
  testWidgets('a node that says nothing is a URL, as it always was',
      (WidgetTester tester) async {
    final ImageProvider<Object>? provider = await providerIn(
      tester,
      pageWith(const <String, Object?>{'src': 'https://example.com/a.png'}),
    );

    expect(provider, isA<NetworkImage>());
  });

  testWidgets('a stored node reads from storage', (WidgetTester tester) async {
    final ImageProvider<Object>? provider = await providerIn(
      tester,
      pageWith(const <String, Object?>{
        'src': 'figma/1-2/logo.png',
        'source': 'stored',
      }),
    );

    expect(provider, const DVStoredImage('figma/1-2/logo.png'));
  });

  testWidgets('an asset node reads from the bundle', (WidgetTester tester) async {
    final ImageProvider<Object>? provider = await providerIn(
      tester,
      pageWith(const <String, Object?>{
        'src': 'assets/logo.png',
        'source': 'asset',
      }),
    );

    expect(provider, isA<AssetImage>());
  });

  testWidgets('a source nobody knows still draws something',
      (WidgetTester tester) async {
    // The same leniency the image reader has, for the same reason: a page
    // that will not render because one word is wrong is worse than a page
    // that tries the address.
    final ImageProvider<Object>? provider = await providerIn(
      tester,
      pageWith(const <String, Object?>{
        'src': 'https://example.com/a.png',
        'source': 'carrier-pigeon',
      }),
    );

    expect(provider, isA<NetworkImage>());
  });

  test('the export writes the source the page draws', () {
    // The rule the property table already keeps: a page that renders from
    // storage and exports a network fetch is a page that changes when it
    // leaves the builder.
    final String stored = pageWith(const <String, Object?>{
      'src': 'figma/1-2/logo.png',
      'source': 'stored',
    }).toDartSource();

    expect(stored, contains("DVImage.stored('figma/1-2/logo.png')"));

    final String network = pageWith(const <String, Object?>{
      'src': 'https://example.com/a.png',
    }).toDartSource();

    expect(network, contains("DVImage.network('https://example.com/a.png')"));
  });
}
