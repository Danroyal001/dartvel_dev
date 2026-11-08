/// A span for each database call made inside a traced request.
library dartvel_core.database.query_tracing;

import '../observability/observability.dart';

final RegExp _stringLiteral = RegExp(r"'(?:[^']|'')*'");
// A number standing alone: not part of an identifier (t1), a qualified name
// or a positional placeholder ($1).
final RegExp _numberLiteral = RegExp(r'(?<![\w.$])\d+(?:\.\d+)?(?!\w)');
final RegExp _whitespace = RegExp(r'\s+');
final RegExp _table = RegExp(
  r'\b(?:from|into|update|table(?:\s+if\s+(?:not\s+)?exists)?)\s+"?([A-Za-z_][\w.]*)',
  caseSensitive: false,
);

/// The longest statement recorded. A generated `IN (?, ?, ...)` of ten
/// thousand placeholders is otherwise ten thousand attributes' worth of
/// bytes on one span.
const int dvMaxStatementLength = 2048;

/// [sql] with every literal replaced by `?`.
///
/// Parameters are never attributes, because a parameter is where the personal
/// data is -- and a literal written into the statement is a parameter that
/// skipped binding, so it is reduced the same way. What is left is the shape a
/// slow-query view groups by.
String dvStatementShape(String sql) {
  final String shape = sql
      .replaceAll(_stringLiteral, '?')
      .replaceAll(_numberLiteral, '?')
      .replaceAll(_whitespace, ' ')
      .trim();
  return shape.length <= dvMaxStatementLength
      ? shape
      : '${shape.substring(0, dvMaxStatementLength)}...';
}

/// Runs [call] inside a client span named for [sql]'s operation and table,
/// when there is an ambient span to hang it from.
///
/// With no ambient span there is no span: a background sweep querying once a
/// second would otherwise be a one-bar root trace a second. An unsampled
/// parent gets none either, since nothing would export it.
Future<T> dvTraceDatabaseCall<T>(String sql, Future<T> Function() call) async {
  final DVSpan? parent = dvCurrentSpan;
  if (parent == null || !parent.sampled) return call();

  final String shape = dvStatementShape(sql);
  final int space = shape.indexOf(' ');
  final String operation =
      (space < 0 ? shape : shape.substring(0, space)).toUpperCase();
  final String? table = _table.firstMatch(shape)?.group(1);

  final DVSpan span = DVObservability.tracer.startSpan(
    table == null ? 'db $operation' : 'db $operation $table',
    parent: parent,
    kind: DVSpanKind.client,
  );
  span
    ..setAttribute('db.operation', operation)
    ..setAttribute('db.statement', shape);
  if (table != null) span.setAttribute('db.table', table);
  try {
    return await call();
  } on Object catch (error) {
    // The type, not the message: an adapter's error quotes the statement it
    // refused, literals and all.
    span
      ..status = DVSpanStatus.error
      ..setAttribute('error', '${error.runtimeType}');
    rethrow;
  } finally {
    span.end();
  }
}
