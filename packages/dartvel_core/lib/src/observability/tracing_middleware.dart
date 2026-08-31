/// Trace context across the request boundary.
///
/// A trace that stops at the process boundary is not a trace. Spans alone do
/// not propagate anything: something has to read the incoming `traceparent`,
/// make the span reachable from inside the handler, and send the outgoing one
/// back.
library dartvel.observability.tracing_middleware;

import 'dart:async';

import '../http/wintercg.dart';
import 'tracing.dart';

/// The zone key the current span hangs on.
///
/// A zone rather than a parameter threaded through every function: a query
/// three calls deep has to be able to hang a child span off the request's
/// without each function in between taking a span it does not otherwise use.
/// That threading is exactly the boilerplate that stops people instrumenting
/// anything.
const Object _dvSpanKey = #dartvelSpan;

/// The span the current call is inside, if any.
DVSpan? get dvCurrentSpan => Zone.current[_dvSpanKey] as DVSpan?;

/// Runs [handler] inside a span for the request.
///
/// Joins the caller's trace when the request carries a valid `traceparent`,
/// and starts a new one when it does not.
Future<Response> dvTraced(
  DVTracer tracer,
  Request request,
  Future<Response> Function(Request request) handler,
) async {
  final DVSpan span = tracer.startSpan(
    '${request.method} ${request.url.path}',
    context: DVTraceContext.parse(request.headers.get('traceparent')),
  );
  span
    ..setAttribute('http.method', request.method)
    ..setAttribute('http.path', request.url.path);

  try {
    final Response response = await runZoned(
      () => handler(request),
      zoneValues: <Object, Object?>{_dvSpanKey: span},
    );

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
