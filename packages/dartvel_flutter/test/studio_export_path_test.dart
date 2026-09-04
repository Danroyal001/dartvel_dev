// Where an exported page's import points.
//
// The export writes a relative import to the generated client, and it wrote
// one level up whatever the page's route was. That is right for a page at
// the top -- lib/pages/pricing.page.dart reaching lib/dartvel_client -- and
// wrong for every nested one: lib/pages/products/[id].page.dart reaching one
// level up finds lib/pages/dartvel_client, which does not exist.
//
// So the file the builder exports for a nested route does not compile, and
// the export is a feature whose whole point is that the result is ordinary
// code somebody can keep.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

DVPageDocument pageAt(String route) {
  final DVPageDocument document = DVPageDocument(route: route, title: 'A page');
  final DVPageDocumentEditor editor = DVPageDocumentEditor(document);
  editor.insert(DVPageNode.text('hello'), parent: document.root.id);
  return document;
}

void main() {
  test('a page at the top reaches the client one level up', () {
    expect(pageAt('/pricing').toDartSource(),
        contains("import '../dartvel_client/dartvel_client.dart';"));
  });

  test('the root page is a top-level page too', () {
    expect(pageAt('/').toDartSource(),
        contains("import '../dartvel_client/dartvel_client.dart';"));
  });

  test('a nested page reaches it from where it actually sits', () {
    // lib/pages/products/[id].page.dart is two levels below lib.
    expect(pageAt('/products/:id').toDartSource(),
        contains("import '../../dartvel_client/dartvel_client.dart';"));
  });

  test('a deeply nested page counts every level', () {
    expect(pageAt('/store/products/:id/reviews').toDartSource(),
        contains("import '../../../../dartvel_client/dartvel_client.dart';"));
  });

  test('the file the page belongs in is named by its route', () {
    // The pages router's own rule, so an exported page dropped into a
    // project is served at the route it was exported from.
    expect(dvStudioPagePath('/'), 'lib/pages/index.page.dart');
    expect(dvStudioPagePath('/pricing'), 'lib/pages/pricing.page.dart');
    expect(dvStudioPagePath('/products/:id'),
        'lib/pages/products/[id].page.dart');
  });
}
