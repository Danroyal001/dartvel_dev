/// Records: one set of operations every database engine implements.
///
/// A model, a Studio page and a queued job are records -- a key, some fields
/// and a version -- and only the engine underneath should know whether they
/// sit in a SQL table or a MongoDB collection. [DVRecordAdapter] is that
/// contract, with a [DVFilter] tree where a SQL string used to be:
/// [DVSqlRecordAdapter] compiles it to parameterised SQL, and a document
/// engine maps the same tree to its own query. See Storage-Neutral Records in
/// NEW_SPEC.md.
library dartvel_core.database.records;

import 'adapter.dart';
import 'framework_tables.dart' show dvEnsureFrameworkTable;

/// How a field is stored, for engines that declare types.
enum DVFieldType {
  text('TEXT'),
  integer('BIGINT'),
  real('DOUBLE PRECISION'),

  /// Stored as 1 or 0 where the engine has no boolean.
  boolean('BIGINT');

  const DVFieldType(this.sql);

  /// The column type the SQL engine declares.
  final String sql;
}

/// A collection: its name, the field that identifies a record, and the
/// fields a record has.
class DVRecordShape {
  const DVRecordShape({
    required this.collection,
    this.key,
    required this.fields,
  });

  final String collection;

  /// The field no two records share, or null for a collection such as a log
  /// where no one field identifies a record.
  final String? key;

  /// Every field, the key included, with how it is stored.
  final Map<String, DVFieldType> fields;
}

/// A comparison a [DVFilter] can make.
enum DVCompare {
  equal('='),
  notEqual('!='),
  less('<'),
  lessOrEqual('<='),
  greater('>'),
  greaterOrEqual('>=');

  const DVCompare(this.sql);

  final String sql;
}

/// Which records an operation applies to: a tree of comparisons, rather than
/// a WHERE string only a SQL engine could run.
///
/// It compares as SQL does: a comparison against a missing or null value
/// never matches, [DVFilter.isNull] is how null is found.
sealed class DVFilter {
  const DVFilter();

  /// [field] compared with [value] by [compare].
  const factory DVFilter.compare(
    String field,
    DVCompare compare,
    Object? value,
  ) = DVFieldFilter;

  /// [field] equal to [value].
  factory DVFilter.equals(String field, Object? value) =>
      DVFieldFilter(field, DVCompare.equal, value);

  /// [field] missing or null.
  const factory DVFilter.isNull(String field) = DVNullFilter;

  /// [field] present and not null.
  factory DVFilter.isNotNull(String field) => DVNullFilter(field, negate: true);

  /// Every one of [filters]. None at all matches everything, and is refused
  /// by an update or a delete.
  const factory DVFilter.all(List<DVFilter> filters) = DVAllFilter;

  /// At least one of [filters].
  const factory DVFilter.any(List<DVFilter> filters) = DVAnyFilter;

  /// Whether [record] is one of the records this filter picks.
  bool matches(Map<String, Object?> record);

  /// True when the filter picks every record.
  bool get isEmpty => false;
}

/// A field compared with a value.
final class DVFieldFilter extends DVFilter {
  const DVFieldFilter(this.field, this.compare, this.value);

  final String field;
  final DVCompare compare;
  final Object? value;

  @override
  bool matches(Map<String, Object?> record) {
    final Object? actual = record[field];
    final Object? expected = value;
    if (actual == null || expected == null) return false;
    final int order = _compareValues(actual, expected);
    return switch (compare) {
      DVCompare.equal => order == 0,
      DVCompare.notEqual => order != 0,
      DVCompare.less => order < 0,
      DVCompare.lessOrEqual => order <= 0,
      DVCompare.greater => order > 0,
      DVCompare.greaterOrEqual => order >= 0,
    };
  }
}

/// A field that is, or is not, null.
final class DVNullFilter extends DVFilter {
  const DVNullFilter(this.field, {this.negate = false});

  final String field;

  /// True for "is not null".
  final bool negate;

  @override
  bool matches(Map<String, Object?> record) =>
      (record[field] == null) != negate;
}

/// Every one of a list of filters.
final class DVAllFilter extends DVFilter {
  const DVAllFilter(this.filters);

  final List<DVFilter> filters;

  @override
  bool matches(Map<String, Object?> record) =>
      filters.every((DVFilter f) => f.matches(record));

  @override
  bool get isEmpty => filters.every((DVFilter f) => f.isEmpty);
}

/// At least one of a list of filters.
final class DVAnyFilter extends DVFilter {
  const DVAnyFilter(this.filters);

  final List<DVFilter> filters;

