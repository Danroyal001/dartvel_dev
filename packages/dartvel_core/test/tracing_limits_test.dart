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
  durationLimits();

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

// Spans are bounded in time, too (DV-TRACE-009): a span left open past its
// declared maximum is closed as incomplete rather than held for ever, which
// would be a memory leak that also silently loses its parent's children.
void durationLimits() {
  group('maximum span duration', () {
    setUp(DVObservability.resetLogging);

    test('a span open past the maximum is closed as incomplete and exported',
        () async {
      final DVMemoryTraceExporter exporter = DVMemoryTraceExporter();
      final DVTracer tracer = DVTracer(
          exporter: exporter,
          maxSpanDuration: const Duration(milliseconds: 50));
      final DVSpan leaked = tracer.startSpan('leaked');
      final DVSpan finished = tracer.startSpan('finished')..end();

      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(exporter.spans, containsAll(<DVSpan>[leaked, finished]));
      expect(leaked.duration, isNotNull, reason: 'it was ended');
      expect(leaked.status, DVSpanStatus.error);
      expect(leaked.attributes['dartvel.span.incomplete'], 'true');
      expect(finished.attributes.containsKey('dartvel.span.incomplete'),
          isFalse);
      expect(tracer.openSpans, 0);
    });

    test('ending it later does not export it twice', () async {
      final DVMemoryTraceExporter exporter = DVMemoryTraceExporter();
      final DVTracer tracer = DVTracer(
          exporter: exporter,
          maxSpanDuration: const Duration(milliseconds: 20));
      final DVSpan span = tracer.startSpan('slow');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      span.end();
      expect(exporter.spans.where((DVSpan s) => s == span), hasLength(1));
    });

    test('DV-TRACE-009 is logged once for a burst', () async {
      final DVTracer tracer =
          DVTracer(maxSpanDuration: const Duration(milliseconds: 20));
      for (int i = 0; i < 5; i++) {
        tracer.startSpan('leaked $i');
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(
        DVObservability.recentLogs.where((r) => r.code == 'DV-TRACE-009'),
        hasLength(1),
      );
    });

    test('with no maximum declared nothing is tracked', () {
      final DVTracer tracer = DVTracer();
      tracer.startSpan('open');
      expect(tracer.openSpans, 0);
    });

    test('dartvel.tracing.maxSpanDuration is read and reaches the tracer',
        () async {
      expect(
        DVTracingConfig.parse(<String, Object?>{'maxSpanDuration': '5m'})
            .maxSpanDuration,
        const Duration(minutes: 5),
      );
      expect(
        DVTracingConfig.parse(<String, Object?>{'maxSpanDuration': '250ms'})
            .maxSpanDuration,
        const Duration(milliseconds: 250),
      );
      expect(
        () => DVTracingConfig.parse(<String, Object?>{'maxSpanDuration': 'soon'}),
        throwsA(isA<ArgumentError>().having(
            (ArgumentError e) => e.name, 'name', 'tracing.maxSpanDuration')),
      );
      final DVTracingConfig declared = DVTracingConfig.parse(
          <String, Object?>{'maxSpanDuration': '30s'});
      expect(DVTracingConfig.parse(declared.toDeclaration()).maxSpanDuration,
          const Duration(seconds: 30));

      dvConfigureRuntimeTracing(const <String, String>{}, declared: declared);
      addTearDown(DVObservability.resetTracing);
      expect(DVObservability.tracer.maxSpanDuration,
          const Duration(seconds: 30));
    });
  });
}
