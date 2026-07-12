import 'package:sqlparser/sqlparser.dart';

/// Provides static analysis support for the `DBSTAT` sqlite3 table.
///
/// The DBSTAT virtual table is a read-only eponymous virtual table that returns
/// information about the amount of disk space used to store the content of an
/// SQLite database.
class DbStatExtension implements Extension {
  const DbStatExtension();

  @override
  void register(SqlEngine engine) {
    engine.registerTable(_dbstat);
  }
}

/// The DBSTAT virtual table is a read-only eponymous virtual table that returns
/// information about the amount of disk space used to store the content of an
/// SQLite database.
Table get _dbstat {
  /// Name of table or index
  final name = TableColumn('name', const ResolvedType(type: BasicType.text));

  /// Path to page from root
  final path = TableColumn('path', const ResolvedType(type: BasicType.text));

  /// Page number, or page count
  final pageno = TableColumn('pageno', const ResolvedType(type: BasicType.int));

  /// 'internal', 'leaf', 'overflow', or NULL
  final pagetype =
      TableColumn('pagetype', const ResolvedType(type: BasicType.text));

  /// Cells on page (0 for overflow pages)
  final ncell = TableColumn('ncell', const ResolvedType(type: BasicType.int));

  /// Bytes of payload on this page or btree
  final payload =
      TableColumn('payload', const ResolvedType(type: BasicType.int));

  /// Bytes of unused space on this page or btree
  final unused = TableColumn('unused', const ResolvedType(type: BasicType.int));

  /// Bytes of unused space on this page or btree
  final mxPayload =
      TableColumn('mx_payload', const ResolvedType(type: BasicType.int));

  /// Byte offset of the page in the database file
  final pgoffset =
      TableColumn('pgoffset', const ResolvedType(type: BasicType.int));

  /// Size of the page, in bytes
  final pgsize = TableColumn('pgsize', const ResolvedType(type: BasicType.int));

  /// Database schema being analyzed
  final schema = TableColumn('schema', const ResolvedType(type: BasicType.text),
      isHidden: true);

  /// True to enable aggregate mode
  final aggregate = TableColumn(
      'aggregate', const ResolvedType(type: BasicType.int),
      isHidden: true);

  return Table(
    name: 'dbstat',
    isVirtual: true,
    resolvedColumns: [
      name,
      path,
      pageno,
      pagetype,
      ncell,
      payload,
      unused,
      mxPayload,
      pgoffset,
      pgsize,
      schema,
      aggregate,
    ],
  );
}
