// Traces: spans, W3C context propagation, and sampling.
//
// Dartvel listed OpenTelemetry as an inspiration and traces as built in, and
// had neither. Middleware is specified to propagate trace IDs and job handlers
// to run with trace context; there was nothing to propagate.
//
// The parts under test are the ones that fail quietly. A traceparent parser
// that accepts a malformed header joins a trace that does not exist and the
// spans are orphaned. A sampler that decides per process samples 10% of each
// service independently, so a request is almost never sampled end to end --
// which looks like "tracing is on and finds nothing".
import 'package:dartvel_core/src/observability/tracing.dart';
import 'package:test/test.dart';

void main() {
  group('trace context on the wire', () {
    const String valid =
        '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01';

    test('a valid traceparent round-trips', () {
      final DVTraceContext? parsed = DVTraceContext.parse(valid);
      expect(parsed, isNotNull);
      expect(parsed!.traceId, '4bf92f3577b34da6a3ce929d0e0e4736');
      expect(parsed.parentSpanId, '00f067aa0ba902b7');
      expect(parsed.sampled, isTrue);
      expect(parsed.toHeader(), valid);
    });

    test('the sampled flag is read from the low bit', () {
      expect(
        DVTraceContext.parse(
          '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00',
        )!.sampled,
        isFalse,
      );
    });

    test('an all-zero trace id is refused', () {
      // The specification calls it invalid, and accepting it means every
      // service that sends one shares a single trace.
      expect(
        DVTraceContext.parse(
          '00-00000000000000000000000000000000-00f067aa0ba902b7-01',
        ),
        isNull,
      );
    });

    test('an all-zero span id is refused', () {
      expect(
        DVTraceContext.parse(
          '00-4bf92f3577b34da6a3ce929d0e0e4736-0000000000000000-01',
        ),
        isNull,
      );
    });

    test('a malformed header is null, not an exception', () {
      // It arrives from outside. A 500 on a bad header turns someone else's
      // misconfiguration into an outage here.
      for (final String bad in <String>[
        '',
        'nonsense',
        '00-abc-def-01',
        '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7',
        '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-0z',
        '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01-extra',
      ]) {
        expect(DVTraceContext.parse(bad), isNull, reason: 'for "$bad"');
      }
    });

    test('a future version is refused rather than guessed at', () {
      // ff is reserved as invalid; an unknown version may have a different
      // layout, and reading it as this one produces a plausible wrong id.
      expect(DVTraceContext.parse(
          'ff-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01'), isNull);
    });

    test('case is normalised to lower', () {
      // Hex is case-insensitive on the wire and a trace id compared as a
      // string is not, so an upper-case id from another service reads as a
      // different trace.
      expect(
        DVTraceContext.parse(
          '00-4BF92F3577B34DA6A3CE929D0E0E4736-00F067AA0BA902B7-01',
        )!.traceId,
        '4bf92f3577b34da6a3ce929d0e0e4736',
      );
    });
  });

  group('spans', () {
    late DVMemoryTraceExporter exporter;
    late DVTracer tracer;

    setUp(() {
      exporter = DVMemoryTraceExporter();
      tracer = DVTracer(exporter: exporter, sampler: DVTraceSampler.always());
    });

    test('a root span gets a trace and a span id', () {
      final DVSpan span = tracer.startSpan('checkout');
      span.end();

      expect(exporter.spans, hasLength(1));
      expect(exporter.spans.single.traceId, hasLength(32));
      expect(exporter.spans.single.spanId, hasLength(16));
      expect(exporter.spans.single.parentSpanId, isNull);
    });

    test('a child stays in the same trace and names its parent', () {
      final DVSpan parent = tracer.startSpan('request');
      final DVSpan child = tracer.startSpan('query', parent: parent);
      child.end();
      parent.end();

      expect(child.traceId, parent.traceId);
      expect(child.parentSpanId, parent.spanId);
      expect(child.spanId, isNot(parent.spanId));
    });

    test('a span continued from a header joins that trace', () {
      final DVTraceContext incoming = DVTraceContext.parse(
        '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01',
      )!;
      final DVSpan span = tracer.startSpan('handler', context: incoming);
      span.end();

      expect(span.traceId, '4bf92f3577b34da6a3ce929d0e0e4736');
      expect(span.parentSpanId, '00f067aa0ba902b7');
    });

    test('it records a duration', () {
      final DVSpan span = tracer.startSpan('slow');
      span.end();
      expect(span.duration, isNotNull);
      expect(span.duration!.inMicroseconds, greaterThanOrEqualTo(0));
    });

    test('ending twice does not export twice', () {
      // A span ended in both a finally and an error handler is ordinary, and
      // a duplicate export doubles every count computed from spans.
      final DVSpan span = tracer.startSpan('once');
      span.end();
      span.end();
      expect(exporter.spans, hasLength(1));
    });

    test('an error is recorded on the span, and it still ends', () {
      final DVSpan span = tracer.startSpan('failing');
      span.recordError(StateError('boom'));
      span.end();

      expect(exporter.spans.single.status, DVSpanStatus.error);
      expect(exporter.spans.single.attributes['error'], contains('boom'));
    });

    test('attributes are carried', () {
      final DVSpan span = tracer.startSpan('request')
        ..setAttribute('http.route', '/orders')
        ..setAttribute('tenant', 'acme');
      span.end();

      expect(exporter.spans.single.attributes['http.route'], '/orders');
      expect(exporter.spans.single.attributes['tenant'], 'acme');
    });

    test('a span that is never ended is never exported', () {
      tracer.startSpan('abandoned');
      expect(exporter.spans, isEmpty);
    });

    test('the header a child should send names the child, not the parent', () {
      // Sending the parent's span id makes every downstream span a sibling of
      // this one instead of its child, and the trace renders flat.
      final DVSpan span = tracer.startSpan('request');
      final DVTraceContext outgoing = span.context;

      expect(outgoing.traceId, span.traceId);
      expect(outgoing.parentSpanId, span.spanId);
    });
  });

  group('sampling', () {
    test('always and never do what they say', () {
      final DVMemoryTraceExporter on = DVMemoryTraceExporter();
      DVTracer(exporter: on, sampler: DVTraceSampler.always())
          .startSpan('a')
          .end();
      expect(on.spans, hasLength(1));

      final DVMemoryTraceExporter off = DVMemoryTraceExporter();
      DVTracer(exporter: off, sampler: DVTraceSampler.never())
          .startSpan('a')
          .end();
      expect(off.spans, isEmpty);
    });

    test('the decision is a function of the trace id alone', () {
      // The property that makes a distributed trace whole. If each service
      // rolls its own dice, a request is sampled by all of them with
      // probability p^n -- so at 10% across four services it is one in ten
      // thousand, and tracing appears to be on and finding nothing.
      final DVTraceSampler sampler = DVTraceSampler.ratio(0.5);
      const String id = '4bf92f3577b34da6a3ce929d0e0e4736';

      final bool first = sampler.shouldSample(id);
      for (int i = 0; i < 50; i += 1) {
        expect(sampler.shouldSample(id), first);
      }
    });

    test('a ratio samples roughly that share', () {
      final DVTraceSampler sampler = DVTraceSampler.ratio(0.25);
      int sampled = 0;
      for (int i = 0; i < 2000; i += 1) {
        if (sampler.shouldSample(DVTraceContext.newTraceId())) sampled += 1;
      }
      expect(sampled / 2000, closeTo(0.25, 0.06));
    });

    test('an upstream sampling decision is honoured', () {
      // Respecting it is what keeps a trace whole: a service that re-decides
      // drops the middle of a trace someone else chose to keep.
      final DVMemoryTraceExporter exporter = DVMemoryTraceExporter();
      final DVTracer tracer =
          DVTracer(exporter: exporter, sampler: DVTraceSampler.never());

      tracer
          .startSpan(
            'handler',
            context: DVTraceContext.parse(
              '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01',
            ),
          )
          .end();

      expect(exporter.spans, hasLength(1),
          reason: 'the caller sampled this trace');
    });

    test('an upstream decision not to sample is honoured too', () {
      final DVMemoryTraceExporter exporter = DVMemoryTraceExporter();
      final DVTracer tracer =
          DVTracer(exporter: exporter, sampler: DVTraceSampler.always());

      tracer
          .startSpan(
            'handler',
            context: DVTraceContext.parse(
              '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00',
            ),
          )
          .end();

      expect(exporter.spans, isEmpty);
    });

    test('a ratio outside 0..1 is refused rather than clamped', () {
      expect(() => DVTraceSampler.ratio(1.5), throwsArgumentError);
      expect(() => DVTraceSampler.ratio(-0.1), throwsArgumentError);
    });
  });

  group('ids', () {
    test('a new trace id is 32 hex characters and not all zero', () {
      for (int i = 0; i < 20; i += 1) {
        final String id = DVTraceContext.newTraceId();
        expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
        expect(id, isNot('0' * 32));
      }
    });

    test('ids do not repeat', () {
      final Set<String> seen = <String>{};
      for (int i = 0; i < 500; i += 1) {
        expect(seen.add(DVTraceContext.newTraceId()), isTrue);
      }
    });
  });
}
