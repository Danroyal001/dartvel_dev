/// The database adapter contract plus the in-memory development adapter.
library dartvel_core.database.adapter;

import 'dart:async';

import '../tenancy/tenants.dart';

abstract class DVDatabaseAdapter {
  Future<List<Map<String, Object?>>> query(String sql, [List<Object?>? params]);
  Future<int> execute(String sql, [List<Object?>? params]);
}

/// The development database: an in-memory table store that runs the subset of
/// SQL Dartvel itself issues.
///
/// It exists so the framework can be run and tested without a database -- a
/// widget test, `dartvel dev` on a project with none configured, the Studio
/// demo. That only works if it answers the statements the framework writes,
/// and for a long time it did not: Studio's page store,
/// `DVDatabaseCacheAdapter` and `DVDatabaseQueueAdapter` all issue CREATE
/// TABLE, scoped DELETE, column-subset SELECT, UPDATE, ORDER BY, LIMIT and
/// COUNT(*), and every one of those threw. Studio's Pages tab rendered the
/// throw where the pages should have been.
///
/// What it runs, against rows held in a map:
///
/// * `CREATE TABLE [IF NOT EXISTS] t (...)` and `DROP TABLE [IF EXISTS] t`
/// * `INSERT INTO t (cols) VALUES (...)`, including an explicit `rowid`
/// * `UPDATE t SET col = ... [WHERE ...]` and `DELETE FROM t [WHERE ...]`
/// * `SELECT [DISTINCT] * | cols | COUNT(*) [AS alias] FROM t`
///   `[WHERE ...] [ORDER BY col [ASC|DESC], ...] [LIMIT n] [OFFSET n]`
/// * a `WHERE` of conditions joined by `AND`, comparing with
///   `= != <> < <= > >=`, `IS NULL` and `IS NOT NULL`
///
/// Anything else -- a join, a subquery, `OR`, SQLite's FTS5 `MATCH`, an
/// `ALTER TABLE` -- throws an [ArgumentError] naming the statement. An
/// in-memory adapter that quietly answers a query it did not understand is
/// worse than one that cannot: the wrong rows look exactly like the right
/// ones. Configure SQLite when the answer needs a real database.
class MemoryDVDatabaseAdapter implements DVDatabaseAdapter {
  final Map<String, _MemoryTable> _tables = <String, _MemoryTable>{};

  static final RegExp _select = RegExp(
    r'^select\s+(distinct\s+)?(.+?)\s+from\s+([A-Za-z_]\w*)\s*(.*)$',
    caseSensitive: false,
  );
  static final RegExp _insert = RegExp(
    r'^insert\s+into\s+([A-Za-z_]\w*)\s*\(([^)]+)\)\s*values\s*\((.*)\)$',
    caseSensitive: false,
  );
  static final RegExp _update = RegExp(
    r'^update\s+([A-Za-z_]\w*)\s+set\s+(.*?)(?:\s+where\s+(.*))?$',
    caseSensitive: false,
  );
  static final RegExp _delete = RegExp(
    r'^delete\s+from\s+([A-Za-z_]\w*)(?:\s+where\s+(.*))?$',
    caseSensitive: false,
  );
  static final RegExp _createTable = RegExp(
    r'^create\s+table\s+(if\s+not\s+exists\s+)?([A-Za-z_]\w*)\s*\((.*)\)$',
    caseSensitive: false,
  );
  static final RegExp _dropTable = RegExp(
    r'^drop\s+table\s+(if\s+exists\s+)?([A-Za-z_]\w*)$',
    caseSensitive: false,
  );
  static final RegExp _whereKeyword =
      RegExp(r'^where\s+', caseSensitive: false);
  static final RegExp _orderKeyword =
      RegExp(r'^order\s+by\s+', caseSensitive: false);
  static final RegExp _limitKeyword =
      RegExp(r'^limit\s+(\S+)', caseSensitive: false);
  static final RegExp _offsetKeyword =
      RegExp(r'^offset\s+(\S+)', caseSensitive: false);
  static final RegExp _afterWhere =
      RegExp(r'\s+(?:order\s+by|limit|offset)\s+', caseSensitive: false);
  static final RegExp _afterOrder =
      RegExp(r'\s+(?:limit|offset)\s+', caseSensitive: false);
  static final RegExp _and = RegExp(r'\s+and\s+', caseSensitive: false);
  static final RegExp _or = RegExp(r'\bor\b', caseSensitive: false);
  static final RegExp _count = RegExp(
    r'^count\s*\(\s*\*\s*\)(?:\s+as\s+([A-Za-z_]\w*))?$',
    caseSensitive: false,
  );
  static final RegExp _aliased = RegExp(
    r'^([A-Za-z_]\w*)\s+as\s+([A-Za-z_]\w*)$',
    caseSensitive: false,
  );
  static final RegExp _column = RegExp(r'^[A-Za-z_]\w*$');
  static final RegExp _assignment = RegExp(r'^([A-Za-z_]\w*)\s*=\s*(.+)$');
  static final RegExp _nullTest = RegExp(
    r'^([A-Za-z_]\w*)\s+is\s+(not\s+)?null$',
    caseSensitive: false,
  );
  static final RegExp _comparison =
      RegExp(r'^([A-Za-z_]\w*)\s*(=|!=|<>|<=|>=|<|>)\s*(.+)$');
  static final RegExp _sortKey = RegExp(
    r'^([A-Za-z_]\w*)(?:\s+(asc|desc))?$',
    caseSensitive: false,
  );

