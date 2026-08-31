import 'dart:async';

// Metrics and health, which the built-in endpoints were pretending to have.
//
// GET /health returned the literal {'status':'ok'}. It checked nothing, so it
// could not fail -- and a health check that cannot fail is worse than none at
// all: a load balancer keeps routing to an instance whose database is gone,
// and the dashboard stays green through the outage.
//
// There was no /metrics at all, though the framework's own site documented one.
import 'package:dartvel_core/src/observability/health.dart';
import 'package:dartvel_core/src/observability/metrics.dart';
import 'package:test/test.dart';

void main() {
  group('counters', () {
    late DVMetrics metrics;
    setUp(() => metrics = DVMetrics());

    test('a counter starts absent, not at zero', () {
      // A metric that reports 0 before anything has happened is
      // indistinguishable from one reporting a genuine zero, and alerting on
      // "no requests" is a real thing people do.
      expect(metrics.render(), isNot(contains('dartvel_requests_total')));
    });

    test('it counts', () {
      metrics.counter('requests_total').increment();
      metrics.counter('requests_total').increment(4);
      expect(metrics.render(), contains('dartvel_requests_total 5'));
    });

    test('labels are separate series', () {
      metrics.counter('requests_total', <String, String>{'route': '/a'})
          .increment();
      metrics.counter('requests_total', <String, String>{'route': '/b'})
          .increment(2);

      final String out = metrics.render();
      expect(out, contains('dartvel_requests_total{route="/a"} 1'));
      expect(out, contains('dartvel_requests_total{route="/b"} 2'));
    });

    test('label values are escaped', () {
      // A label value carrying a quote or a newline breaks the exposition
      // format, and Prometheus rejects the whole scrape -- so one bad route
      // name silently takes out every metric on the instance.
      metrics.counter('requests_total',
          <String, String>{'route': 'a"b\nc\\d'}).increment();

      final String out = metrics.render();
      expect(out, contains(r'route="a\"b\nc\\d"'));
    });

    test('a counter never goes backwards', () {
      // Prometheus computes rates from the assumption that it does not.
      expect(() => metrics.counter('requests_total').increment(-1),
          throwsArgumentError);
    });
  });

  group('gauges', () {
    test('a gauge is set, and may fall', () {
      final DVMetrics metrics = DVMetrics();
      metrics.gauge('queue_depth').set(9);
      metrics.gauge('queue_depth').set(3);
      expect(metrics.render(), contains('dartvel_queue_depth 3'));
    });
  });

  group('histograms', () {
    test('it renders buckets, a sum and a count', () {
      final DVMetrics metrics = DVMetrics();
      metrics.histogram('request_seconds').observe(0.003);
      metrics.histogram('request_seconds').observe(0.3);

      final String out = metrics.render();
      expect(out, contains('dartvel_request_seconds_bucket{le="0.005"} 1'));
      expect(out, contains('dartvel_request_seconds_bucket{le="+Inf"} 2'));
      expect(out, contains('dartvel_request_seconds_count 2'));
      expect(out, contains('dartvel_request_seconds_sum 0.303'));
    });

    test('buckets are cumulative', () {
      // le="0.5" means "at most 0.5", which includes everything in the
      // smaller buckets. Non-cumulative buckets render a histogram that looks
      // plausible and computes every quantile wrong.
      final DVMetrics metrics = DVMetrics();
      for (final double value in <double>[0.001, 0.02, 0.4]) {
        metrics.histogram('request_seconds').observe(value);
      }

      final String out = metrics.render();
      expect(out, contains('dartvel_request_seconds_bucket{le="0.005"} 1'));
      expect(out, contains('dartvel_request_seconds_bucket{le="0.025"} 2'));
      expect(out, contains('dartvel_request_seconds_bucket{le="0.5"} 3'));
    });
  });

  group('exposition format', () {
    test('every metric declares its type', () {
      // Without a TYPE line Prometheus guesses untyped, and a counter scraped
      // as untyped cannot have rate() applied to it.
      final DVMetrics metrics = DVMetrics();
      metrics.counter('requests_total').increment();
      metrics.gauge('queue_depth').set(1);

      final String out = metrics.render();
      expect(out, contains('# TYPE dartvel_requests_total counter'));
      expect(out, contains('# TYPE dartvel_queue_depth gauge'));
    });

    test('a name is declared once however many series it has', () {
      // A repeated HELP or TYPE for the same name is a parse error, not a
      // warning.
      final DVMetrics metrics = DVMetrics();
      metrics.counter('requests_total', <String, String>{'route': '/a'})
          .increment();
      metrics.counter('requests_total', <String, String>{'route': '/b'})
          .increment();

      final String out = metrics.render();
      expect('# TYPE dartvel_requests_total counter'.allMatches(out).length, 1);
    });

    test('it ends with a newline', () {
      // The exposition format requires it and some scrapers drop the last
      // line without it.
      final DVMetrics metrics = DVMetrics();
      metrics.counter('requests_total').increment();
      expect(metrics.render(), endsWith('\n'));
    });
  });

  group('health', () {
    test('with no checks registered it is up', () {
      final DVHealth health = DVHealth();
      expect(health.report().status, DVHealthStatus.up);
    });

    test('a failing check brings the report down', () {
      final DVHealth health = DVHealth()
        ..register('database', () async => DVHealthResult.down('no route'));

      expect(health.reportAsync(), completion(
          predicate<DVHealthReport>((DVHealthReport r) =>
              r.status == DVHealthStatus.down)));
    });

    test('a degraded check does not read as down', () async {
      // The distinction a load balancer needs: degraded still serves, down
      // should be taken out of rotation.
      final DVHealth health = DVHealth()
        ..register('cache', () async => DVHealthResult.degraded('slow'));

      expect((await health.reportAsync()).status, DVHealthStatus.degraded);
    });

    test('down beats degraded', () async {
      final DVHealth health = DVHealth()
        ..register('cache', () async => DVHealthResult.degraded('slow'))
        ..register('database', () async => DVHealthResult.down('gone'));

      expect((await health.reportAsync()).status, DVHealthStatus.down);
    });

    test('a check that throws is down, not an error page', () async {
      // The endpoint has to answer. A health check that 500s tells a load
      // balancer nothing about which instance is bad.
      final DVHealth health = DVHealth()
        ..register('database', () async => throw StateError('boom'));

      final DVHealthReport report = await health.reportAsync();
      expect(report.status, DVHealthStatus.down);
      expect(report.checks['database']!.detail, contains('boom'));
    });

    test('a check that hangs is down rather than hanging the endpoint',
        () async {
      // The failure mode that matters: a database with a dead connection
      // does not refuse, it waits. A health endpoint that waits with it is
      // the outage.
      final DVHealth health = DVHealth(timeout: const Duration(milliseconds: 40))
        ..register('database', () => Completer<DVHealthResult>().future);

      final DVHealthReport report = await health.reportAsync();
      expect(report.status, DVHealthStatus.down);
      expect(report.checks['database']!.detail, contains('timed out'));
    });

    test('the report carries uptime and the checks that ran', () async {
      final DVHealth health = DVHealth()
        ..register('cache', () async => DVHealthResult.up());

      final DVHealthReport report = await health.reportAsync();
      expect(report.checks.keys, contains('cache'));
      expect(report.uptime, isA<Duration>());
    });
  });
}
