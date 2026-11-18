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
  // with. This is a step inside it worth seeing on its own: a child of the
  // request's span, ended when the work returns or throws, with any query
  // or outbound call made inside it nested under it.
  await DV.ObservabilityAndLogging.tracer.trace('reprice-basket',
      (DVSpan span) async {
    span.setAttribute('basket.id', 'b-9');
    span.setAttribute('basket.items', 3); // an int stays an int
    await Future<void>.delayed(const Duration(milliseconds: 5));
  });
  // docs:end
}

void openTelemetryInCode() {
  // docs:start otel-code
  // The same switch the pubspec section is, for a project that configures
  // export in code -- in an @DVBoot function, say. The OTEL_* variables on
  // the deployment are still applied over it.
  DV.ObservabilityAndLogging.useOpenTelemetry(const DVOpenTelemetryConfig(
    enabled: true,
    endpoint: 'https://otlp.example.com',
    secretHeaders: <String, String>{'authorization': 'OTLP_AUTH_HEADER'},
    serviceName: 'shop-api',
    resourceAttributes: <String, String>{'team': 'checkout'},
    sampler: DVOtelSampler.parentBasedTraceIdRatio,
    ratio: 0.1,
  ));
  // docs:end
}


Future<bool> gatewayReachable() async => true;
