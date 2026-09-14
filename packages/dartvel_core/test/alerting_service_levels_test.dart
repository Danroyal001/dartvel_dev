// Service levels and the signals alert rules read.
//
// An error-budget number is judged by the ones that look right. A burn rate
// that forgets to divide by the budget reports 0.01 for a service burning its
// month ten times too fast, and nothing ever crosses 14.4. A window measured
// from the first sample instead of back from now averages the outage into the
// hours before it. A counter that restarts with the process reads as a negative
// rate, which is below every threshold. A fresh process with ten minutes of
// history, read as if those ten minutes were the whole month, declares the
// budget gone on its first deploy.
//
// And a percentile taken from the wrong index is off by one sample, which on a
// latency alert is the difference between firing and not.
import 'dart:math';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

final DateTime t0 = DateTime.utc(2026, 9, 1);

class _Traffic {
  int total = 0;
  int failed = 0;

  void add({int ok = 0, int failed = 0}) {
    total += ok + failed;
    this.failed += failed;
  }

  DVServiceLevelCounts read() =>
      DVServiceLevelCounts(total: total, failed: failed);
}

class _Diagnostics {
  final List<String> codes = <String>[];
  void call(String code, String message) => codes.add(code);
  int count(String code) => codes.where((String c) => c == code).length;
}

const DVServiceLevel checkout = DVServiceLevel(
  name: 'checkout',
  objective: DVObjective.successRate(0.999, over: Duration(days: 30)),
  applies: DVAppliesTo.backendFunction('createOrder'),
);

DVSpanSample span(String name, int ms, {DateTime? at, bool error = false}) =>
    DVSpanSample(
      name: name,
      startedAt: at ?? t0,
      duration: Duration(milliseconds: ms),
      error: error,
    );

