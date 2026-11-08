// A database query inside a request is a span under that request.
//
// Before this the request was the only span most requests had, so a slow
// page showed one bar and no reason. The silent failure worth the most test
// effort is the other one: a query span that carries its parameters, or a
// literal inlined into the statement, ships personal data to a hosted trace
// backend that everyone with access to that account can read.
import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/src/observability/observability.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    DVObservability.resetTracing();
    const DVDatabase().configure(MemoryDVDatabaseAdapter());
  });
  tearDown(() {
    const DVDatabase().unconfigure();
    DVObservability.resetTracing();
  });

  List<DVSpan> childrenOf(DVSpan parent) => DVObservability.recentSpans
      .where((DVSpan span) => span.parentSpanId == parent.spanId)
      .toList();

  test('a query inside a span is a client span under it, named for the '
      'operation and table', () async {
    final DVSpan request = DVObservability.tracer.startSpan('GET /notes');
    await dvInSpan(request, () async {
      await const DVDatabase()
          .execute('CREATE TABLE IF NOT EXISTS notes (id INTEGER, title TEXT)');
      await const DVDatabase()
          .query('SELECT * FROM notes WHERE title = ?', <Object?>['x']);
    });
    request.end();

    final List<DVSpan> queries = childrenOf(request);
    expect(queries.map((DVSpan s) => s.name),
        <String>['db CREATE notes', 'db SELECT notes']);
    for (final DVSpan span in queries) {
      expect(span.traceId, request.traceId);
      expect(span.kind, DVSpanKind.client);
    }
    expect(queries.last.attributes['db.operation'], 'SELECT');
    expect(queries.last.attributes['db.statement'],
        'SELECT * FROM notes WHERE title = ?');
  });

  test('parameters are never attributes, and literals in the statement are '
      'reduced to its shape', () async {
    final DVSpan request = DVObservability.tracer.startSpan('POST /notes');
    await dvInSpan(request, () async {
      await const DVDatabase()
          .execute('CREATE TABLE IF NOT EXISTS notes (id INTEGER, title TEXT)');
      await const DVDatabase().execute(
          'INSERT INTO notes (id, title) VALUES (?, ?)',
          <Object?>[1, 'ada@example.com']);
      await const DVDatabase().query(
          "SELECT * FROM notes WHERE title = 'grace@example.com' AND id = 42");
    });
    request.end();

    final String everything = childrenOf(request)
        .expand((DVSpan s) => s.attributes.values)
        .join('\n');
    expect(everything, isNot(contains('ada@example.com')));
    expect(everything, isNot(contains('grace@example.com')));
    expect(everything, isNot(contains('42')));
    expect(childrenOf(request).last.attributes['db.statement'],
        'SELECT * FROM notes WHERE title = ? AND id = ?');
  });

  test('a failing query marks its span as an error without quoting the '
      'statement back', () async {
    final DVSpan request = DVObservability.tracer.startSpan('GET /notes');
    await dvInSpan(request, () async {
      await expectLater(
        const DVDatabase().query(
            "SELECT * FROM notes JOIN people ON 'bob@example.com' = name"),
        throwsA(anything),
      );
    });
    request.end();

    final DVSpan failed = childrenOf(request).single;
    expect(failed.status, DVSpanStatus.error);
    expect(failed.attributes.values.join('\n'),
        isNot(contains('bob@example.com')),
        reason: 'the adapter error names the statement, literals and all');
  });

  test('a query outside any span starts no trace of its own', () async {
    // A background sweep running a query a second would otherwise be a root
    // trace a second, each one a single bar.
    await const DVDatabase().query('SELECT 1');
    expect(DVObservability.recentSpans, isEmpty);
  });
}
