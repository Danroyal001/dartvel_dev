import 'package:dartvel_core/dartvel.dart';

import '../catalog_rows.dart';

/// GET /api/catalog: the coffees on the shelf, from the server's database.
///
/// The generated server opens SQLite on its first run when nothing else is
/// configured, so this creates its table and seeds it the first time it is
/// asked. The app gets `getCatalogApi()` for it, typed.
Future<List<Map<String, Object?>>> catalog() async {
  const DVDatabase db = DVDatabase();
  await db.execute(
    'CREATE TABLE IF NOT EXISTS shop_catalog ('
    'slug TEXT PRIMARY KEY, name TEXT NOT NULL, origin TEXT NOT NULL, '
    'roast TEXT NOT NULL, notes TEXT NOT NULL, description TEXT NOT NULL, '
    'priceCents INTEGER NOT NULL, weightGrams INTEGER NOT NULL, '
    'published INTEGER NOT NULL)',
  );
  final List<Map<String, Object?>> count =
      await db.query('SELECT COUNT(*) AS n FROM shop_catalog');
  if (((count.first['n'] as num?) ?? 0) == 0) {
    for (final Map<String, Object?> row in catalogRows) {
      await db.execute(
        'INSERT INTO shop_catalog (slug, name, origin, roast, notes, '
        'description, priceCents, weightGrams, published) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
        <Object?>[
          row['slug'],
          row['name'],
          row['origin'],
          row['roast'],
          row['notes'],
          row['description'],
          row['priceCents'],
          row['weightGrams'],
          row['published'] == true ? 1 : 0,
        ],
      );
    }
  }
  return db.query(
    'SELECT slug, name, origin, roast, notes, description, priceCents, '
    'weightGrams FROM shop_catalog WHERE published = 1 ORDER BY name',
  );
}