void main() {
  group('an objective', () {
    test('a 99.9% monthly objective is breached by forty-three minutes of '
        'failure', () {
      // The specification's own number. 0.1% of thirty days is 43.2 minutes.
      expect(checkout.objective.budgetTime,
          const Duration(minutes: 43, seconds: 12));
    });

    test('a target that leaves no budget, or promises nothing, is refused', () {
      final DVServiceLevels levels = DVServiceLevels();
      expect(
        () => levels.add(const DVServiceLevel(
          name: 'perfect',
          objective: DVObjective.successRate(1, over: Duration(days: 30)),
          applies: DVAppliesTo.page('/'),
        )),
        throwsArgumentError,
      );
      expect(
        () => levels.add(const DVServiceLevel(
          name: 'nothing',
          objective: DVObjective.successRate(0, over: Duration(days: 30)),
          applies: DVAppliesTo.page('/'),
        )),
        throwsArgumentError,
      );
      expect(
        () => levels.add(const DVServiceLevel(
          name: 'instant',
          objective: DVObjective.successRate(0.99, over: Duration.zero),
          applies: DVAppliesTo.page('/'),
        )),
        throwsArgumentError,
      );
    });

    test('two levels under one name are refused', () {
      final DVServiceLevels levels = DVServiceLevels()..add(checkout);
      expect(() => levels.add(checkout), throwsArgumentError);
    });

    test('what an objective applies to compares by value', () {
      // Built at runtime, so the comparison is by value and not by the
      // canonical const instance.
      expect(const DVAppliesTo.backendFunction('createOrder'),
          DVAppliesTo.backendFunction(<String>['create', 'Order'].join()));
      expect(const DVAppliesTo.backendFunction('createOrder'),
          isNot(const DVAppliesTo.page('createOrder')));
    });
  });

  group('burn rate', () {
    late _Traffic traffic;
    late DVServiceLevels levels;

    setUp(() {
      traffic = _Traffic();
      levels = DVServiceLevels()
        ..add(checkout)
        ..source(checkout.applies, traffic.read);
    });

    test('is the error rate divided by the budget, not the error rate', () {
      levels.sample(t0);
      traffic.add(ok: 990, failed: 10);
      final DateTime now = t0.add(const Duration(hours: 1));
      levels.sample(now);

      // 1% failing against a 0.1% budget is burning ten times too fast.
      expect(levels.burnRate('checkout', const Duration(hours: 1), now: now),
          closeTo(10, 1e-9));
    });

    test('the window is measured back from now, not from the first sample', () {
      levels.sample(t0);
      traffic.add(ok: 500);
      levels.sample(t0.add(const Duration(minutes: 30)));
      traffic.add(ok: 490, failed: 10);
      levels.sample(t0.add(const Duration(minutes: 60)));
      traffic.add(ok: 500);
      final DateTime now = t0.add(const Duration(minutes: 90));
      levels.sample(now);

      // The last hour saw 1000 requests and 10 failures. Measured from the
      // first sample it would be 1500 and 10, a burn of 6.7 that sits under a
      // threshold of 10 while the hour it describes was over it.
      expect(levels.burnRate('checkout', const Duration(hours: 1), now: now),
          closeTo(10, 1e-9));
    });

    test('a counter reset is an increase from zero, not a negative rate', () {
      levels.sample(t0);
      traffic.add(ok: 990, failed: 10);
      levels.sample(t0.add(const Duration(minutes: 10)));

      // The process restarted; its counters start again from nothing.
      traffic
        ..total = 0
        ..failed = 0
        ..add(ok: 50, failed: 50);
      final DateTime now = t0.add(const Duration(minutes: 20));
      levels.sample(now);

      // 1100 requests, 60 failed. A plain last-minus-first reads -890 and
      // +40, a negative request count and a rate below every threshold.
      expect(
          levels.burnRate('checkout', const Duration(minutes: 30), now: now),
          closeTo(60 / 1100 / 0.001, 1e-6));
    });

    test('no traffic in the window is no data, not a perfect score', () {
      levels.sample(t0);
      final DateTime now = t0.add(const Duration(minutes: 5));
      levels.sample(now);
      expect(levels.burnRate('checkout', const Duration(minutes: 5), now: now),
          isNull);
    });

    test('an unknown level has no burn rate', () {
      expect(levels.burnRate('nope', const Duration(hours: 1), now: t0),
          isNull);
    });
  });

  group('the budget', () {
    test('a full window of 0.05% failure has consumed half of a 0.1% budget',
        () {
      final _Traffic traffic = _Traffic();
      final DVServiceLevels levels = DVServiceLevels()
        ..add(checkout)
        ..source(checkout.applies, traffic.read);

      levels.sample(t0);
      traffic.add(ok: 99950, failed: 50);
      final DateTime now = t0.add(const Duration(days: 30));
      levels.sample(now);

      final DVServiceLevelStatus status = levels.status('checkout', now: now);
      expect(status.budgetConsumed, closeTo(0.5, 1e-9));
      expect(status.budgetRemaining, closeTo(0.5, 1e-9));
      expect(status.exhausted, isFalse);
    });

    test('ten minutes of history is ten minutes of the month, not all of it',
        () {
      final _Traffic traffic = _Traffic();
      final DVServiceLevels levels = DVServiceLevels()
        ..add(checkout)
        ..source(checkout.applies, traffic.read);

      levels.sample(t0);
      for (int minute = 1; minute <= 10; minute++) {
        traffic.add(failed: 100);
        levels.sample(t0.add(Duration(minutes: minute)));
      }
      final DateTime now = t0.add(const Duration(minutes: 10));
      final DVServiceLevelStatus status = levels.status('checkout', now: now);

      // Every request failed, for ten of the 43.2 minutes the month allows.
      // Read as if those ten minutes were the whole window it is a thousand
      // times the budget, and a process that restarted during a blip would
      // hold every deploy for a month.
      expect(status.budgetConsumed, closeTo(10 / 43.2, 1e-9));
      expect(status.exhausted, isFalse);
      expect(status.coverage, closeTo(10 / (30 * 24 * 60), 1e-12));
    });

    test('and forty-five minutes of it is past the budget', () {
      final _Traffic traffic = _Traffic();
      final DVServiceLevels levels = DVServiceLevels()
        ..add(checkout)
        ..source(checkout.applies, traffic.read);

      levels.sample(t0);
      for (int minute = 1; minute <= 45; minute++) {
        traffic.add(failed: 100);
        levels.sample(t0.add(Duration(minutes: minute)));
      }
      final DVServiceLevelStatus status =
          levels.status('checkout', now: t0.add(const Duration(minutes: 45)));
      expect(status.exhausted, isTrue);
      expect(status.budgetRemaining, lessThan(0));
    });

    test('exhaustion is reported once per exhaustion, not on every sample', () {
      const DVServiceLevel hourly = DVServiceLevel(
        name: 'search',
        objective: DVObjective.successRate(0.99, over: Duration(hours: 1)),
        applies: DVAppliesTo.page('/search'),
      );
      final _Traffic traffic = _Traffic();
      final _Diagnostics diagnostics = _Diagnostics();
      final DVServiceLevels levels = DVServiceLevels(onDiagnostic: diagnostics)
        ..add(hourly)
        ..source(hourly.applies, traffic.read);

      int minute = 0;
      void tick({int ok = 0, int failed = 0}) {
        traffic.add(ok: ok, failed: failed);
        levels.sample(t0.add(Duration(minutes: minute++)));
      }

      tick();
      for (int i = 0; i < 3; i++) {
        tick(failed: 100);
      }
      for (int i = 0; i < 10; i++) {
        tick(ok: 100);
      }
      expect(diagnostics.count('DV-ALERT-003'), 1);

      // Seventy healthy minutes move the failures out of the window, and the
      // budget comes back.
      for (int i = 0; i < 70; i++) {
        tick(ok: 100);
      }
      expect(
          levels
              .status('search', now: t0.add(Duration(minutes: minute - 1)))
              .exhausted,
          isFalse);

      for (int i = 0; i < 3; i++) {
        tick(failed: 100);
      }
      expect(diagnostics.count('DV-ALERT-003'), 2);
    });

    test('a level with no source has no status rather than a clean one', () {
      final DVServiceLevels levels = DVServiceLevels()..add(checkout);
      levels.sample(t0);
      levels.sample(t0.add(const Duration(hours: 1)));
      final DVServiceLevelStatus status =
          levels.status('checkout', now: t0.add(const Duration(hours: 1)));
      expect(status.hasData, isFalse);
      expect(status.budgetRemaining, isNull);
      expect(status.exhausted, isFalse);
    });

    test('the release gate holds while a budget is exhausted', () {
      final _Traffic traffic = _Traffic();
      final DVServiceLevels levels = DVServiceLevels()
        ..add(checkout)
        ..source(checkout.applies, traffic.read);
      final DVErrorBudgetGate gate = DVErrorBudgetGate(levels);

      levels.sample(t0);
      traffic.add(ok: 1000);
      levels.sample(t0.add(const Duration(hours: 1)));
      expect(gate.evaluate(now: t0.add(const Duration(hours: 1))).hold,
          isFalse);

      for (int minute = 61; minute <= 120; minute++) {
        traffic.add(failed: 100);
        levels.sample(t0.add(Duration(minutes: minute)));
      }
      final DVErrorBudgetDecision decision =
          gate.evaluate(now: t0.add(const Duration(minutes: 120)));
      expect(decision.hold, isTrue);
      expect(decision.exhausted, <String>['checkout']);
    });
  });

  group('signals', () {
    test('a metric reads the registry, and a name nobody registered is '
        'missing rather than zero', () {
      final DVMetrics metrics = DVMetrics();
      metrics.gauge('queue_depth', <String, String>{'queue': 'mail'}).set(42);
      metrics.counter('http_requests_total',
          <String, String>{'status': '200'}).increment(3);
      final DVSignalReaders readers = DVSignalReaders(metrics: metrics);

      expect(
          readers
              .read(const DVSignalRef.metric('queue_depth',
                  labels: <String, String>{'queue': 'mail'}), now: t0)
              .value,
          42);
      final DVSignalReading gone =
          readers.read(const DVSignalRef.metric('queue_lenght'), now: t0);
      expect(gone.status, DVSignalReadingStatus.missing);
      expect(gone.value, isNull);

      // Registered, but no request has been answered with a 500 yet: that is
      // quiet, not gone.
      final DVSignalReading quiet = readers.read(
          const DVSignalRef.metric('http_requests_total',
              labels: <String, String>{'status': '500'}),
          now: t0);
      expect(quiet.status, DVSignalReadingStatus.noData);
    });

    test('a trace percentile is the nearest rank, over spans in any order', () {
      final List<int> ms = List<int>.generate(20, (int i) => i + 1)
        ..shuffle(Random(7));
      final DVSignalReaders readers = DVSignalReaders(
        spans: () => <DVSpanSample>[
          for (final int m in ms) span('createOrder', m),
          span('listOrders', 5000),
        ],
      );

      Duration? stat(DVTraceStat s) => readers
          .read(DVSignalRef.trace('createOrder', s), now: t0)
          .duration;

      // Nearest rank: ceil(0.95 * 20) = the 19th smallest. Index 19 of the
      // sorted list is the 20th, and an unsorted list is whatever finished
      // nineteenth.
      expect(stat(DVTraceStat.p95), const Duration(milliseconds: 19));
      expect(stat(DVTraceStat.p50), const Duration(milliseconds: 10));
      expect(stat(DVTraceStat.max), const Duration(milliseconds: 20));

      final DVSignalReaders hundred = DVSignalReaders(
        spans: () => <DVSpanSample>[
          for (int m = 100; m >= 1; m--) span('createOrder', m),
        ],
      );
      expect(
          hundred
              .read(const DVSignalRef.trace('createOrder', DVTraceStat.p99),
                  now: t0)
              .duration,
          const Duration(milliseconds: 99));
    });

    test('only spans inside the window count', () {
      final DVSignalReaders readers = DVSignalReaders(
        spans: () => <DVSpanSample>[
          span('createOrder', 9000, at: t0.subtract(const Duration(hours: 1))),
          span('createOrder', 100, at: t0.subtract(const Duration(minutes: 1))),
        ],
      );
      expect(
          readers
              .read(const DVSignalRef.trace('createOrder', DVTraceStat.max),
                  now: t0)
              .duration,
          const Duration(milliseconds: 100));

      final DVSignalReading none = readers.read(
          const DVSignalRef.trace('createOrder', DVTraceStat.max),
          now: t0.add(const Duration(hours: 2)));
      expect(none.status, DVSignalReadingStatus.noData);
    });

    test('the default trace source is the spans this process recorded', () {
      DVObservability.resetTracing();
      final DVSpan real = DVObservability.tracer.startSpan('createOrder');
      real.end();
      final DVSignalReading reading = DVSignalReaders().read(
          const DVSignalRef.trace('createOrder', DVTraceStat.max),
          now: DateTime.now().add(const Duration(seconds: 1)));
      expect(reading.status, DVSignalReadingStatus.value);
      expect(reading.duration, real.duration);
      DVObservability.resetTracing();
    });

    test('a crash rate is crashed sessions over sessions that started', () {
      final DVReleaseHealth health = DVReleaseHealth();
      for (int i = 0; i < 10; i++) {
        health.sessionStarted(
            sessionId: 's$i', installId: 'i$i', release: '2.0.0');
      }
      health.sessionCrashed(sessionId: 's3');
      final DVSignalReaders readers = DVSignalReaders(releaseHealth: health);

      expect(readers.read(const DVSignalRef.crashRate('2.0.0'), now: t0).value,
          closeTo(0.1, 1e-12));
      expect(
          readers.read(const DVSignalRef.crashRate('2.1.0'), now: t0).status,
          DVSignalReadingStatus.noData);
    });

    test('a signal only the application can measure is missing until it is '
        'registered, and again once it is removed', () {
      final DVSignalReaders readers = DVSignalReaders();
      const DVSignalRef depth = DVSignalRef.queueDepth('mail');
      expect(readers.read(depth, now: t0).status,
          DVSignalReadingStatus.missing);

      readers.register(depth, () => 12);
      expect(readers.read(depth, now: t0).value, 12);

      readers.unregister(depth);
      expect(readers.read(depth, now: t0).status,
          DVSignalReadingStatus.missing);
    });

    test('an error-budget burn needs both windows burning', () {
      final _Traffic traffic = _Traffic();
      final DVServiceLevels levels = DVServiceLevels()
        ..add(checkout)
        ..source(checkout.applies, traffic.read);
      final DVSignalReaders readers = DVSignalReaders(serviceLevels: levels);
      const DVSignalRef burn = DVSignalRef.errorBudgetBurn('checkout');

      levels.sample(t0);
      for (int minute = 1; minute <= 30; minute++) {
        traffic.add(ok: 80, failed: 20);
        levels.sample(t0.add(Duration(minutes: minute)));
      }
      for (int minute = 31; minute <= 40; minute++) {
        traffic.add(ok: 100);
        levels.sample(t0.add(Duration(minutes: minute)));
      }

      // The hour is still burning hard; the last five minutes are clean. The
      // outage is over, and paging now wakes someone to look at a recovery.
      final DateTime now = t0.add(const Duration(minutes: 40));
      expect(levels.burnRate('checkout', const Duration(hours: 1), now: now),
          greaterThan(14.4));
      expect(readers.read(burn, now: now).value, 0);

      expect(
          readers
              .read(const DVSignalRef.errorBudgetBurn('nope'), now: now)
              .status,
          DVSignalReadingStatus.missing);
    });
  });
}
