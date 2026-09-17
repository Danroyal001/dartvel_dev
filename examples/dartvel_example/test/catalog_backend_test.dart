// The catalogue backend function against a real SQLite database, the way the
// generated server runs it.
import 'package:dartvel_example/backend/catalog_rows.dart';
import 'package:dartvel_example/backend/functions/catalog.get.dart';
import 'package:dartvel_example/dartvel_client/dartvel_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SqliteDVDatabaseAdapter database;

  setUp(() {
    database = SqliteDVDatabaseAdapter.memory();
    DV.Database.configure(database);
  });

  tearDown(() => database.close());

  test('seeds its table on the first request and only then', () async {
    final List<Map<String, Object?>> first = await catalog();
    final List<Map<String, Object?>> second = await catalog();
    expect(first, hasLength(catalogRows.length));
    expect(second, hasLength(catalogRows.length));
    final List<Map<String, Object?>> stored = await database.query(
      'SELECT slug FROM shop_catalog',
    );
    expect(stored, hasLength(catalogRows.length));
  });

  test('answers with published coffees only, by name', () async {
    await catalog();
    await database.execute(
      "UPDATE shop_catalog SET published = 0 WHERE slug = 'nyeri'",
    );
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
  });
}
