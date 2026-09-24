import 'package:dartvel_core/dartvel.dart';
// The record layer, which an application does not name and this one has to.
//
// A backend function cannot import the generated model: models.g.dart
// imports Flutter, and this runs in a pure Dart server. So the one place in
// this project that should most obviously be `Product.all()` writes the
// model's table, key, columns and types out a second time instead, and
// re-types every column by hand on the way back because it is reading rows
// rather than products.
//
// This import is here to make that visible rather than ambient. It goes when
// the generator emits a Flutter-free model surface for the server.
import 'package:dartvel_core/framework.dart';

import '../catalog_rows.dart';

/// The Product model's records, as the server keeps them: its table and key,
/// read and written through DVRecordTable, which is the model's own plumbing
/// named by hand because the server cannot reach the model.
DVRecordTable _products() => DVRecordTable(
  table: dvTenantTable('products'),
  key: 'slug',
  columns: catalogRows.first.keys.toList(growable: false),
);

/// GET /api/catalog: the coffees on the shelf, from the server's Product
/// records.
///
/// The generated server opens SQLite on its first run when nothing else is
/// configured, so the first request seeds the season's coffees as Product
/// records when there are none. After that the records are the truth. The
/// app gets `getCatalogApi()` for it, typed.
Future<List<Map<String, Object?>>> catalog() async {
  final DVRecordTable products = _products();
  await products.ensureSchema();
  List<DVRecord> records = await products.all(withDeleted: true);
  if (records.isEmpty) {
    for (final Map<String, Object?> row in catalogRows) {
      await products.write(<String, Object?>{
        ...row,
        'published': row['published'] == true ? 1 : 0,
      });
    }
    records = await products.all(withDeleted: true);
  }
  final List<Map<String, Object?>> shelf = <Map<String, Object?>>[
    for (final DVRecord record in records)
      if (record.deletedAt == null) _typed(record.values),
  ]..retainWhere((Map<String, Object?> row) => row['published'] == true);
  return shelf..sort(
    (Map<String, Object?> a, Map<String, Object?> b) =>
        '${a['name']}'.compareTo('${b['name']}'),
  );
}

/// A stored row as the model's types. The model's columns have TEXT
/// affinity, so a number or a flag can come back as a string.
Map<String, Object?> _typed(Map<String, Object?> values) {
  int number(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
  final Object? published = values['published'];
  return <String, Object?>{
    for (final String column in catalogRows.first.keys)
      column: '${values[column] ?? ''}',
    'priceCents': number(values['priceCents']),
    'weightGrams': number(values['weightGrams']),
    'published':
        published == true ||
        published == 1 ||
        published == '1' ||
        published == 'true',
  };
}
