/// PostgreSQL full-text search.
library dartvel_core.search.postgres_search;

import '../../dartvel.dart';

/// Search over a PostgreSQL table using its own full-text engine.
///
/// The index lives in the database rather than a separate service, which is
/// the point: one datastore to operate, and results that cannot go stale
/// relative to the rows they came from.
class DVPostgresSearchProvider<TModel, TFacets>
    implements DVSearchProvider<TModel, TFacets> {
  final DVDatabaseAdapter database;

  /// The table to search.
  final String table;

  /// Columns concatenated into the searchable document.
  final List<String> columns;

  /// Rebuilds a model from a result row.
  final TModel Function(Map<String, Object?> row) fromRow;

  /// Extra SQL and parameters narrowing the search — tenant scoping, a
  /// published flag, a facet.
  ///
  /// Returning SQL with its parameters separately keeps facet values out of
  /// the statement text.
  final ({String sql, List<Object?> params}) Function(TFacets? facets)? filter;

  /// The text search configuration, which decides stemming and stop words.
  final String configuration;

  DVPostgresSearchProvider({
    required this.database,
    required this.table,
    required this.columns,
    required this.fromRow,
    this.filter,
    this.configuration = 'english',
  }) {
    if (!_isIdentifier(table)) {
      throw ArgumentError.value(table, 'table', 'Not a plain SQL identifier.');
    }
    for (final column in columns) {
      if (!_isIdentifier(column)) {
        throw ArgumentError.value(
          column,
          'columns',
          'Not a plain SQL identifier.',
        );
      }
    }
    if (columns.isEmpty) {
      throw ArgumentError.value(
        columns,
        'columns',
        'Searching no columns can only ever return nothing.',
      );
    }
  }

  /// Table and column names are interpolated because SQL has no placeholder
  /// for an identifier; they are validated instead, so nothing a caller
  /// passes can become arbitrary SQL.
  static bool _isIdentifier(String value) =>
      RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(value);

  String get _document => columns
      .map((String column) => "coalesce($column, '')")
      .join(" || ' ' || ");

  /// The table as this tenant's statement names it.
  ///
  /// Under a schema per tenant that is a qualified name, resolved when the
  /// statement runs rather than when the provider was built: which schema is
  /// asking is a fact about the request, and two requests are in flight at
  /// once. Under the shared database it is the table's own name and the
  /// separation is [_tenantPredicate] below.
  String get _table => dvTenantTable(table);

  /// The tenant predicate for this table, or null when it needs none.
  ///
  /// Null for a table nobody registered as scoped -- a currency list is
  /// deliberately shared and a predicate on a column it has not got fails
  /// every search over it -- and null under the other two isolation
  /// strategies, where the schema or the connection is what separates.
  ///
  /// This is what search was missing. The provider builds its own SQL and
  /// hands it to the adapter, so it went past DV.Database and past the check
  /// that refuses a statement naming a scoped table without the tenant
  /// column. Nothing else added one: the automatic tenant filter was a hook
  /// called [filter] that every application had to write for itself, and one
  /// that did not got a search box returning other tenants' rows with their
  /// titles and descriptions in the results.
  ({String sql, Object? param})? get _tenantPredicate {
    const DVTenants tenants = DVTenants();
    if (tenants.isolation != DVTenantIsolation.sharedDatabase) return null;
    // Case-insensitively, because an unquoted SQL identifier is: a provider
    // built for Orders and a client that registered orders name one table,
    // and missing that fails in the silent direction -- no predicate, rows
    // returned, nothing about the result to look at.
    final String lower = table.toLowerCase();
    if (!dvTenantScopedTables
        .any((String scoped) => scoped.toLowerCase() == lower)) {
      return null;
    }
    return (sql: '$dvTenantColumnName = ?', param: tenants.currentTenant);
  }

  @override
  Future<DVSearchResultPage<TModel>> query(
    String query, {
    TFacets? facets,
    int page = 1,
    int perPage = 20,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      // An empty query matching everything would page the whole table into
      // memory; matching nothing is the honest answer to "search for".
      return DVSearchResultPage<TModel>(
        items: <TModel>[],
        total: 0,
        page: page,
        perPage: perPage,
      );
    }

    final extra = filter?.call(facets);
    final where = StringBuffer(
      "to_tsvector('$configuration', $_document) @@ "
      "websearch_to_tsquery('$configuration', ?)",
    );
    final params = <Object?>[trimmed];
    // Before the application's own filter, so a filter that throws or is
    // written wrong cannot be the reason the tenant predicate is missing.
    final scope = _tenantPredicate;
    if (scope != null) {
      where.write(' AND ${scope.sql}');
      params.add(scope.param);
    }
    if (extra != null && extra.sql.trim().isNotEmpty) {
      where.write(' AND (${extra.sql})');
      params.addAll(extra.params);
    }

    final String from = _table;
    final counted = await database.query(
      'SELECT COUNT(*) AS total FROM $from WHERE $where',
      params,
    );
    final total = (counted.first['total'] as num?)?.toInt() ?? 0;

    final offset = (page < 1 ? 0 : page - 1) * perPage;
    final rows = await database.query(
      'SELECT * FROM $from WHERE $where '
      // ts_rank orders by relevance rather than table order, which is the
      // only reason to use the search engine over a LIKE.
      "ORDER BY ts_rank(to_tsvector('$configuration', $_document), "
      "websearch_to_tsquery('$configuration', ?)) DESC "
      'LIMIT ? OFFSET ?',
      <Object?>[...params, trimmed, perPage, offset],
    );

    return DVSearchResultPage<TModel>(
      items: rows.map(fromRow).toList(growable: false),
      total: total,
      page: page,
      perPage: perPage,
    );
  }

  /// Creates a GIN index over the searchable document.
  ///
  /// Optional but close to mandatory in production: without it every search
  /// is a sequential scan that recomputes the tsvector for every row.
  Future<void> createIndex({String? indexName}) async {
    final name = indexName ?? '${table}_dv_search_idx';
    if (!_isIdentifier(name)) {
      throw ArgumentError.value(name, 'indexName', 'Not a plain identifier.');
    }
    await database.execute(
      // The tenant's own table under a schema per tenant: an index built on
      // the bare name there lands in whichever schema the connection is
      // pointed at, which is somebody else's table or none.
      'CREATE INDEX IF NOT EXISTS $name ON $_table USING GIN '
      "(to_tsvector('$configuration', $_document))",
    );
  }
}