  @override
  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?>? params,
  ]) async {
    final statement = _normalize(sql);
    if (statement.toLowerCase() == 'select 1') {
      return const [
        {'1': 1}
      ];
    }

    final select = _select.firstMatch(statement);
    if (select == null) throw _unsupported(statement);
    final binding = _Binding(statement, params);
    final clauses = _readClauses(select.group(4)!, binding, statement);
    binding.done();

    final rows = <_MemoryRow>[
      for (final row in _tables[select.group(3)!]?.rows ?? const <_MemoryRow>[])
        if (clauses.where.every((condition) => condition.matches(row))) row,
    ];
    _sort(rows, clauses.order);

    var projected = _project(rows, select.group(2)!.trim(), statement);
    if (select.group(1) != null) projected = _distinct(projected);
    final offset = clauses.offset;
    if (offset != null) projected = projected.skip(offset).toList();
    final limit = clauses.limit;
    if (limit != null) projected = projected.take(limit).toList();
    return projected;
  }

  @override
  Future<int> execute(String sql, [List<Object?>? params]) async {
    final statement = _normalize(sql);
    final binding = _Binding(statement, params);

    final create = _createTable.firstMatch(statement);
    if (create != null) {
      final name = create.group(2)!;
      if (create.group(1) == null && _tables.containsKey(name)) {
        throw _unsupported(statement, 'Table $name already exists.');
      }
      _tables.putIfAbsent(name, _MemoryTable.new);
      return 0;
    }

    final drop = _dropTable.firstMatch(statement);
    if (drop != null) {
      final name = drop.group(2)!;
      if (_tables.remove(name) == null && drop.group(1) == null) {
        throw _unsupported(statement, 'Table $name does not exist.');
      }
      return 0;
    }

    final insert = _insert.firstMatch(statement);
    if (insert != null) {
      final columns = _splitTopLevel(insert.group(2)!);
      final expressions = _splitTopLevel(insert.group(3)!);
      if (columns.length != expressions.length) {
        throw _unsupported(
          statement,
          'It names ${columns.length} columns and ${expressions.length} '
          'values.',
        );
      }
      final values = <String, Object?>{};
      int? rowid;
      for (var i = 0; i < columns.length; i++) {
        final value = _readValue(expressions[i], binding, statement);
        if (columns[i].toLowerCase() == 'rowid') {
          if (value is! int) {
            throw _unsupported(statement, 'A rowid must be an integer.');
          }
          rowid = value;
          continue;
        }
        values[columns[i]] = value;
      }
      binding.done();
      _tables
          .putIfAbsent(insert.group(1)!, _MemoryTable.new)
          .add(values, rowid: rowid);
      return 1;
    }

    final update = _update.firstMatch(statement);
    if (update != null) {
      final assignments = <String, Object?>{};
      for (final assignment in _splitTopLevel(update.group(2)!)) {
        final parts = _assignment.firstMatch(assignment);
        if (parts == null) throw _unsupported(statement);
        assignments[parts.group(1)!] =
            _readValue(parts.group(2)!, binding, statement);
      }
      final conditions = _readConditions(update.group(3), binding, statement);
      binding.done();
      var affected = 0;
      final rows = _tables[update.group(1)!]?.rows ?? const <_MemoryRow>[];
      for (final row in rows) {
        if (!conditions.every((condition) => condition.matches(row))) continue;
        row.values.addAll(assignments);
        affected++;
      }
      return affected;
    }

    final delete = _delete.firstMatch(statement);
    if (delete != null) {
      final conditions = _readConditions(delete.group(2), binding, statement);
      binding.done();
      final table = _tables[delete.group(1)!];
      if (table == null) return 0;
      final before = table.rows.length;
      table.rows.removeWhere(
        (row) => conditions.every((condition) => condition.matches(row)),
      );
      return before - table.rows.length;
    }

    throw _unsupported(statement);
  }

  /// The `WHERE`, `ORDER BY`, `LIMIT` and `OFFSET` that follow a `FROM`, read
  /// in the order they are written so their `?` placeholders bind in it too.
  ({List<_Condition> where, List<_SortKey> order, int? limit, int? offset})
      _readClauses(String tail, _Binding binding, String statement) {
    var remaining = tail.trim();

    var where = const <_Condition>[];
    final whereAt = _whereKeyword.firstMatch(remaining);
    if (whereAt != null) {
      remaining = remaining.substring(whereAt.end);
      final stop = _afterWhere.firstMatch(remaining);
      where = _readConditions(
        stop == null ? remaining : remaining.substring(0, stop.start),
        binding,
        statement,
      );
      remaining = stop == null ? '' : remaining.substring(stop.start).trim();
    }

    var order = const <_SortKey>[];
    final orderAt = _orderKeyword.firstMatch(remaining);
    if (orderAt != null) {
      remaining = remaining.substring(orderAt.end);
      final stop = _afterOrder.firstMatch(remaining);
      order = _readOrder(
        stop == null ? remaining : remaining.substring(0, stop.start),
        statement,
      );
      remaining = stop == null ? '' : remaining.substring(stop.start).trim();
    }

    int? limit;
    final limitAt = _limitKeyword.firstMatch(remaining);
    if (limitAt != null) {
      limit = _readCount(limitAt.group(1)!, binding, statement);
      remaining = remaining.substring(limitAt.end).trim();
    }

    int? offset;
    final offsetAt = _offsetKeyword.firstMatch(remaining);
    if (offsetAt != null) {
      offset = _readCount(offsetAt.group(1)!, binding, statement);
      remaining = remaining.substring(offsetAt.end).trim();
    }

    if (remaining.isNotEmpty) throw _unsupported(statement);
    return (where: where, order: order, limit: limit, offset: offset);
  }

  List<_Condition> _readConditions(
    String? text,
    _Binding binding,
    String statement,
  ) {
    if (text == null || text.trim().isEmpty) return const <_Condition>[];
    if (text.contains('(') || _or.hasMatch(text)) {
      throw _unsupported(statement);
    }
    final conditions = <_Condition>[];
    for (final clause in text.split(_and)) {
      final trimmed = clause.trim();
      final nullTest = _nullTest.firstMatch(trimmed);
      if (nullTest != null) {
        conditions.add(_Condition(
          nullTest.group(1)!,
          nullTest.group(2) == null ? 'is null' : 'is not null',
          null,
        ));
        continue;
      }
      final comparison = _comparison.firstMatch(trimmed);
      if (comparison == null) throw _unsupported(statement);
      conditions.add(_Condition(
        comparison.group(1)!,
        comparison.group(2)!,
        _readValue(comparison.group(3)!, binding, statement),
      ));
    }
    return conditions;
  }

  List<_SortKey> _readOrder(String text, String statement) {
    final keys = <_SortKey>[];
    for (final key in _splitTopLevel(text)) {
      final match = _sortKey.firstMatch(key);
      if (match == null) throw _unsupported(statement);
      keys.add(_SortKey(
        match.group(1)!,
        (match.group(2) ?? 'asc').toLowerCase() == 'desc',
      ));
    }
    return keys;
  }

  /// Sorted through the insertion index, so equal keys keep insertion order:
  /// Dart's sort is not stable, and a statement ending `, rowid DESC` is
  /// relying on exactly that tie-break.
  static void _sort(List<_MemoryRow> rows, List<_SortKey> order) {
    if (order.isEmpty) return;
    final indexed = rows.indexed.toList();
    indexed.sort((a, b) {
      for (final key in order) {
        final comparison = _compareValues(a.$2[key.column], b.$2[key.column]);
        if (comparison != 0) return key.descending ? -comparison : comparison;
      }
      return a.$1.compareTo(b.$1);
    });
    rows
      ..clear()
      ..addAll(indexed.map((entry) => entry.$2));
  }

  List<Map<String, Object?>> _project(
    List<_MemoryRow> rows,
    String projection,
    String statement,
  ) {
    if (projection == '*') {
      return <Map<String, Object?>>[
        for (final row in rows) Map<String, Object?>.from(row.values),
      ];
    }

    final items = _splitTopLevel(projection);
    if (items.length == 1) {
      final aggregate = _count.firstMatch(items.single);
      if (aggregate != null) {
        return <Map<String, Object?>>[
          <String, Object?>{aggregate.group(1) ?? 'COUNT(*)': rows.length},
        ];
      }
    }

    final columns = <String, String>{};
    for (final item in items) {
      final aliased = _aliased.firstMatch(item);
      if (aliased != null) {
        columns[aliased.group(2)!] = aliased.group(1)!;
        continue;
      }
      if (!_column.hasMatch(item)) throw _unsupported(statement);
      columns[item] = item;
    }
    return <Map<String, Object?>>[
      for (final row in rows)
        <String, Object?>{
          for (final column in columns.entries) column.key: row[column.value],
        },
    ];
  }

  static List<Map<String, Object?>> _distinct(List<Map<String, Object?>> rows) {
    final seen = <String>{};
    return <Map<String, Object?>>[
      for (final row in rows)
        if (seen.add(
          row.entries.map((entry) => '${entry.key}=${entry.value}').join('|'),
        ))
          row,
    ];
  }

  int _readCount(String expression, _Binding binding, String statement) {
    final value = _readValue(expression, binding, statement);
    if (value is int) return value;
    throw _unsupported(statement, 'A row count must be an integer.');
  }

  Object? _readValue(String expression, _Binding binding, String statement) {
    final token = expression.trim();
    if (token == '?') return binding.next();
    if (token.toLowerCase() == 'null') return null;
    if (token.length >= 2 && token.startsWith("'") && token.endsWith("'")) {
      return token.substring(1, token.length - 1).replaceAll("''", "'");
    }
    final number = num.tryParse(token);
    if (number != null) return number;
    throw _unsupported(
      statement,
      "'$token' is not a value it can read; bind it with ? instead.",
    );
  }

  static String _normalize(String sql) {
    var statement = sql.trim().replaceAll(RegExp(r'\s+'), ' ');
    while (statement.endsWith(';')) {
      statement = statement.substring(0, statement.length - 1).trimRight();
    }
    return statement;
  }

  static ArgumentError _unsupported(String statement, [String? detail]) =>
      ArgumentError(
        'MemoryDVDatabaseAdapter cannot run this statement: $statement. '
        '${detail ?? _subset}',
      );

  static const String _subset =
      'It runs the subset Dartvel issues against it -- CREATE TABLE, INSERT, '
      'UPDATE, DELETE, and SELECT with WHERE, ORDER BY, LIMIT, DISTINCT and '
      'COUNT(*) -- over in-memory tables. Configure SQLite or another adapter '
      'for anything more.';

  static List<String> _splitTopLevel(String text) {
    final parts = <String>[];
    final buffer = StringBuffer();
    var depth = 0;
    var quoted = false;
    for (var i = 0; i < text.length; i++) {
      final character = text[i];
      if (character == "'") quoted = !quoted;
      if (!quoted) {
        if (character == '(') depth++;
        if (character == ')') depth--;
        if (character == ',' && depth == 0) {
          parts.add(buffer.toString().trim());
          buffer.clear();
          continue;
        }
      }
      buffer.write(character);
    }
    final last = buffer.toString().trim();
    if (last.isNotEmpty) parts.add(last);
    return parts;
  }
}

