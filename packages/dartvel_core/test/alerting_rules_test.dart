// Alert rules: state, deduplication, delivery, and noise.
//
// An alerting engine fails quietly in a handful of well-known ways. It fires
// on one sample, so a garbage-collection pause pages someone and the rule gets
// muted. It flaps: a signal hovering at the threshold fires, resolves and fires
// again, and every edge is a page. It never resolves, so the incident on the
// pager service stays open until a human closes it and the next real one is
// deduplicated into it. It sends the resolve under a different key than the
// trigger, which is the same thing. It fails to deliver once and never tries
// again while the alert stays firing. And it retries by re-paging everyone who
// already got it.
//
// Every group below is one of those.
import 'dart:async';
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

final DateTime t0 = DateTime.utc(2026, 9, 1, 3);

DateTime at(int minutes, [int seconds = 0]) =>
    t0.add(Duration(minutes: minutes, seconds: seconds));

class _Diagnostics {
  final List<String> codes = <String>[];
  final List<String> messages = <String>[];
  void call(String code, String message) {
    codes.add(code);
    messages.add(message);
  }

  int count(String code) => codes.where((String c) => c == code).length;
}

class _SpyProvider implements DVNotificationProvider {
  _SpyProvider(this.kind);

  @override
  final DVNotificationProviderKind kind;

  bool failing = false;
  final List<DVSentNotification> sent = <DVSentNotification>[];

  @override
  Future<void> send(String recipient, DVNotificationMessage message) async {
    if (failing) throw StateError('provider down');
    sent.add(DVSentNotification(recipient: recipient, message: message));
  }
}

class _SpyPager implements DVAlertPager {
  bool failing = false;
  final List<DVAlertEvent> triggers = <DVAlertEvent>[];
  final List<DVAlertEvent> resolves = <DVAlertEvent>[];

  @override
  Future<void> trigger(DVAlertEvent event) async {
    if (failing) throw StateError('pager down');
    triggers.add(event);
  }

  @override
  Future<void> resolve(DVAlertEvent event) async {
    if (failing) throw StateError('pager down');
    resolves.add(event);
  }
}

class _SlowPager implements DVAlertPager {
  final Completer<void> release = Completer<void>();
  final List<DVAlertEvent> triggers = <DVAlertEvent>[];

  @override
  Future<void> trigger(DVAlertEvent event) async {
    await release.future;
    triggers.add(event);
  }

  @override
  Future<void> resolve(DVAlertEvent event) async {}
}

/// A gauge the test moves by hand.
class _Signal {
  num? value;
  num? call() => value;
}

const DVSignalRef depth = DVSignalRef.queueDepth('mail');

DVAlertRule depthRule({
  String name = 'mail-backlog',
  Duration forDuration = const Duration(minutes: 5),
  Duration? resolveAfter,
  Duration? repeatEvery,
  List<DVAlertTarget> notify = const <DVAlertTarget>[
    DVAlertTarget.user('ops-1'),
  ],
}) =>
    DVAlertRule(
      name: name,
      signal: depth,
      condition: const DVAlertWhen.above(100),
      forDuration: forDuration,
      resolveAfter: resolveAfter,
      repeatEvery: repeatEvery,
      notify: notify,
    );

