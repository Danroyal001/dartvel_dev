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

/// Runs [handler] inside a span for the request.
///
/// Joins the caller's trace when the request carries a valid `traceparent`,
/// and starts a new one when it does not.
///
/// When the request is already inside a server span -- every request is,
/// once tracing is on, because [Router.measure] opens one -- this runs the
/// handler as it is. A second server span for the same request would draw a
/// service calling itself.
Future<Response> dvTraced(
  DVTracer tracer,
  Request request,
  Future<Response> Function(Request request) handler,
) async {
  final DVSpan? current = dvCurrentSpan;
  if (current != null && current.kind == DVSpanKind.server && !current.isEnded) {
    return handler(request);
  }
  final DVSpan span = dvStartServerSpan(tracer, request);
  try {
    final Response response = await dvInSpan(span, () => handler(request));
    dvFinishServerSpan(span, response);
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

/// The server span for [request], by the HTTP semantic conventions.
///
/// Named by the method alone until the route is known: the path is where ids
/// are, and one span name per order id is how a tracing backend's index is
/// blown up by the application it watches. [dvRecordHttpRoute] renames it.
DVSpan dvStartServerSpan(DVTracer tracer, Request request) {
  final String method = request.method;
  return tracer.startSpan(
    method,
    kind: DVSpanKind.server,
    context: DVTraceContext.parse(request.headers.get('traceparent')),
    attributes: <String, Object>{
      'http.request.method': method,
      'url.path': request.url.path,
      'url.scheme': request.url.scheme.isEmpty ? 'http' : request.url.scheme,
      if (request.url.host.isNotEmpty) 'server.address': request.url.host,
      if (request.url.hasPort) 'server.port': request.url.port,
      if (request.headers.get('user-agent') case final String agent)
        'user_agent.original': agent,
    },
  );
}

/// Records [response] on a server span and sends its trace context back.
void dvFinishServerSpan(DVSpan span, Response response) {
  span.setAttribute('http.response.status_code', response.status);
  // 5xx only. A 404 is the client asking for something that is not there,
  // and counting it as a server error makes an error rate that alerts on
  // ordinary traffic.
  if (response.status >= 500) {
    span.status = DVSpanStatus.error;
    span.setAttribute('error.type', '${response.status}');
  }
  // Sent back so a support ticket can quote a trace id. Without it the id
  // exists only in the backend and nobody outside can name one.
  if (response.headers.get('traceparent') == null) {
    response.headers.set('traceparent', span.context.toHeader());
  }
}

/// Names the current request's server span after [route], the template the
/// request matched (`/orders/:id`), as the semantic conventions name a span.
///
/// The router calls this when it matches; the page server and Studio call it
/// for the routes they answer. Outside a request it does nothing.
void dvRecordHttpRoute(String route) {
  final DVRequestTelemetry? scope = DVRequestTelemetry.current;
  scope?.route = route;
  // The request's own server span, even from inside a child span -- the
  // page server matches its route inside the render span.
  final DVSpan? current = dvCurrentSpan;
  final DVSpan? span = scope?.span ??
      (current != null && current.kind == DVSpanKind.server ? current : null);
  if (span == null) return;
  span
    ..updateName('${span.attributes['http.request.method'] ?? ''} $route'.trim())
    ..setAttribute('http.route', route);
}

/// What the request being served has learned about itself on the way:
/// the route template it matched. Read by the request metrics once the
/// response is known.
class DVRequestTelemetry {
  DVRequestTelemetry([this.span]);

  /// The request's server span, when it has one.
  final DVSpan? span;


  static const Object _key = #dartvelRequestTelemetry;

  /// The request this call is serving, or null outside one.
  static DVRequestTelemetry? get current =>
      Zone.current[_key] as DVRequestTelemetry?;

  /// Runs [body] as the request this scope describes.
  R run<R>(R Function() body) =>
      runZoned(body, zoneValues: <Object, Object?>{_key: this});

  String? route;
}
