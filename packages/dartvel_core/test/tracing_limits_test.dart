// Spans are bounded: in attributes (DV-TRACE-010).
//
// An unbounded attribute map is how a trace backend's bill becomes the reason
// tracing gets switched off -- one loop that tags a span per item, and every
// request carries ten thousand attributes to a backend that charges by the
// byte.
import 'dart:convert';

import 'package:dartvel_core/src/observability/observability.dart';
import 'package:test/test.dart';

void main() {
  setUp(DVObservability.resetLogging);

  group('attribute limit', () {
    test('past the limit, new attributes are dropped and counted', () {
      final DVMemoryTraceExporter exporter = DVMemoryTraceExporter();
      final DVTracer tracer = DVTracer(exporter: exporter, attributeLimit: 3);
      final DVSpan span = tracer.startSpan('loop');
      for (int i = 0; i < 10; i++) {
        span.setAttribute('item.$i', 'x');
      }
      span.end();

      expect(span.attributes.keys, <String>['item.0', 'item.1', 'item.2']);
      expect(span.droppedAttributes, 7);
    });

    test('an attribute already set can still change at the limit', () {
      final DVTracer tracer = DVTracer(attributeLimit: 2);
      final DVSpan span = tracer.startSpan('request')
        ..setAttribute('http.method', 'GET')
        ..setAttribute('http.path', '/');
      span.setAttribute('http.path', '/orders');
      expect(span.attributes['http.path'], '/orders');
      expect(span.droppedAttributes, 0);
    });

    test('an error is still recorded on a full span', () {
      // The attribute that matters most is the one most likely to arrive
      // last.
      final DVTracer tracer = DVTracer(attributeLimit: 1);
      final DVSpan span = tracer.startSpan('request')
        ..setAttribute('a', '1');
      span.recordError(StateError('boom'));
      expect(span.status, DVSpanStatus.error);
      expect(span.attributes['error'], contains('boom'));
    });

    test('DV-TRACE-010 is logged once, not once per dropped attribute', () {
      final DVTracer tracer = DVTracer(attributeLimit: 1);
      for (int s = 0; s < 5; s++) {
        final DVSpan span = tracer.startSpan('loop');
        for (int i = 0; i < 5; i++) {
          span.setAttribute('k$i', 'v');
        }
      }
      expect(
        DVObservability.recentLogs.where((r) => r.code == 'DV-TRACE-010'),
        hasLength(1),
      );
    });

    test('the default is 128, as OpenTelemetry\'s is', () {
      final DVSpan span = DVTracer().startSpan('x');
      for (int i = 0; i < 200; i++) {
        span.setAttribute('k$i', 'v');
      }
      expect(span.attributes, hasLength(128));
    });

    test('the dropped count reaches the collector', () {
      final DVSpan span = DVTracer(attributeLimit: 1).startSpan('x')
        ..setAttribute('a', '1')
        ..setAttribute('b', '2')
        ..end();
      final Map<String, Object?> sent = (jsonDecode(jsonEncode(
                  dvOtlpTracesJson(<DVSpan>[span], serviceName: 's')))
              as Map<String, Object?>)
          .let((Map<String, Object?> body) =>
              ((((body['resourceSpans']! as List<Object?>).single!
                              as Map<String, Object?>)['scopeSpans']!
                          as List<Object?>)
                      .single! as Map<String, Object?>)['spans']!
                  as List<Object?>)
          .single! as Map<String, Object?>;
      expect(sent['droppedAttributesCount'], 1);
    });
  });
}

extension<T> on T {
  R let<R>(R Function(T value) body) => body(this);
}