/// A row, and the rowid SQLite gives every one of them: `ORDER BY at DESC,
/// rowid DESC` is how Studio's history stores break a tie, and a map of
/// columns alone cannot answer it.
class _MemoryRow {
  _MemoryRow(this.rowid, this.values);

  final int rowid;
  final Map<String, Object?> values;

  Object? operator [](String column) =>
      column.toLowerCase() == 'rowid' ? rowid : values[column];
}

class _MemoryTable {
  final List<_MemoryRow> rows = <_MemoryRow>[];
  int _nextRowid = 1;

  void add(Map<String, Object?> values, {int? rowid}) {
    final assigned = rowid ?? _nextRowid;
    if (assigned >= _nextRowid) _nextRowid = assigned + 1;
    rows.add(_MemoryRow(assigned, values));
  }
}

/// One `WHERE` comparison, its right-hand side already bound.
class _Condition {
  _Condition(this.column, this.operator, this.value);

  final String column;
  final String operator;
  final Object? value;

  bool matches(_MemoryRow row) {
    final actual = row[column];
    switch (operator) {
      case 'is null':
        return actual == null;
      case 'is not null':
        return actual != null;
    }
    // SQL's null: a comparison against it is unknown and never matches, which
    // is why the cache sweep tests IS NOT NULL before comparing the expiry.
    if (actual == null || value == null) return false;
    final order = _compareValues(actual, value);
    switch (operator) {
      case '=':
        return order == 0;
      case '!=':
      case '<>':
        return order != 0;
      case '<':
        return order < 0;
      case '<=':
        return order <= 0;
      case '>':
        return order > 0;
      case '>=':
        return order >= 0;
    }
    return false;
  }
}

