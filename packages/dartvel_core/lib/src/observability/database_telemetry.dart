/// Database calls as spans and metrics, by the OpenTelemetry database
/// semantic conventions.
library dartvel.observability.database_telemetry;

import 'observability.dart' show DVObservability;
import 'tracing.dart';

/// Runs [body], one statement against a database of kind [system]
/// (`sqlite`, `postgresql`, `mysql`, `other_sql`), as a client span under the
/// current one and as a `db.client.operation.duration` observation.
///
/// Only inside a trace. A query outside any span is a queue poll or a cache
/// sweep, and a root span per poll every second is not a trace anybody
/// wants. And never with the values: [sql] is recorded with its literals
/// replaced by `?`, and bound parameters are not recorded at all -- the
/// statement says what was asked, the values are whose data it was.
Future<T> dvTracedDatabaseCall<T>(
  String system,
  String sql,
  Future<T> Function() body, {
  String? namespace,
}) {
  final bool semantic = DVObservability.semanticMetrics;
  final DVSpan? parent =
      DVObservability.requestTracing ? dvCurrentSpan : null;
  if (parent == null && !semantic) return body();
  return _traced(system, sql, body, parent, semantic, namespace);
}

Future<T> _traced<T>(String system, String sql, Future<T> Function() body,
    DVSpan? parent, bool semantic, String? namespace) async {
  final (String operation, String? table) = _summary(sql);
  final DVSpan? span = parent == null
      ? null
      : DVObservability.tracer.startSpan(
          table == null ? operation : '$operation $table',
          parent: parent,
          kind: DVSpanKind.client,
          attributes: <String, Object>{
            'db.system.name': system,
            'db.operation.name': operation,
            if (table != null) 'db.collection.name': table,
            if (namespace != null) 'db.namespace': namespace,
            'db.query.text': dvSanitizeSqlForTelemetry(sql),
          },
        );
  final Stopwatch clock = Stopwatch()..start();
  String? errorType;
  try {
    return await (span == null ? body() : dvInSpan(span, body));
  } on Object catch (error, stack) {
    errorType = '${error.runtimeType}';
    span?.recordError(error, stack);
    rethrow;
  } finally {
    clock.stop();
    span?.end();
    if (semantic) {
      DVObservability.metrics.setUnit('db.client.operation.duration', 's');
      DVObservability.metrics
          .histogram(
            'db.client.operation.duration',
            <String, String>{
              'db.system.name': system,
              'db.operation.name': operation,
              if (table != null) 'db.collection.name': table,
              if (errorType != null) 'error.type': errorType,
            },
            'Duration of database client operations.',
          )
          .observe(clock.elapsedMicroseconds / 1000000);
    }
  }
}

final RegExp _firstWord = RegExp(r'^\s*([A-Za-z]+)');
final RegExp _target = RegExp(
    r'\b(?:FROM|INTO|UPDATE|TABLE(?:\s+IF\s+(?:NOT\s+)?EXISTS)?|JOIN)\s+["`\[]?([A-Za-z_][A-Za-z0-9_.]*)',
    caseSensitive: false);

(String, String?) _summary(String sql) {
  final String operation =
      (_firstWord.firstMatch(sql)?.group(1) ?? 'QUERY').toUpperCase();
  return (operation, _target.firstMatch(sql)?.group(1));
}

final RegExp _literals = RegExp(
  // A quoted string (with '' escapes), a hex or blob literal, or a number
  // that is not part of an identifier or a $1 placeholder.
  r"""[xX]'[0-9A-Fa-f]*'|'(?:[^']|'')*'|(?<![A-Za-z0-9_$])-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?(?![A-Za-z0-9_])""",
);

/// [sql] with every literal value replaced by `?`.
///
/// A statement Dartvel writes binds its values, so this usually changes
/// nothing; the statement somebody wrote by hand with an email address in it
/// is the one it is for.
String dvSanitizeSqlForTelemetry(String sql) =>
    sql.replaceAll(_literals, '?');
