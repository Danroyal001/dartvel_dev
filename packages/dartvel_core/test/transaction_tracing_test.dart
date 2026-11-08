// A DV.transaction inside a request is a span, with the compensations that
// ran.
//
// A rolled-back order and a committed one look the same from the request's
// span: both are a POST that took 300ms. The transaction's own span is what
// says which, and which compensations ran -- the part of a failure that is
// otherwise reconstructed from logs.
import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/src/observability/observability.dart';
import 'package:test/test.dart';

void main() {
  late DVTransactionRunner transaction;
  setUp(() {
    transaction = DVTransactionRunner();
    DVObservability.resetTracing();
  });
  tearDown(DVObservability.resetTracing);

  DVSpan spanNamed(String name) =>
      DVObservability.recentSpans.singleWhere((DVSpan s) => s.name == name);

  test('a committed transaction is a span under the request, and work in its '
      'body hangs under it', () async {
    final DVSpan request = DVObservability.tracer.startSpan('POST /orders');
    await dvInSpan(request, () async {
      await transaction((DVContext context) async {
        DVObservability.tracer.startSpan('inner', parent: dvCurrentSpan).end();
      });
    });
    request.end();

    final DVSpan tx = spanNamed('transaction');
    expect(tx.parentSpanId, request.spanId);
    expect(tx.traceId, request.traceId);
    expect(tx.status, DVSpanStatus.ok);
    expect(tx.attributes['transaction.outcome'], 'committed');
    expect(spanNamed('inner').parentSpanId, tx.spanId);
  });

  test('a rollback records the compensations that ran, and the error type '
      'rather than its message', () async {
    final DVSpan request = DVObservability.tracer.startSpan('POST /orders');
    await dvInSpan(request, () async {
      await expectLater(
        transaction((DVContext context) async {
          context
            ..compensate(() {})
            ..compensate(() {});
          throw StateError('card 4242 4242 4242 4242 declined');
        }),
        throwsStateError,
      );
    });
    request.end();

    final DVSpan tx = spanNamed('transaction');
    expect(tx.status, DVSpanStatus.error);
    expect(tx.attributes['transaction.outcome'], 'compensated');
    expect(tx.attributes['transaction.compensations'], '2');
    expect(tx.attributes['error.type'], 'StateError');
    expect(tx.attributes.values.join(), isNot(contains('4242')));
  });

  test('a joined transaction is not a second span', () async {
    final DVSpan request = DVObservability.tracer.startSpan('POST /orders');
    await dvInSpan(request, () async {
      await transaction((DVContext outer) async {
        await transaction((DVContext inner) async {});
      });
    });
    request.end();
    expect(
        DVObservability.recentSpans.where((DVSpan s) => s.name == 'transaction'),
        hasLength(1));
  });

  test('a transaction outside any span starts no trace', () async {
    await transaction((DVContext context) async {});
    expect(DVObservability.recentSpans, isEmpty);
  });
}