  @override
  bool matches(Map<String, Object?> record) =>
      filters.any((DVFilter f) => f.matches(record));
}

/// An order to return records in.
class DVSort {
  const DVSort(this.field, {this.descending = false});

  final String field;
  final bool descending;
}

/// The operations every database engine implements.
///
/// Framework code persists through these rather than through SQL strings, so
/// that a project on a document database gets the same Studio, models and
/// stores as one on PostgreSQL. `DV.Database.records` is the one for the
/// configured database.
abstract interface class DVRecordAdapter {
  /// The record operations for [database]: itself when it is a record
  /// engine, as a document database is, and otherwise compiled to SQL for it.
  static DVRecordAdapter over(DVDatabaseAdapter database) =>
      database is DVRecordAdapter
      ? database as DVRecordAdapter
      : DVSqlRecordAdapter(database);

  /// The collection exists with [shape]'s fields.
  Future<void> ensure(DVRecordShape shape);

  /// The records [where] picks, in [orderBy], at most [limit] of them after
  /// skipping [offset], with only [fields] when given.
  Future<List<Map<String, Object?>>> find(
    String collection, {
    DVFilter? where,
    List<DVSort> orderBy = const <DVSort>[],
    int? limit,
    int? offset,
    List<String>? fields,
  });

  /// How many records [where] picks.
  Future<int> count(String collection, {DVFilter? where});

  /// Adds one record.
  Future<void> insert(String collection, Map<String, Object?> record);

  /// Applies [changes] to the records [where] picks, and answers how many.
  ///
  /// An optimistic write names the version it read in [where]; nought
  /// changed is the conflict.
  Future<int> update(
    String collection,
    Map<String, Object?> changes, {
    required DVFilter where,
  });

  /// Removes the records [where] picks, and answers how many.
  Future<int> delete(String collection, {required DVFilter where});
}

/// The record operations compiled to SQL, for SQLite, PostgreSQL, MySQL and
/// the in-memory development database.
///
/// Every name is checked to be an identifier and every value is a parameter,
/// so nothing a record holds can become SQL.
class DVSqlRecordAdapter implements DVRecordAdapter {
  /// Over [database], or `DV.Database` -- with its tenant checks -- when none
  /// is given.
  DVSqlRecordAdapter([DVDatabaseAdapter? database]) : _database = database;

  final DVDatabaseAdapter? _database;

  Future<List<Map<String, Object?>>> _query(String sql, List<Object?> params) =>
      _database == null
      ? const DVDatabase().query(sql, params)
      : _database.query(sql, params);

  Future<int> _execute(String sql, List<Object?> params) => _database == null
      ? const DVDatabase().execute(sql, params)
      : _database.execute(sql, params);

  /// The collections ensured on each database, so a store that ensures its
  /// collection before every operation pays for it once per process.
  static final Expando<Set<String>> _ensured = Expando<Set<String>>();

  @override
  Future<void> ensure(DVRecordShape shape) async {
    final DVDatabaseAdapter database = _database ?? const DVDatabase().adapter;
    final Set<String> done = _ensured[database] ??= <String>{};
    if (done.contains(shape.collection)) return;
    final String table = _collection(shape.collection);
    final String columns = <String>[
      for (final MapEntry<String, DVFieldType> field in shape.fields.entries)
        field.key == shape.key
            // MySQL cannot index TEXT without a prefix length, so a text key
            // is VARCHAR(255), as the framework's other keyed tables are.
            ? '${_name(field.key)} ${field.value == DVFieldType.text ? 'VARCHAR(255)' : field.value.sql} PRIMARY KEY'
            : '${_name(field.key)} ${field.value.sql}',
    ].join(', ');
    // Through the framework-table check: every column typed, and on
    // PostgreSQL and MySQL an integer column an earlier release made 32 bits
    // wide is widened, or refused with its plan when it has rows.
    await dvEnsureFrameworkTable(
      database,
      'CREATE TABLE IF NOT EXISTS $table ($columns)',
    );
    // A table from an earlier release keeps the columns it was made with.
    // Selecting a column the table lacks fails on SQLite, PostgreSQL and
    // MySQL alike, and ADD COLUMN is the one ALTER all three share -- the
    // same repair dartvel db migrate makes for a model.
    for (final MapEntry<String, DVFieldType> field in shape.fields.entries) {
      final String column = _name(field.key);
      try {
        await _query('SELECT $column FROM $table LIMIT 0', const <Object?>[]);
      } on Object {
        await _execute(
          'ALTER TABLE $table ADD COLUMN $column ${field.value.sql}',
          const <Object?>[],
        );
      }
    }
    done.add(shape.collection);
  }

