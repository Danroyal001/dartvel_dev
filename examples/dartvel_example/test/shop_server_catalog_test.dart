// Served by its own web-server, the shop shows the server's Product records.
//
// The shelf was seeded from the in-code coffees into the browser's own store,
// so on a web-server the shop listed six coffees while Studio's Product table
// on that server was empty, and editing a product there changed nothing the
// shop showed.
import 'package:dartvel_example/dartvel_client/dartvel_client.dart';
import 'package:dartvel_example/shop/catalog.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _row(String slug, String name) => <String, Object?>{
  'slug': slug,
  'name': name,
  'origin': 'Huila, Colombia',
  'roast': 'medium',
  'notes': 'Red apple',
  'description': 'Edited in Studio.',
  'priceCents': 2100,
  'weightGrams': 250,
  'published': true,
};

void main() {
  setUp(() {
    DV.Database.configure(MemoryDVDatabaseAdapter());
    resetShopStore();
  });

  tearDown(() {
    DVAuth.servedByOwnServer = const bool.fromEnvironment('DARTVEL_WEB_SERVER');
    serverCatalog = getCatalogApi;
  });

  test('on its own server the shelf is the server\'s Product records', () async {
    DVAuth.servedByOwnServer = true;
    int asked = 0;
    serverCatalog = () async {
      asked += 1;
      return <Map<String, Object?>>[_row('huila', 'Huila Reserve')];
    };

    await openShopStore();

    expect(asked, 1);
    final List<Product> shelf = await Product.all();
    expect(shelf.map((Product p) => p.name), <String>['Huila Reserve']);
    expect(shelf.single.priceCents, 2100);
  });

  test('on-device, the shelf is seeded from the season\'s coffees', () async {
    DVAuth.servedByOwnServer = false;
    serverCatalog = () async => fail('the on-device demo has no server');

    await openShopStore();

    expect(await Product.all(), hasLength(seedCatalog.length));
  });
}
