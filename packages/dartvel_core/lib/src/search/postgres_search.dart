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
    if (extra != null && extra.sql.trim().isNotEmpty) {
      where.write(' AND (${extra.sql})');
      params.addAll(extra.params);
    }

    final counted = await database.query(
      'SELECT COUNT(*) AS total FROM $table WHERE $where',
      params,
    );
    final total = (counted.first['total'] as num?)?.toInt() ?? 0;

    final offset = (page < 1 ? 0 : page - 1) * perPage;
    final rows = await database.query(
      'SELECT * FROM $table WHERE $where '
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
      'CREATE INDEX IF NOT EXISTS $name ON $table USING GIN '
      "(to_tsvector('$configuration', $_document))",
    );
  }
}