class _SortKey {
  _SortKey(this.column, this.descending);

  final String column;
  final bool descending;
}

/// Parameters consumed in the order the statement writes them, so a `?` in a
/// `SET` binds before a `?` in the `WHERE` that follows it.
class _Binding {
  _Binding(this.statement, List<Object?>? params)
      : _params = params ?? const <Object?>[];

  final String statement;
  final List<Object?> _params;
  int _index = 0;

  Object? next() {
    if (_index == _params.length) {
      throw ArgumentError(
        'MemoryDVDatabaseAdapter: $statement has more ? placeholders than the '
        '${_params.length} parameters given.',
      );
    }
    return _params[_index++];
  }

  void done() {
    if (_index != _params.length) {
      throw ArgumentError(
        'MemoryDVDatabaseAdapter: $statement binds $_index parameters but '
        '${_params.length} were given.',
      );
    }
  }
}

int _compareValues(Object? a, Object? b) {
  if (a == null && b == null) return 0;
  if (a == null) return -1;
  if (b == null) return 1;
  if (a is num && b is num) return a.compareTo(b);
  if (a is String && b is String) return a.compareTo(b);
  if (a is bool && b is bool) return (a ? 1 : 0).compareTo(b ? 1 : 0);
  return a.toString().compareTo(b.toString());
}