  @override
  Future<List<Map<String, Object?>>> find(
    String collection, {
    DVFilter? where,
    List<DVSort> orderBy = const <DVSort>[],
    int? limit,
    int? offset,
    List<String>? fields,
  }) {
    final List<Object?> params = <Object?>[];
    final StringBuffer sql = StringBuffer('SELECT ')
      ..write(fields == null ? '*' : fields.map(_name).join(', '))
      ..write(' FROM ${_collection(collection)}')
      ..write(_where(where, params));
    if (orderBy.isNotEmpty) {
      sql.write(' ORDER BY ');
      sql.write(
        orderBy
            .map(
              (DVSort s) => '${_name(s.field)}${s.descending ? ' DESC' : ''}',
            )
            .join(', '),
      );
    }
    if (limit != null) sql.write(' LIMIT ${_count(limit)}');
    if (offset != null) sql.write(' OFFSET ${_count(offset)}');
    return _query(sql.toString(), params);
  }

  @override
  Future<int> count(String collection, {DVFilter? where}) async {
    final List<Object?> params = <Object?>[];
    final List<Map<String, Object?>> rows = await _query(
      'SELECT COUNT(*) AS n FROM ${_collection(collection)}${_where(where, params)}',
      params,
    );
    final Object? n = rows.isEmpty ? 0 : rows.first['n'];
    return n is int ? n : int.parse('$n');
  }

  @override
  Future<void> insert(String collection, Map<String, Object?> record) async {
    final List<String> names = record.keys.map(_name).toList();
    await _execute(
      'INSERT INTO ${_collection(collection)} (${names.join(', ')}) '
      'VALUES (${List<String>.filled(names.length, '?').join(', ')})',
      record.values.map(_value).toList(),
    );
  }

  @override
  Future<int> update(
    String collection,
    Map<String, Object?> changes, {
    required DVFilter where,
  }) {
    _refuseEverything(where, 'update');
    final List<Object?> params = changes.values.map(_value).toList();
    final String assignments = changes.keys
        .map((String k) => '${_name(k)} = ?')
        .join(', ');
    return _execute(
      'UPDATE ${_collection(collection)} SET $assignments${_where(where, params)}',
      params,
    );
  }

  @override
  Future<int> delete(String collection, {required DVFilter where}) {
    _refuseEverything(where, 'delete');
    final List<Object?> params = <Object?>[];
    return _execute(
      'DELETE FROM ${_collection(collection)}${_where(where, params)}',
      params,
    );
  }

  /// An update or a delete with a filter that picks everything is almost
  /// always a filter built from an empty list by mistake.
  static void _refuseEverything(DVFilter where, String operation) {
    if (where.isEmpty) {
      throw ArgumentError.value(
        where,
        'where',
        'An empty filter would $operation every record',
      );
    }
  }

  static String _where(DVFilter? where, List<Object?> params) {
    if (where == null || where.isEmpty) return '';
    // A top-level AND needs no parentheses, and the in-memory development
    // database reads a WHERE as conditions joined by AND.
    if (where is DVAllFilter) {
      return ' WHERE ${<String>[for (final DVFilter f in where.filters)
        if (!f.isEmpty) _compile(f, params)].join(' AND ')}';
    }
    return ' WHERE ${_compile(where, params)}';
  }

  static String _compile(DVFilter filter, List<Object?> params) {
    switch (filter) {
      case DVFieldFilter(
        :final String field,
        :final DVCompare compare,
        :final Object? value,
      ):
        params.add(_value(value));
        return '${_name(field)} ${compare.sql} ?';
      case DVNullFilter(:final String field, :final bool negate):
        return '${_name(field)} IS ${negate ? 'NOT ' : ''}NULL';
      case DVAllFilter(:final List<DVFilter> filters):
        return _join(filters, 'AND', params);
      case DVAnyFilter(:final List<DVFilter> filters):
        // An empty "any" picks nothing, which SQL has no bare word for.
        if (filters.isEmpty) return '1 = 0';
        return _join(filters, 'OR', params);
    }
  }

  static String _join(
    List<DVFilter> filters,
    String word,
    List<Object?> params,
  ) {
    final List<String> parts = <String>[
      for (final DVFilter f in filters)
        if (!f.isEmpty) _compile(f, params),
    ];
    return parts.length == 1 ? parts.single : '(${parts.join(' $word ')})';
  }

  static final RegExp _identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

  static String _name(String name) {
    if (!_identifier.hasMatch(name)) {
      throw ArgumentError.value(name, 'name', 'Not a collection or field name');
    }
    return name;
  }

  /// A collection's name, which may be qualified by a schema: a tenant's
  /// tables sit in its own under schema-per-tenant.
  static String _collection(String name) {
    final List<String> parts = name.split('.');
    if (parts.length > 2) {
      throw ArgumentError.value(name, 'name', 'Not a collection name');
    }
    parts.forEach(_name);
    return name;
  }

  static int _count(int n) {
    if (n < 0) throw ArgumentError.value(n, 'n', 'Must not be negative');
    return n;
  }

  static Object? _value(Object? value) =>
      value is bool ? (value ? 1 : 0) : value;
}

