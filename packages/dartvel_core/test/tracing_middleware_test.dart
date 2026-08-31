// A trace that stops at the process boundary is not a trace.
//
// The spec says middleware must propagate trace IDs and job handlers must run
// with trace context. Spans alone do not do that: something has to read the
// incoming traceparent, put it on the request, and send the outgoing one on
// every call the handler makes.
import 'dart:async';

import 'package:dartvel_core/src/http/wintercg.dart';
import 'package:dartvel_core/src/observability/tracing.dart';
import 'package:dartvel_core/src/observability/tracing_middleware.dart';
import 'package:test/test.dart';

Request get(String path, {Map<String, String> headers = const {}}) {
  final Headers h = Headers();
  headers.forEach(h.set);
  return Request(
    method: 'GET',
    url: Uri.parse('http://localhost$path'),
    headers: h,
    bodyStream: const Stream<List<int>>.empty(),
  );
}

void main() {
  late DVMemoryTraceExporter exporter;
  late DVTracer tracer;

  setUp(() {
    exporter = DVMemoryTraceExporter();
    tracer = DVTracer(exporter: exporter, sampler: DVTraceSampler.always());
  });

  test('a request with no traceparent starts a trace', () async {
    await dvTraced(tracer, get('/orders'), (Request req) async {
      expect(dvCurrentSpan, isNotNull);
      return Response.text('ok');
    });

    expect(exporter.spans, hasLength(1));
    expect(exporter.spans.single.parentSpanId, isNull);
  });

  test('a request with a traceparent joins that trace', () async {
    await dvTraced(
      tracer,
      get('/orders', headers: <String, String>{
        'traceparent':
            '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01',
      }),
      (Request req) async => Response.text('ok'),
    );

    expect(exporter.spans.single.traceId, '4bf92f3577b34da6a3ce929d0e0e4736');
    expect(exporter.spans.single.parentSpanId, '00f067aa0ba902b7');
  });

  test('the response carries the trace id back', () async {
    // So a support ticket can name the trace. Without it the id exists only
    // in the backend and nobody outside can quote one.
    final Response response = await dvTraced(
      tracer,
      get('/orders'),
      (Request req) async => Response.text('ok'),
    );

    expect(response.headers.get('traceparent'), isNotNull);
    expect(
      DVTraceContext.parse(response.headers.get('traceparent'))!.traceId,
      exporter.spans.single.traceId,
    );
  });

  test('the span is reachable from inside the handler', () async {
    // The whole point of ambient context: a query three calls deep must be
    // able to hang a child span off this one without every function in
    // between taking a span parameter.
    late String seen;
    await dvTraced(tracer, get('/orders'), (Request req) async {
      seen = dvCurrentSpan!.traceId;
      return Response.text('ok');
    });

    expect(seen, exporter.spans.single.traceId);
  });

  test('a nested call becomes a child span', () async {
    await dvTraced(tracer, get('/orders'), (Request req) async {
      await tracer.trace('db.query', (DVSpan span) async {}, parent: dvCurrentSpan);
      return Response.text('ok');
    });

    expect(exporter.spans, hasLength(2));
    final DVSpan child =
        exporter.spans.firstWhere((DVSpan s) => s.name == 'db.query');
    final DVSpan root =
        exporter.spans.firstWhere((DVSpan s) => s.name != 'db.query');
    expect(child.traceId, root.traceId);
    expect(child.parentSpanId, root.spanId);
  });

  test('the span records the route and the status', () async {
    await dvTraced(
      tracer,
      get('/orders'),
      (Request req) async => Response.text('ok', status: 201),
    );

    expect(exporter.spans.single.attributes['http.method'], 'GET');
    expect(exporter.spans.single.attributes['http.path'], '/orders');
    expect(exporter.spans.single.attributes['http.status'], '201');
  });

  test('a 5xx marks the span as an error', () async {
    // A handler that returns 500 without throwing is the common shape, and a
    // trace where every span is ok while the endpoint is failing is worse
    // than no trace.
    await dvTraced(
      tracer,
      get('/orders'),
      (Request req) async => Response.text('nope', status: 503),
    );

    expect(exporter.spans.single.status, DVSpanStatus.error);
  });

  test('a 4xx is not an error on the span', () async {
    // A 404 is the client asking for something that is not there. Marking it
    // an error makes an error rate that alerts on ordinary traffic.
    await dvTraced(
      tracer,
      get('/orders'),
      (Request req) async => Response.text('gone', status: 404),
    );

    expect(exporter.spans.single.status, DVSpanStatus.ok);
  });

  test('a throwing handler records the error and rethrows', () async {
    await expectLater(
      dvTraced(
        tracer,
        get('/orders'),
        (Request req) async => throw StateError('boom'),
      ),
      throwsStateError,
    );

    expect(exporter.spans.single.status, DVSpanStatus.error);
    expect(exporter.spans.single.attributes['error'], contains('boom'));
  });

  test('the span ends even when the handler throws', () async {
    // A span left open is a span never exported, so an endpoint that always
    // fails is the one that never appears in the trace view.
    await dvTraced(tracer, get('/x'), (Request req) async => throw 'x')
        .catchError((Object _) => Response.text(''));
    expect(exporter.spans, hasLength(1));
  });

  test('there is no ambient span outside a traced call', () async {
    expect(dvCurrentSpan, isNull);
  });
}