/// The database facade behind `DV.Database`.
///
/// Lives in core, not the Flutter layer: it wraps only [DVDatabaseAdapter],
/// and a backend isolate needs it as much as a widget does.
class DVDatabase {
  const DVDatabase();
  static DVDatabaseAdapter? _adapter;
  static DVDatabaseAdapter Function(String tenant)? _openForTenant;
  static final Map<String, DVDatabaseAdapter> _perTenant =
      <String, DVDatabaseAdapter>{};

  void configure(DVDatabaseAdapter adapter) {
    _adapter = adapter;
  }

  /// How to open the database for one tenant, under
  /// [DVTenantIsolation.databasePerTenant].
  ///
  /// Required under that strategy and unused under the others. Without it
  /// every tenant would read the one configured adapter, which is the leak
  /// the strategy exists to prevent -- and every query would still return
  /// rows, so nothing would look wrong.
  ///
  /// Called once per tenant and the result kept. A connection per query is a
  /// connection pool nobody wrote, and on SQLite it is a second write lock
  /// over the same file.
  void configureTenantDatabases(
    DVDatabaseAdapter Function(String tenant) open,
  ) {
    _openForTenant = open;
    _perTenant.clear();
  }

  /// Forgets the configured adapter. Intended for tests.
  void unconfigure() {
    _adapter = null;
    _openForTenant = null;
    _perTenant.clear();
  }

