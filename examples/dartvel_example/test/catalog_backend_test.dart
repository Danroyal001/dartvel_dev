// The catalogue backend function against a real SQLite database, the way the
// generated server runs it.
//
// It reads the Product model's own table, so the coffees the shop is served
// are the Product records Studio lists and edits. It used to keep a table of
// its own, and an edit in Studio changed nothing anybody saw.
import 'package:dartvel_example/backend/catalog_rows.dart';
import 'package:dartvel_example/backend/functions/catalog.get.dart';
import 'package:dartvel_example/dartvel_client/dartvel_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// The products table as Studio on the backend reads and writes it: the
/// Product model's table and key, through DVRecordTable.
DVRecordTable _studioProducts(DVDatabaseAdapter database) => DVRecordTable(
  table: 'products',
  key: 'slug',
  columns: catalogRows.first.keys.toList(),
  database: database,
);

void main() {
  late SqliteDVDatabaseAdapter database;

  setUp(() {
    database = SqliteDVDatabaseAdapter.memory();
    DV.Database.configure(database);
  });

  tearDown(() => database.close());

  test('seeds the Product records on the first request and only then', () async {
    final List<Map<String, Object?>> first = await catalog();
    final List<Map<String, Object?>> second = await catalog();
    expect(first, hasLength(catalogRows.length));
    expect(second, hasLength(catalogRows.length));
    expect(
      await _studioProducts(database).all(),
      hasLength(catalogRows.length),
    );
  });

  test('a product edited as Studio edits it is what the shop is served', () async {
    await catalog();
    final DVRecordTable products = _studioProducts(database);
    final DVRecord huila = (await products.read('huila'))!;
    await products.write(<String, Object?>{
      ...huila.values,
      'name': 'Huila Reserve',
      'priceCents': 2100,
    }, base: huila);

    final Map<String, Object?> served = (await catalog()).firstWhere(
      (Map<String, Object?> row) => row['slug'] == 'huila',
    );
    expect(served['name'], 'Huila Reserve');
    expect(served['priceCents'], 2100);
  });

  test('answers with published coffees only, by name, typed', () async {
    await catalog();
    final DVRecordTable products = _studioProducts(database);
    final DVRecord nyeri = (await products.read('nyeri'))!;
    await products.write(<String, Object?>{
      ...nyeri.values,
      'published': 0,
    }, base: nyeri);

    final List<Map<String, Object?>> rows = await catalog();
    final List<Object?> names = rows
        .map((Map<String, Object?> r) => r['name'])
        .toList();
    expect(names, isNot(contains('Nyeri')));
    expect(
      names,
      <Object?>[...names]..sort((Object? a, Object? b) => '$a'.compareTo('$b')),
    );
    expect(rows.first['priceCents'], isA<int>());
    expect(rows.first['weightGrams'], isA<int>());
    expect(rows.first['published'], isTrue);
  });
}