void main() {
  const DVNotificationsService notifications = DVNotificationsService();
  late _SpyProvider inApp;
  late _Signal signal;
  late DVSignalReaders readers;
  late _Diagnostics diagnostics;

  setUp(() {
    inApp = _SpyProvider(DVNotificationProviderKind.local);
    notifications
      ..resetRouting()
      ..register(inApp);
    signal = _Signal();
    readers = DVSignalReaders()..register(depth, signal.call);
    diagnostics = _Diagnostics();
  });

  DVAlerting engine({
    Map<String, DVAlertPager> pagers = const <String, DVAlertPager>{},
    DVAlertTeamResolver? teams,
    DVIncidents? incidents,
  }) =>
      DVAlerting(
        readers: readers,
        notifications: notifications,
        pagers: pagers,
        teams: teams,
        incidents: incidents,
        onDiagnostic: diagnostics.call,
      );

  group('declaring a rule', () {
    test('a rule that fires on a single sample is refused', () {
      expect(() => engine().addRule(depthRule(forDuration: Duration.zero)),
          throwsArgumentError);
    });

    test('a duration threshold on a numeric signal, or the reverse, is '
        'refused rather than compared as numbers', () {
      final DVAlerting alerting = engine();
      expect(
        () => alerting.addRule(const DVAlertRule(
          name: 'latency-as-number',
          signal: DVSignalRef.trace('createOrder', DVTraceStat.p95),
          condition: DVAlertWhen.above(800),
          forDuration: Duration(minutes: 5),
          notify: <DVAlertTarget>[DVAlertTarget.user('ops-1')],
        )),
        throwsArgumentError,
      );
      expect(
        () => alerting.addRule(const DVAlertRule(
          name: 'depth-as-duration',
          signal: depth,
          condition: DVAlertWhen.above(Duration(seconds: 1)),
          forDuration: Duration(minutes: 5),
          notify: <DVAlertTarget>[DVAlertTarget.user('ops-1')],
        )),
        throwsArgumentError,
      );
    });

    test('the specification\'s own rule is accepted as written', () {
      engine().addRule(const DVAlertRule(
        name: 'checkout-latency',
        signal: DVSignalRef.trace('createOrder', DVTraceStat.p95),
        condition: DVAlertWhen.above(Duration(milliseconds: 800)),
        forDuration: Duration(minutes: 5),
        notify: <DVAlertTarget>[DVAlertTarget.team('payments')],
      ));
    });

    test('two rules under one name are refused', () {
      final DVAlerting alerting = engine()..addRule(depthRule());
      expect(() => alerting.addRule(depthRule()), throwsArgumentError);
    });

    test('a rule with no target is reported, since it makes the dashboard '
        'look covered', () {
      engine().addRule(depthRule(notify: const <DVAlertTarget>[]));
      expect(diagnostics.count('DV-ALERT-005'), 1);
    });
  });

  group('state', () {
    test('a breach shorter than forDuration never fires', () async {
      final DVAlerting alerting = engine()..addRule(depthRule());

      signal.value = 500;
      await alerting.evaluate(now: at(0));
      await alerting.evaluate(now: at(4, 59));
      expect(alerting.state('mail-backlog').status, DVAlertStatus.pending);
      signal.value = 3;
      await alerting.evaluate(now: at(5));
      signal.value = 500;
      await alerting.evaluate(now: at(6));
      await alerting.evaluate(now: at(10));

      // Pending restarted at minute 6; four minutes is not five.
      expect(alerting.state('mail-backlog').status, DVAlertStatus.pending);
      expect(inApp.sent, isEmpty);
    });

    test('a breach held for forDuration fires once, however often it is '
        'evaluated', () async {
      final DVAlerting alerting = engine()..addRule(depthRule());

      signal.value = 500;
      for (int minute = 0; minute <= 30; minute++) {
        await alerting.evaluate(now: at(minute));
      }
      expect(alerting.state('mail-backlog').status, DVAlertStatus.firing);
      expect(alerting.state('mail-backlog').firingSince, at(5));
      expect(inApp.sent, hasLength(1));
      expect(inApp.sent.single.recipient, 'ops-1');
      expect(inApp.sent.single.message.title, contains('mail-backlog'));
      expect(diagnostics.count('DV-ALERT-001'), 1);
    });

    test('an alert resolves, and says so, once the signal has recovered',
        () async {
      final DVAlerting alerting = engine()..addRule(depthRule());

      signal.value = 500;
      for (int minute = 0; minute <= 6; minute++) {
        await alerting.evaluate(now: at(minute));
      }
      signal.value = 0;
      for (int minute = 7; minute <= 20; minute++) {
        await alerting.evaluate(now: at(minute));
      }

      expect(alerting.state('mail-backlog').status, DVAlertStatus.inactive);
      expect(inApp.sent, hasLength(2));
      expect(inApp.sent.last.message.title, contains('RESOLVED'));
    });

    test('a signal that stops reporting resolves rather than firing forever',
        () async {
      final DVAlerting alerting = engine()..addRule(depthRule());
      signal.value = 500;
      for (int minute = 0; minute <= 6; minute++) {
        await alerting.evaluate(now: at(minute));
      }
      signal.value = null;
      for (int minute = 7; minute <= 20; minute++) {
        await alerting.evaluate(now: at(minute));
      }
      expect(alerting.state('mail-backlog').status, DVAlertStatus.inactive);
    });

    test('a signal hovering at the threshold pages once, not on every edge',
        () async {
      final DVAlerting alerting = engine()
        ..addRule(depthRule(forDuration: const Duration(minutes: 1)));

      // Two minutes over, two minutes under, for two hours.
      for (int minute = 0; minute <= 120; minute++) {
        signal.value = (minute ~/ 2).isEven ? 500 : 0;
        await alerting.evaluate(now: at(minute));
      }
      expect(
          inApp.sent
              .where((DVSentNotification n) =>
                  !n.message.title.contains('RESOLVED'))
              .length,
          1);
    });

    test('a still-firing alert is repeated only when asked, on its interval',
        () async {
      final DVAlerting alerting = engine()
        ..addRule(depthRule(repeatEvery: const Duration(minutes: 30)));
      signal.value = 500;
      for (int minute = 0; minute <= 70; minute++) {
        await alerting.evaluate(now: at(minute));
      }
      // Fired at 5, repeated at 35 and 65.
      expect(inApp.sent, hasLength(3));
    });

    test('a rule naming a signal that no longer exists is reported, once, and '
        'neither fires nor resolves on it', () async {
      final DVAlerting alerting = engine()..addRule(depthRule());
      signal.value = 500;
      for (int minute = 0; minute <= 6; minute++) {
        await alerting.evaluate(now: at(minute));
      }
      readers.unregister(depth);
      for (int minute = 7; minute <= 30; minute++) {
        await alerting.evaluate(now: at(minute));
      }

      expect(diagnostics.count('DV-ALERT-006'), 1);
      // A renamed metric is not a recovery, and announcing one is a lie told
      // at exactly the moment nobody is watching the signal.
      expect(alerting.state('mail-backlog').status, DVAlertStatus.firing);
      expect(inApp.sent, hasLength(1));

      readers.register(depth, signal.call);
      signal.value = 0;
      for (int minute = 31; minute <= 45; minute++) {
        await alerting.evaluate(now: at(minute));
      }
      expect(alerting.state('mail-backlog').status, DVAlertStatus.inactive);
      readers.unregister(depth);
      await alerting.evaluate(now: at(46));
      expect(diagnostics.count('DV-ALERT-006'), 2);
    });

    test('two evaluations at once do not both page', () async {
      final _SlowPager pager = _SlowPager();
      final DVAlerting alerting = engine(
          pagers: <String, DVAlertPager>{'pagerduty': pager})
        ..addRule(depthRule(
          forDuration: const Duration(minutes: 1),
          notify: const <DVAlertTarget>[DVAlertTarget.pager('pagerduty')],
        ));
      signal.value = 500;
      await alerting.evaluate(now: at(0));

      // A timer that fires while the previous evaluation is still waiting on
      // a slow pager.
      final Future<void> first = alerting.evaluate(now: at(1));
      final Future<void> second = alerting.evaluate(now: at(1, 30));
      pager.release.complete();
      await Future.wait(<Future<void>>[first, second]);

      expect(pager.triggers, hasLength(1));
    });

    test('a trace rule compares durations', () async {
      final DVSignalReaders traces = DVSignalReaders(
        spans: () => <DVSpanSample>[
          for (int i = 1; i <= 20; i++)
            DVSpanSample(
              name: 'createOrder',
              startedAt: at(0),
              duration: Duration(milliseconds: 790 + i),
            ),
        ],
      );
      final DVAlerting alerting = DVAlerting(
        readers: traces,
        notifications: notifications,
        onDiagnostic: diagnostics.call,
      )..addRule(const DVAlertRule(
          name: 'checkout-latency',
          signal: DVSignalRef.trace('createOrder', DVTraceStat.p95,
              window: Duration(hours: 1)),
          condition: DVAlertWhen.above(Duration(milliseconds: 800)),
          forDuration: Duration(minutes: 5),
          notify: <DVAlertTarget>[DVAlertTarget.user('ops-1')],
        ));

      for (int minute = 0; minute <= 5; minute++) {
        await alerting.evaluate(now: at(minute));
      }
      // p95 is the 19th of 791..810 ms: 809, above 800.
      expect(alerting.state('checkout-latency').status, DVAlertStatus.firing);
    });
  });

  group('delivery', () {
    Future<void> fire(DVAlerting alerting, {int from = 0, int to = 6}) async {
      signal.value = 500;
      for (int minute = from; minute <= to; minute++) {
        await alerting.evaluate(now: at(minute));
      }
    }

    test('a team is resolved to its members, and each is notified', () async {
      final DVAlerting alerting = engine(
        teams: (String team) async =>
            team == 'payments' ? <String>['ana', 'bo'] : <String>[],
      )..addRule(depthRule(
          notify: const <DVAlertTarget>[DVAlertTarget.team('payments')]));
      await fire(alerting);
      expect(inApp.sent.map((DVSentNotification n) => n.recipient),
          unorderedEquals(<String>['ana', 'bo']));
    });

    test('an alert that reached nobody is reported and tried again, and '
        'stops once it lands', () async {
      final DVAlerting alerting = engine()..addRule(depthRule());
      inApp.failing = true;
      await fire(alerting, to: 8);
      expect(diagnostics.count('DV-ALERT-002'), 1);
      expect(diagnostics.count('DV-ALERT-001'), 0);
      expect(alerting.state('mail-backlog').delivered, isFalse);

      inApp.failing = false;
      await fire(alerting, from: 9, to: 20);
      expect(inApp.sent, hasLength(1));
      expect(diagnostics.count('DV-ALERT-001'), 1);
      expect(alerting.state('mail-backlog').delivered, isTrue);
    });

    test('a retry reaches only the targets that missed it', () async {
      final _SpyPager pager = _SpyPager()..failing = true;
      final DVAlerting alerting = engine(
          pagers: <String, DVAlertPager>{'pagerduty': pager})
        ..addRule(depthRule(notify: const <DVAlertTarget>[
          DVAlertTarget.user('ops-1'),
          DVAlertTarget.pager('pagerduty'),
        ]));

      await fire(alerting, to: 7);
      expect(inApp.sent, hasLength(1));
      expect(diagnostics.count('DV-ALERT-002'), 0);

      pager.failing = false;
      await fire(alerting, from: 8, to: 12);
      expect(pager.triggers, hasLength(1));
      // The person who was already woken is not woken again by the pager's
      // recovery.
      expect(inApp.sent, hasLength(1));
    });

    test('a recipient who muted every channel did not receive it', () async {
      // The notification service does not throw for this -- a muted
      // recipient is a preference, not a fault -- so a delivery that reached
      // nobody comes back looking like a normal return.
      notifications.usePreferences((String _) async =>
          const DVNotificationPreferences(unsubscribed: true));
      final DVAlerting alerting = engine()..addRule(depthRule());
      await fire(alerting);
      expect(inApp.sent, isEmpty);
      expect(alerting.state('mail-backlog').delivered, isFalse);
      expect(diagnostics.count('DV-ALERT-002'), 1);
      expect(diagnostics.count('DV-ALERT-001'), 0);
    });

    test('a target nobody can resolve counts as undelivered', () async {
      final DVAlerting alerting = engine()
        ..addRule(depthRule(notify: const <DVAlertTarget>[
          DVAlertTarget.team('nobody'),
          DVAlertTarget.pager('unregistered'),
        ]));
      await fire(alerting);
      expect(diagnostics.count('DV-ALERT-002'), 1);
    });

    test('a pager is triggered, repeated and resolved under one key per '
        'episode', () async {
      final _SpyPager pager = _SpyPager();
      final DVAlerting alerting = engine(
          pagers: <String, DVAlertPager>{'pagerduty': pager})
        ..addRule(depthRule(
          repeatEvery: const Duration(minutes: 10),
          notify: const <DVAlertTarget>[DVAlertTarget.pager('pagerduty')],
        ));

      await fire(alerting, to: 20);
      signal.value = 0;
      for (int minute = 21; minute <= 30; minute++) {
        await alerting.evaluate(now: at(minute));
      }
      await fire(alerting, from: 31, to: 40);

      expect(pager.triggers, hasLength(3));
      expect(pager.resolves, hasLength(1));
      final String first = pager.triggers.first.dedupKey;
      // A resolve under any other key leaves the pager's incident open, and
      // the next outage is deduplicated into a stale one nobody is watching.
      expect(pager.triggers[1].dedupKey, first);
      expect(pager.resolves.single.dedupKey, first);
      expect(pager.triggers[2].dedupKey, isNot(first));
    });

    test('a resolve the pager refused is retried until it lands', () async {
      final _SpyPager pager = _SpyPager();
      final DVAlerting alerting = engine(
          pagers: <String, DVAlertPager>{'pagerduty': pager})
        ..addRule(depthRule(
            notify: const <DVAlertTarget>[DVAlertTarget.pager('pagerduty')]));

      await fire(alerting);
      pager.failing = true;
      signal.value = 0;
      for (int minute = 7; minute <= 15; minute++) {
        await alerting.evaluate(now: at(minute));
      }
      expect(alerting.state('mail-backlog').status, DVAlertStatus.inactive);
      expect(pager.resolves, isEmpty);

      pager.failing = false;
      await alerting.evaluate(now: at(16));
      await alerting.evaluate(now: at(17));
      expect(pager.resolves, hasLength(1));
    });

    test('PagerDuty receives the Events API v2 shape, and its routing key '
        'stays out of the error', () async {
      final List<DVHttpRequest> requests = <DVHttpRequest>[];
      int status = 202;
      final DVPagerDutyPager pager = DVPagerDutyPager(
        routingKey: 'R0UT1NGKEY',
        send: (DVHttpRequest request) async {
          requests.add(request);
          return DVHttpResponse(statusCode: status, body: '{}');
        },
      );
      final DVAlertEvent event = DVAlertEvent(
        rule: 'mail-backlog',
        dedupKey: 'mail-backlog#1',
        summary: 'x' * 2000,
        at: at(5),
      );

      await pager.trigger(event);
      await pager.resolve(event);

      expect(requests.first.url.toString(),
          'https://events.pagerduty.com/v2/enqueue');
      final Map<String, Object?> trigger =
          jsonDecode(utf8.decode(requests.first.body)) as Map<String, Object?>;
      expect(trigger['routing_key'], 'R0UT1NGKEY');
      expect(trigger['event_action'], 'trigger');
      expect(trigger['dedup_key'], 'mail-backlog#1');
      final Map<String, Object?> payload =
          trigger['payload']! as Map<String, Object?>;
      expect((payload['summary']! as String).length, lessThanOrEqualTo(1024));
      expect(payload['severity'], isNotNull);
      expect(payload['source'], isNotNull);

      final Map<String, Object?> resolve =
          jsonDecode(utf8.decode(requests.last.body)) as Map<String, Object?>;
      expect(resolve['event_action'], 'resolve');
      expect(resolve['dedup_key'], 'mail-backlog#1');

      status = 400;
      await expectLater(
        pager.trigger(event),
        throwsA(predicate((Object e) => !'$e'.contains('R0UT1NGKEY'))),
      );
    });
  });

  group('incidents', () {
    test('a firing alert opens an incident and its resolution is on the '
        'timeline, without declaring the incident over', () async {
      final DVIncidents incidents =
          DVIncidents(store: DVMemoryIncidentStore());
      final DVAlerting alerting = engine(incidents: incidents)
        ..addRule(depthRule());

      signal.value = 500;
      for (int minute = 0; minute <= 6; minute++) {
        await alerting.evaluate(now: at(minute));
      }
      final List<DVIncident> open = await incidents.open();
      expect(open, hasLength(1));
      expect(open.single.rules, contains('mail-backlog'));
      expect(alerting.state('mail-backlog').incidentId, open.single.id);

      signal.value = 0;
      for (int minute = 7; minute <= 20; minute++) {
        await alerting.evaluate(now: at(minute));
      }
      final DVIncident after = (await incidents.find(open.single.id))!;
      // Resolved is a sentence a person says in public. The alert clearing
      // moves the incident to monitoring and leaves that to them.
      expect(after.status, DVIncidentStatus.monitoring);
      expect(after.timeline.map((DVIncidentEntry e) => e.message).join('\n'),
          contains('resolved'));
    });
  });

  group('what an alert writes', () {
    test('a burn rate reads as 6.7×, not as the float that was divided', () async {
      const DVSignalRef burn = DVSignalRef.errorBudgetBurn('catalog-search');
      readers.register(burn, () => 6.703703703703697);
      final DVIncidents incidents =
          DVIncidents(store: DVMemoryIncidentStore());
      final DVAlerting alerting = engine(incidents: incidents)
        ..addRule(const DVAlertRule(
          name: 'catalog-search-burn',
          signal: burn,
          condition: DVAlertWhen.above(6),
          forDuration: Duration(minutes: 5),
          notify: <DVAlertTarget>[DVAlertTarget.user('ops-1')],
        ));
      for (int minute = 0; minute <= 6; minute++) {
        await alerting.evaluate(now: at(minute));
      }
      final DVIncident incident = (await incidents.open()).single;
      final String entry = incident.timeline.first.message;
      expect(entry, contains('is 6.7×, above 6.0×'));
      expect(entry, isNot(contains('6.70')));
      expect(inApp.sent.single.message.body, contains('is 6.7×, above 6.0×'));
    });

    test('each kind of signal is written with the precision it is read at', () {
      expect(
          const DVSignalRef.errorBudgetBurn('checkout').format(6.703703703703697),
          '6.7×');
      expect(const DVSignalRef.errorBudgetBurn('checkout').format(6), '6.0×');
      expect(const DVSignalRef.errorBudgetBurn('checkout').format(412.3), '412×');
      expect(
          const DVSignalRef.trace('createOrder', DVTraceStat.p95)
              .format(const Duration(microseconds: 812540)),
          '812.5ms');
      expect(
          const DVSignalRef.trace('createOrder', DVTraceStat.p95)
              .format(const Duration(milliseconds: 800)),
          '800ms');
      expect(const DVSignalRef.crashRate('2.0.0').format(0.012345), '1.23%');
      expect(
          const DVSignalRef.kioskFleetHealth('lobby').format(0.9), '90%');
      expect(const DVSignalRef.queueDepth('mail').format(500), '500');
      expect(const DVSignalRef.quotaBreaches('api').format(3.0), '3');
      expect(const DVSignalRef.metric('load').format(1.23456), '1.23');
      // Rounding a small, real value to 0 is a reading of nothing.
      expect(const DVSignalRef.metric('ratio').format(0.000412), '0.000412');
    });

    test('a latency threshold keeps its sub-millisecond part', () async {
      // An 812.5ms p95 above an 812.2ms limit written as "812ms, above 812ms"
      // reads as a rule that fired on nothing.
      const DVSignalRef latency = DVSignalRef.trace('createOrder', DVTraceStat.p95);
      expect(
          const DVAlertRule(
            name: 'latency',
            signal: latency,
            condition: DVAlertWhen.above(Duration(microseconds: 812200)),
            forDuration: Duration(minutes: 5),
          ).signal.format(const Duration(microseconds: 812200)),
          '812.2ms');
    });
  });

  group('noise', () {
    test('a rule that fires every day and changes nothing is reported, and '
        'one that fires ten times in one day is not', () async {
      final DVAlerting alerting = engine()
        ..addRule(depthRule(
            name: 'daily', forDuration: const Duration(minutes: 1)))
        ..addRule(depthRule(
            name: 'bad-day', forDuration: const Duration(minutes: 1)));

      final DateTime day0 = DateTime.utc(2026, 9, 1);
      for (int day = 0; day < 7; day++) {
        alerting.recordEpisode('daily',
            firedAt: day0.add(Duration(days: day, hours: 3)),
            acknowledged: true);
      }
      for (int i = 0; i < 10; i++) {
        alerting.recordEpisode('bad-day',
            firedAt: day0.add(Duration(days: 6, minutes: i * 30)),
            acknowledged: true);
      }

      final List<DVAlertFinding> findings =
          await alerting.analyze(now: day0.add(const Duration(days: 7)));
      final List<DVAlertFinding> noisy = findings
          .where((DVAlertFinding f) => f.code == 'DV-ALERT-005')
          .toList();
      expect(noisy.map((DVAlertFinding f) => f.rule), <String>['daily']);
    });

    test('a daily rule someone acted on is not noise', () async {
      final DVAlerting alerting = engine()..addRule(depthRule(name: 'daily'));
      final DateTime day0 = DateTime.utc(2026, 9, 1);
      for (int day = 0; day < 7; day++) {
        alerting.recordEpisode('daily',
            firedAt: day0.add(Duration(days: day, hours: 3)),
            acknowledged: true,
            action: day == 4 ? 'raised the worker pool' : null);
      }
      final List<DVAlertFinding> findings =
          await alerting.analyze(now: day0.add(const Duration(days: 7)));
      expect(findings, isEmpty);
    });

    test('analysis reports a rule with no target and a rule whose signal is '
        'gone', () async {
      final DVAlerting alerting = engine()
        ..addRule(depthRule(name: 'silent', notify: const <DVAlertTarget>[]))
        ..addRule(const DVAlertRule(
          name: 'renamed',
          signal: DVSignalRef.metric('jobs_waiting'),
          condition: DVAlertWhen.above(10),
          forDuration: Duration(minutes: 5),
          notify: <DVAlertTarget>[DVAlertTarget.user('ops-1')],
        ));
      final List<DVAlertFinding> findings = await alerting.analyze(now: t0);
      expect(
          findings.map((DVAlertFinding f) => '${f.code} ${f.rule}'),
          unorderedEquals(<String>[
            'DV-ALERT-005 silent',
            'DV-ALERT-006 renamed',
          ]));
    });

    test('an acknowledgement is recorded against the episode that is firing',
        () async {
      final DVAlerting alerting = engine()..addRule(depthRule());
      signal.value = 500;
      for (int minute = 0; minute <= 6; minute++) {
        await alerting.evaluate(now: at(minute));
      }
      alerting.acknowledge('mail-backlog',
          action: 'drained the queue', now: at(7));
      expect(alerting.episodes('mail-backlog').single.action,
          'drained the queue');
      expect(alerting.episodes('mail-backlog').single.acknowledgedAt, at(7));
    });
  });
}
