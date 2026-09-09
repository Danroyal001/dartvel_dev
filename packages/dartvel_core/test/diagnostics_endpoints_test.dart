// Spans were exported into an in-process list and logs, once they existed,
// went into an in-process buffer. Both are invisible to anything outside the
// process -- which includes `dartvel logs` and `dartvel traces`, the two
// commands that had to admit they had no source to read.
//
// These endpoints are the source. They are off unless the process was started
// with them on, because a log buffer is the one place in a running service
// where every password reset link, every customer email and every request
// body someone logged all sit together.
import 'dart:async';
import 'dart:convert';

import 'package:dartvel_core/src/http/router.dart';
import 'package:dartvel_core/src/http/wintercg.dart';
import 'package:dartvel_core/src/observability/observability.dart';
import 'package:test/test.dart';

Future<Response> get(Router router, String path) => router(Request(
      method: 'GET',
      url: Uri.parse('http://localhost$path'),
      headers: Headers(),
      bodyStream: const Stream<List<int>>.empty(),
    ));

Future<String> read(Response response) async {
  final List<int> bytes = <int>[];
  await for (final List<int> chunk in response.body!.stream) {
    bytes.addAll(chunk);
  }
  return utf8.decode(bytes);
}

List<Map<String, Object?>> ndjson(String body) => body
    .split('\n')
    .where((String line) => line.trim().isNotEmpty)
    .map((String line) => jsonDecode(line) as Map<String, Object?>)
    .toList();

void main() {
  setUp(() {
    DVObservability.metrics.reset();
    DVObservability.resetLogging();
    DVObservability.resetTracing();
    DVObservability.diagnosticsEndpoints = false;
  });

  tearDown(() {
    DVObservability.diagnosticsEndpoints = false;
    DVObservability.resetLogging();
    DVObservability.resetTracing();
  });

  group('GET /_dartvel/logs', () {
    test('is not there at all unless the process opted in', () async {
      DVObservability.log('a customer email address');

      final Response response = await get(Router(), '/_dartvel/logs');

      expect(response.status, 404);
      expect(await read(response), isNot(contains('customer email')));
    });

    test('serves the recent records as one JSON object per line', () async {
      DVObservability.diagnosticsEndpoints = true;
      DVObservability.log('first');
      DVObservability.log('second', context: <String, Object?>{'orderId': 7});

      final Response response = await get(Router(), '/_dartvel/logs');
      final List<Map<String, Object?>> records = ndjson(await read(response));

      expect(response.status, 200);
      expect(response.headers.get('content-type'),
          contains('application/x-ndjson'));
      expect(records.map((Map<String, Object?> r) => r['message']),
          <String>['first', 'second']);
      expect(records[1]['context'], <String, Object?>{'orderId': 7});
    });

    test('honours a limit, so a client can ask for the tail', () async {
      DVObservability.diagnosticsEndpoints = true;
      for (int i = 0; i < 10; i += 1) {
        DVObservability.log('line $i');
      }

      final List<Map<String, Object?>> records =
          ndjson(await read(await get(Router(), '/_dartvel/logs?limit=2')));

      expect(records.map((Map<String, Object?> r) => r['message']),
          <String>['line 8', 'line 9']);
    });
  });

  group('GET /_dartvel/traces', () {
    test('is not there unless the process opted in', () async {
      expect((await get(Router(), '/_dartvel/traces')).status, 404);
    });

    test('serves finished spans with the shape a trace view needs', () async {
      DVObservability.diagnosticsEndpoints = true;
      final DVSpan parent = DVObservability.tracer.startSpan('GET /checkout');
      final DVSpan child =
          DVObservability.tracer.startSpan('db.query', parent: parent);
      child
        ..setAttribute('db.table', 'orders')
        ..end();
      parent.end();

      final List<Map<String, Object?>> spans =
          ndjson(await read(await get(Router(), '/_dartvel/traces')));

      expect(spans, hasLength(2));
      expect(spans[0]['name'], 'db.query');
      expect(spans[0]['traceId'], parent.traceId);
      expect(spans[0]['parentSpanId'], parent.spanId);
      expect(spans[0]['durationMs'], isA<num>());
      expect(spans[0]['status'], 'ok');
      expect(
        (spans[0]['attributes']! as Map<String, Object?>)['db.table'],
        'orders',
      );
    });

    test('a span still running is not served as if it had finished', () async {
      DVObservability.diagnosticsEndpoints = true;
      DVObservability.tracer.startSpan('still going');

      expect(
        ndjson(await read(await get(Router(), '/_dartvel/traces'))),
        isEmpty,
      );
    });
  });

  group('the recent-span buffer', () {
    test('drops the oldest rather than growing without limit', () {
      DVObservability.resetTracing(spanCapacity: 3);
      for (int i = 0; i < 8; i += 1) {
        DVObservability.tracer.startSpan('span $i').end();
      }

      expect(
        DVObservability.recentSpans.map((DVSpan s) => s.name),
        <String>['span 5', 'span 6', 'span 7'],
      );
    });

    test('an exporter of the application\'s own does not blind the buffer',
        () {
      final DVMemoryTraceExporter mine = DVMemoryTraceExporter();
      DVObservability.useTracing(exporter: mine);

      DVObservability.tracer.startSpan('work').end();

      // Pointing tracing at a collector must not be what takes `dartvel
      // traces` away: it read the in-process buffer, and an assignment that
      // replaced the exporter emptied it for good.
      expect(mine.spans, hasLength(1));
      expect(DVObservability.recentSpans, hasLength(1));
    });
  });

  group('runtime configuration from the environment', () {
    test('diagnostics endpoints stay off when nothing asks for them', () {
      expect(dvDiagnosticsEnabled(const <String, String>{}), isFalse);
      expect(
        dvDiagnosticsEnabled(const <String, String>{'DARTVEL_DIAGNOSTICS': '0'}),
        isFalse,
      );
      expect(
        dvDiagnosticsEnabled(
            const <String, String>{'DARTVEL_DIAGNOSTICS': 'false'}),
        isFalse,
      );
    });

    test('and come on for the spellings a person would actually type', () {
      for (final String value in <String>['1', 'true', 'TRUE', 'yes', 'on']) {
        expect(
          dvDiagnosticsEnabled(
              <String, String>{'DARTVEL_DIAGNOSTICS': value}),
          isTrue,
          reason: value,
        );
      }
    });

    test('the server gets a JSON line per record on its own stdout', () {
      final List<String> written = <String>[];
      dvConfigureRuntimeLogging(const <String, String>{}, write: written.add);

      DVObservability.log('serving on 8080');

      expect(written, hasLength(1));
      expect(
        (jsonDecode(written.single) as Map<String, Object?>)['message'],
        'serving on 8080',
      );
    });

    test('DARTVEL_LOG_LEVEL decides what reaches stdout', () {
      final List<String> written = <String>[];
      dvConfigureRuntimeLogging(
        const <String, String>{'DARTVEL_LOG_LEVEL': 'warn'},
        write: written.add,
      );

      DVObservability.log('routine');
      DVObservability.log('trouble', level: DVLogLevel.error);

      expect(written, hasLength(1));
      expect(
        (jsonDecode(written.single) as Map<String, Object?>)['message'],
        'trouble',
      );
    });

    test('an unreadable level does not take the process down on the way up',
        () {
      final List<String> written = <String>[];
      dvConfigureRuntimeLogging(
        const <String, String>{'DARTVEL_LOG_LEVEL': 'chatty'},
        write: written.add,
      );

      DVObservability.log('routine');

      expect(written, hasLength(1));
    });
  });
}
