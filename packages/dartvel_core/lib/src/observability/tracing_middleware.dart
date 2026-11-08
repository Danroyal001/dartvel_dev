/// Trace context across the request boundary.
///
/// A trace that stops at the process boundary is not a trace. Spans alone do
/// not propagate anything: something has to read the incoming `traceparent`,
/// make the span reachable from inside the handler, and send the outgoing one
/// back.
library dartvel.observability.tracing_middleware;

import 'dart:async';

import '../http/wintercg.dart';
import 'observability.dart';

// Tracers that have already reported a malformed traceparent. Once each: a
// misconfigured client sends the same bad header on every request, and a
// warning per request is a log flood about one fact.
final Expando<bool> _malformedReported = Expando<bool>('DV-TRACE-001');

/// Runs [handler] inside a span for the request.
///
/// Joins the caller's trace when the request carries a valid `traceparent`,
/// and starts a new one when it does not.
Future<Response> dvTraced(
  DVTracer tracer,
  Request request,
  Future<Response> Function(Request request) handler,
) async {
  final String? header = request.headers.get('traceparent');
  final DVTraceContext? incoming = DVTraceContext.parse(header);
  if (header != null && incoming == null && _malformedReported[tracer] != true) {
    _malformedReported[tracer] = true;
    DVObservability.log(
      'DV-TRACE-001: an inbound traceparent was malformed; a new trace was '
      'started.',
      level: DVLogLevel.warn,
      code: 'DV-TRACE-001',
      context: <String, Object?>{'path': request.url.path},
    );
  }
  final DVSpan span = tracer.startSpan(
    '${request.method} ${request.url.path}',
    context: incoming,
    kind: DVSpanKind.server,
  );
  span
    ..setAttribute('http.method', request.method)
    ..setAttribute('http.path', request.url.path);

  try {
    final Response response = await dvInSpan(span, () => handler(request));

    span.setAttribute('http.status', '${response.status}');
    // 5xx only. A 404 is the client asking for something that is not there,
    // and counting it as a server error makes an error rate that alerts on
    // ordinary traffic.
    if (response.status >= 500) {
      span.status = DVSpanStatus.error;
      span.setAttribute('error', 'HTTP ${response.status}');
    }

    // Sent back so a support ticket can quote a trace id. Without it the id
    // exists only in the backend and nobody outside can name one.
    response.headers.set('traceparent', span.context.toHeader());
    return response;
  } on Object catch (error, stack) {
    span.recordError(error, stack);
    rethrow;
  } finally {
    // Either way. A span left open is a span never exported, so an endpoint
    // that always fails would be the one that never appears in the trace
    // view.
    span.end();
  }
}
