// Jobs are linked, not nested (DV-TRACE-005).
//
// A job enqueued by a request and run moments later belongs in that
// request's trace; one run four hours later is part of the same story and
// not of the same waterfall -- nesting it would make a root span four hours
// long. So the publish is a span under the request, the dispatching span's
// context travels in the envelope, and the run either continues that trace or
// starts its own with a link back.
import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/src/observability/observability.dart';
import 'package:test/test.dart';

class SendReceipt {
  const SendReceipt(this.orderId);
  final String orderId;
}

void main() {
  late List<DVSpan> handlerSpans;

  setUp(() {
    DVObservability.resetTracing();
    DVObservability.resetLogging();
    handlerSpans = <DVSpan>[];
    const DVQueues().useAdapter(DVInMemoryQueueAdapter());
    const DVQueues().register<SendReceipt>((SendReceipt job) {
      handlerSpans.add(dvCurrentSpan!);
    });
  });
  tearDown(() {
    DVQueues.traceWindow = const Duration(minutes: 1);
    DVObservability.resetTracing();
    const DVQueues().useAdapter(DVInMemoryQueueAdapter());
  });

  DVSpan spanNamed(String name) =>
      DVObservability.recentSpans.singleWhere((DVSpan s) => s.name == name);

  test('dispatching inside a request is a producer span under it, and its '
      'context travels in the envelope', () async {
    final DVSpan request = DVObservability.tracer.startSpan('POST /orders');
    final DVJobEnvelope<SendReceipt> job = await dvInSpan(request,
        () => const DVQueues().dispatch(const SendReceipt('o-1')));
    request.end();

    final DVSpan publish = spanNamed('queue publish default');
    expect(publish.parentSpanId, request.spanId);
    expect(publish.kind, DVSpanKind.producer);
    expect(publish.attributes['job.type'], 'SendReceipt');
    expect(DVTraceContext.parse(job.traceparent)!.parentSpanId, publish.spanId);
  });

  test('a job run within the window continues the trace that dispatched it',
      () async {
    final DVSpan request = DVObservability.tracer.startSpan('POST /orders');
    await dvInSpan(request,
        () => const DVQueues().dispatch(const SendReceipt('o-1')));
    request.end();

    expect(await const DVQueues().work(), 1);

    final DVSpan consume = spanNamed('queue consume default');
    expect(consume.kind, DVSpanKind.consumer);
    expect(consume.traceId, request.traceId);
    expect(consume.parentSpanId, spanNamed('queue publish default').spanId);
    expect(consume.links, isEmpty);
    expect(handlerSpans.single, same(consume),
        reason: 'the handler runs inside it, so its queries hang under it');
  });

  test('a job run outside the window starts its own trace with a link back, '
      'and DV-TRACE-005 says so once', () async {
    DVQueues.traceWindow = Duration.zero;
    final DVSpan request = DVObservability.tracer.startSpan('POST /orders');
    await dvInSpan(request, () async {
      await const DVQueues().dispatch(const SendReceipt('o-1'));
      await const DVQueues().dispatch(const SendReceipt('o-2'));
    });
    request.end();
    await Future<void>.delayed(const Duration(milliseconds: 5));

    expect(await const DVQueues().work(maxJobs: 2), 2);

    final List<DVSpan> consumes = DVObservability.recentSpans
        .where((DVSpan s) => s.name == 'queue consume default')
        .toList();
    expect(consumes, hasLength(2));
    for (final DVSpan consume in consumes) {
      expect(consume.traceId, isNot(request.traceId));
      expect(consume.parentSpanId, isNull);
      expect(consume.links.single.traceId, request.traceId);
    }
    expect(
      DVObservability.recentLogs.where((r) => r.code == 'DV-TRACE-005'),
      hasLength(1),
    );
  });

  test('the link reaches the collector', () async {
    DVQueues.traceWindow = Duration.zero;
    final DVSpan request = DVObservability.tracer.startSpan('POST /orders');
    await dvInSpan(request,
        () => const DVQueues().dispatch(const SendReceipt('o-1')));
    request.end();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await const DVQueues().work();

    final Map<String, Object?> body = dvOtlpTracesJson(
        <DVSpan>[spanNamed('queue consume default')],
        serviceName: 'worker');
    final List<Object?> resourceSpans = body['resourceSpans']! as List<Object?>;
    final List<Object?> scopeSpans = (resourceSpans.single!
        as Map<String, Object?>)['scopeSpans']! as List<Object?>;
    final List<Object?> spans =
        (scopeSpans.single! as Map<String, Object?>)['spans']! as List<Object?>;
    final Map<String, Object?> span = spans.single! as Map<String, Object?>;
    final Map<String, Object?> link =
        (span['links']! as List<Object?>).single! as Map<String, Object?>;
    expect(link['traceId'], request.traceId);
  });

  test('a failing job marks its span as an error', () async {
    const DVQueues().register<SendReceipt>((SendReceipt job) {
      throw StateError('mail server said no');
    });
    await const DVQueues().dispatch(const SendReceipt('o-1'));
    await const DVQueues().work();
    final DVSpan consume = spanNamed('queue consume default');
    expect(consume.status, DVSpanStatus.error);
    expect(consume.attributes['error.type'], 'StateError');
  });

  test('dispatching outside any trace publishes no span and sends no context',
      () async {
    final DVJobEnvelope<SendReceipt> job =
        await const DVQueues().dispatch(const SendReceipt('o-1'));
    expect(job.traceparent, isNull);
    expect(DVObservability.recentSpans, isEmpty);
  });
}