  Future<List<Map<String, Object?>>> query(
    String sql, [
    List<Object?>? params,
  ]) {
    _refuseUnscoped(sql);
    return _configuredAdapter.query(sql, params);
  }

  Future<int> execute(String sql, [List<Object?>? params]) {
    // Writes too, and a write without the column is the worse half: it puts
    // a row in the table belonging to nobody, which every tenant then cannot
    // see.
    _refuseUnscoped(sql);
    return _configuredAdapter.execute(sql, params);
  }

  /// Runs [body] with the tenant check off.
  ///
  /// An operator report, a migration, a support tool. The point is not that
  /// crossing tenants is hard -- it is that it is written down: visible in a
  /// diff, greppable, and a decision somebody made rather than a query that
  /// happened not to have a predicate.
  R acrossTenants<R>(R Function() body) => runZoned(
        body,
        zoneValues: <Object?, Object?>{_zoneAcrossTenants: true},
      );

  static const Symbol _zoneAcrossTenants = #dartvelAcrossTenants;

  static void _refuseUnscoped(String sql) {
    if (Zone.current[_zoneAcrossTenants] == true) return;
    final List<String> tables = dvUnscopedTablesIn(sql);
    if (tables.isEmpty) return;
    throw StateError(
      'This statement names ${tables.join(', ')}, whose rows belong to a '
      'tenant, and does not mention $dvTenantColumnName -- so it reads or '
      'writes across every tenant. Add the predicate, or say so with '
      'DV.Database.acrossTenants(() => ...) if crossing tenants is what this '
      'is for.',
    );
  }

  /// The configured adapter.
  ///
  /// Public because a module that shares the application's database needs
  /// the same connection rather than a second one: two adapters over one
  /// SQLite file is two write locks over one file.
  DVDatabaseAdapter get adapter => _configuredAdapter;

  static DVDatabaseAdapter get _configuredAdapter {
    const DVTenants tenants = DVTenants();
    if (tenants.isolation == DVTenantIsolation.databasePerTenant) {
      final open = _openForTenant;
      if (open == null) {
        throw StateError(
          'Tenant isolation is databasePerTenant and no per-tenant database '
          'is configured, so every tenant would read the one adapter -- '
          'which is the separation this strategy exists to provide, and '
          'every query would still return rows. Call '
          'DV.Database.configureTenantDatabases((tenant) => ...).',
        );
      }
      final String tenant = tenants.currentTenant;
      return _perTenant[tenant] ??= open(tenant);
    }

    final adapter = _adapter;
    if (adapter == null) {
      throw StateError(
        'DV.Database has no configured adapter. Configure SQLite or another '
        'database adapter before use.',
      );
    }
    return adapter;
  }
}
