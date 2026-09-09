// Nothing in the framework recorded a single metric.
//
// The registry was built, /metrics served it, and the only series that ever
// appeared was process uptime -- so a Dartvel server scraped by Prometheus
// reported that it was alive and nothing whatever about what it was doing.
// Request rate, error rate and latency are the three numbers every alert is
// written against, and they are all derivable from the router, which every
// request already passes through.
//
// The same call site is the only place an exception escaping a handler can be
// seen at all: the FFI server layer turns a throw into a 500 inside a bare
// `catch (_)`, so before this the error itself was discarded.
import 'dart:async';

import 'package:dartvel_core/src/http/router.dart';
import 'package:dartvel_core/src/http/wintercg.dart';
import 'package:dartvel_core/src/observability/observability.dart';
import 'package:test/test.dart';

Future<Response> send(Router router, String method, String path) =>
    router(Request(
      method: method,
      url: Uri.parse('http://localhost$path'),
      headers: Headers(),
      bodyStream: const Stream<List<int>>.empty(),
    ));

void main() {
  setUp(() {
    DVObservability.metrics.reset();
    DVObservability.resetLogging();
  });

  tearDown(DVObservability.resetLogging);

  test('a served request is counted by method and status', () async {
    final Router router = Router()
      ..get('/orders', (Request _) async => Response.text('ok'));

    await send(router, 'GET', '/orders');
    await send(router, 'GET', '/orders');

    expect(
      DVObservability.render(),
      contains('dartvel_http_requests_total{method="GET",status="200"} 2'),
    );
  });

  test('request latency is observed, so a p95 exists at all', () async {
    final Router router = Router()
      ..get('/orders', (Request _) async => Response.text('ok'));

    await send(router, 'GET', '/orders');

    expect(
      DVObservability.render(),
      contains('dartvel_http_request_duration_seconds_count{method="GET"} 1'),
    );
  });

  test('the path is never a metric label', () async {
    final Router router = Router()
      ..get('/orders/:id', (Request _) async => Response.text('ok'));

    for (int i = 0; i < 3; i += 1) {
      await send(router, 'GET', '/orders/$i');
    }

    // One series per distinct path is how a metrics backend gets killed by
    // the application it is watching: an id in a label means unbounded
    // cardinality, and the router cannot tell an id from a route segment.
    expect(DVObservability.render(), isNot(contains('/orders/1')));
    expect(
      DVObservability.render(),
      contains('dartvel_http_requests_total{method="GET",status="200"} 3'),
    );
  });

  test('a 404 is counted as a 404, not as a server error', () async {
    await send(Router(), 'GET', '/nothing-here');

    expect(
      DVObservability.render(),
      contains('dartvel_http_requests_total{method="GET",status="404"} 1'),
    );
  });

  test('each request leaves one access record naming route and status',
      () async {
    final Router router = Router()
      ..get('/orders', (Request _) async => Response.text('ok'));

    await send(router, 'GET', '/orders');

    final DVLogRecord record = DVObservability.recentLogs.single;
    expect(record.context['method'], 'GET');
    expect(record.context['path'], '/orders');
    expect(record.context['status'], 200);
    expect(record.context['durationMs'], isA<num>());
  });

  test('the access record names the trace the response reported', () async {
    final Router router = Router()
      ..get(
        '/orders',
        (Request request) => dvTraced(
          DVObservability.tracer,
          request,
          (Request _) async => Response.text('ok'),
        ),
      );

    final Response response = await send(router, 'GET', '/orders');

    final String traceparent = response.headers.get('traceparent')!;
    final DVLogRecord record = DVObservability.recentLogs.single;
    // Correlation is the whole point: a support ticket quotes the header,
    // and that has to be enough to find the log lines for the request.
    expect(record.traceId, isNotNull);
    expect(traceparent, contains(record.traceId!));
  });

  test('an escaping exception is recorded and still rethrown', () async {
    final Router router = Router()
      ..get('/boom', (Request _) async => throw StateError('database gone'));

    await expectLater(
      send(router, 'GET', '/boom'),
      throwsA(isA<StateError>()),
    );

    final DVLogRecord record = DVObservability.recentLogs.last;
    expect(record.level, DVLogLevel.error);
    expect(record.error, contains('database gone'));
    expect(record.stackTrace, isNotNull);
    expect(
      DVObservability.render(),
      contains('dartvel_http_requests_total{method="GET",status="500"} 1'),
    );
  });

  test('the metrics endpoint does not count itself', () async {
    await send(Router(), 'GET', '/metrics');
    await send(Router(), 'GET', '/health');

    // A scrape every fifteen seconds is the loudest client a small service
    // has, and counting it buries the traffic somebody actually cares about
    // and makes every request-rate graph a picture of Prometheus.
    expect(DVObservability.render(), isNot(contains('http_requests_total')));
  });
}