int _compareValues(Object a, Object b) {
  if (a is num && b is num) return a.compareTo(b);
  if (a is String && b is String) return a.compareTo(b);
  if (a is bool && b is bool) return (a ? 1 : 0).compareTo(b ? 1 : 0);
  if (a is bool && b is num) return (a ? 1 : 0).compareTo(b);
  if (a is num && b is bool) return a.compareTo(b ? 1 : 0);
  return a.toString().compareTo(b.toString());
}

/// An in-memory database that runs the record operations and no SQL.
///
/// It stands in for a document engine. Configured as `DV.Database`, a
/// surface that still writes a SQL string fails naming the statement, and one
/// written against `DV.Database.records` works -- which is what a project on
/// MongoDB will see. For tests; the development database that runs the
/// framework's SQL is [MemoryDVDatabaseAdapter].
class DVMemoryRecordEngine implements DVDatabaseAdapter, DVRecordAdapter {
  final Map<String, List<Map<String, Object?>>> _collections =
      <String, List<Map<String, Object?>>>{};

  List<Map<String, Object?>> _in(String collection) =>
      _collections.putIfAbsent(collection, () => <Map<String, Object?>>[]);

  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?>? params,
  ]) => Future<List<Map<String, Object?>>>.error(_noSql(sql));

  @override
  Future<int> execute(String sql, [List<Object?>? params]) =>
      Future<int>.error(_noSql(sql));

  static UnsupportedError _noSql(String sql) => UnsupportedError(
    'This database runs records, not SQL, as a document database does. '
    'Persist through DV.Database.records. Refused: $sql',
  );

  @override
  Future<void> ensure(DVRecordShape shape) async => _in(shape.collection);

  @override
  Future<List<Map<String, Object?>>> find(
    String collection, {
    DVFilter? where,
    List<DVSort> orderBy = const <DVSort>[],
    int? limit,
    int? offset,
    List<String>? fields,
  }) async {
    final List<Map<String, Object?>> matches = <Map<String, Object?>>[
      for (final Map<String, Object?> record in _in(collection))
        if (where == null || where.isEmpty || where.matches(record)) record,
    ];
    if (orderBy.isNotEmpty) {
      matches.sort((Map<String, Object?> a, Map<String, Object?> b) {
        for (final DVSort sort in orderBy) {
          final Object? x = a[sort.field];
          final Object? y = b[sort.field];
          // Nulls first ascending, as SQLite and PostgreSQL's NULLS FIRST.
          final int order = x == null
              ? (y == null ? 0 : -1)
              : y == null
              ? 1
              : _compareValues(x, y);
          if (order != 0) return sort.descending ? -order : order;
        }
        return 0;
      });
    }
    final Iterable<Map<String, Object?>> paged = matches
        .skip(offset ?? 0)
        .take(limit ?? matches.length);
    return <Map<String, Object?>>[
      for (final Map<String, Object?> record in paged)
        fields == null
            ? Map<String, Object?>.of(record)
            : <String, Object?>{for (final String f in fields) f: record[f]},
    ];
  }

  @override
  Future<int> count(String collection, {DVFilter? where}) async =>
      (await find(collection, where: where)).length;

  @override
  Future<void> insert(String collection, Map<String, Object?> record) async =>
      _in(collection).add(Map<String, Object?>.of(record));

  @override
  Future<int> update(
    String collection,
    Map<String, Object?> changes, {
    required DVFilter where,
  }) async {
    DVSqlRecordAdapter._refuseEverything(where, 'update');
    int changed = 0;
    for (final Map<String, Object?> record in _in(collection)) {
      if (where.matches(record)) {
        record.addAll(changes);
        changed++;
      }
    }
    return changed;
  }

  @override
  Future<int> delete(String collection, {required DVFilter where}) async {
    DVSqlRecordAdapter._refuseEverything(where, 'delete');
    final List<Map<String, Object?>> records = _in(collection);
    final int before = records.length;
    records.removeWhere(where.matches);
    return before - records.length;
  }
}
