import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/dv.dart';

// Under lib/backend and outside functions/, so none of this is a URL.

Future<void> serverLogging() async {
  // docs:start monitoring-server-log
  // The same two names on the server: DV.log for a line, and
  // DV.ObservabilityAndLogging for everything the server serves about itself.
  DV.log('Refund accepted', context: <String, Object?>{'orderId': 'o-42'});

  DV.log(
    'Gateway slow',
    level: DVLogLevel.warn,
    // A code is what an alert rule matches on. Wording changes; this does not.
    code: 'PAY-SLOW',
    context: <String, Object?>{'gateway': 'stripe', 'ms': 2400},
  );
  // docs:end
}

void serverMetrics() {
  // docs:start monitoring-server-metrics
  // Registered on first use, and served at GET /metrics as Prometheus text.
  DV.ObservabilityAndLogging.metrics
      .counter('refunds_total', <String, String>{'currency': 'usd'})
      .increment();

  DV.ObservabilityAndLogging.metrics.gauge('queue_depth').set(12);

  DV.ObservabilityAndLogging.metrics
      .histogram('checkout_seconds')
      .observe(0.42);
  // docs:end
}

void serverHealth() {
  // docs:start monitoring-server-health
  // Each check answers for itself when GET /health is asked, under a
  // deadline. Degraded is not down: a cold cache is slow, and reporting it
  // as an outage pages somebody for nothing.
  DV.ObservabilityAndLogging.health.register('payments', () async {
    final bool reachable = await gatewayReachable();
    return reachable
        ? DVHealthResult.up()
        : DVHealthResult.down('the gateway did not answer');
  });
  // docs:end
}

Future<void> serverTracing() async {
  // docs:start monitoring-server-trace
  // The request already has a span, joined to the traceparent it arrived
  // with. This is for the work inside it worth seeing on its own.
  final DVSpan span =
      DV.ObservabilityAndLogging.tracer.startSpan('reprice-basket');
  span.setAttribute('basket.id', 'b-9');
  try {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  } finally {
    // In a finally: a thrown error would otherwise leave the span open, and
    // the trace then shows a request that never ended.
    span.end();
  }
  // docs:end
}

Future<bool> gatewayReachable() async => true;
