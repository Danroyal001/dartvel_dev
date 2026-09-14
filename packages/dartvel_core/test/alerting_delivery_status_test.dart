// What a screen needs to read off a rule and an incident without working it
// out again: whether a firing alert is on its way to resolving, which targets
// it reached, which it missed and why, which pager resolves are still queued,
// and who wrote each line of an incident's timeline.
//
// The failure each group guards is a quiet one. A delivery that failed for one
// target while another succeeded reads as "delivered" through the single
// boolean the state had; a resolve queued behind a refusing pager is invisible
// until someone notices the pager incident is still open; and a timeline with
// no author cannot say which person declared an outage over.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

final DateTime t0 = DateTime.utc(2026, 9, 1, 3);

DateTime at(int minutes) => t0.add(Duration(minutes: minutes));

class _Provider implements DVNotificationProvider {
  @override
  DVNotificationProviderKind get kind => DVNotificationProviderKind.local;

  final Set<String> refusing = <String>{};

  @override
  Future<void> send(String recipient, DVNotificationMessage message) async {
    if (refusing.contains(recipient)) throw StateError('inbox full');
  }
}

class _Pager implements DVAlertPager {
  bool failing = false;

  @override
  Future<void> trigger(DVAlertEvent event) async {
    if (failing) throw const DVAlertDeliveryException('HTTP 503');
  }

  @override
  Future<void> resolve(DVAlertEvent event) async {
    if (failing) throw const DVAlertDeliveryException('HTTP 503');
  }
}

const DVSignalRef depth = DVSignalRef.queueDepth('mail');

void main() {
  const DVNotificationsService notifications = DVNotificationsService();
  late _Provider provider;
  late _Pager pager;
  num? value;
  late DVAlerting alerting;

  setUp(() {
    provider = _Provider();
    notifications
      ..resetRouting()
      ..register(provider);
    pager = _Pager();
    value = null;
    alerting =
        DVAlerting(
          readers: DVSignalReaders()..register(depth, () => value),
          notifications: notifications,
          pagers: <String, DVAlertPager>{'pagerduty': pager},
          teams: (String team) async =>
              team == 'payments' ? <String>['ana', 'bo'] : <String>[],
          onDiagnostic: (String code, String message) {},
        )..addRule(
          const DVAlertRule(
            name: 'mail-backlog',
            signal: depth,
            condition: DVAlertWhen.above(100),
            forDuration: Duration(minutes: 5),
            notify: <DVAlertTarget>[
              DVAlertTarget.user('ops-1'),
              DVAlertTarget.team('payments'),
              DVAlertTarget.team('nobody'),
              DVAlertTarget.pager('pagerduty'),
            ],
          ),
        );
  });

  Future<void> run(int from, int to) async {
    for (int minute = from; minute <= to; minute++) {
      await alerting.evaluate(now: at(minute));
    }
  }

  group('delivery status', () {
    test(
      'names the targets reached and the ones missed, with the reason',
      () async {
        provider.refusing.add('bo');
        pager.failing = true;
        value = 500;
        await run(0, 6);

        final DVAlertState state = alerting.state('mail-backlog');
        expect(state.status, DVAlertStatus.firing);
        // One boolean said this was delivered, and it was -- to two of five.
        expect(state.delivered, isTrue);
        expect(
          state.deliveredTo,
          unorderedEquals(<String>['user:ops-1', 'user:ana']),
        );
        expect(
          state.missed.keys,
          unorderedEquals(<String>[
            'user:bo',
            'team:nobody',
            'pager:pagerduty',
          ]),
        );
        // The notification service's own report of the attempt, per channel.
        expect(state.missed['user:bo'], contains('reached nobody'));
        expect(state.missed['team:nobody'], contains('no members'));
        expect(state.missed['pager:pagerduty'], contains('HTTP 503'));
        expect(state.lastNotifiedAt, at(5));
      },
    );

    test('a retry that lands takes the target off the missed list', () async {
      pager.failing = true;
      value = 500;
      await run(0, 6);
      expect(
        alerting.state('mail-backlog').missed.keys,
        contains('pager:pagerduty'),
      );

      pager.failing = false;
      await run(7, 7);
      final DVAlertState state = alerting.state('mail-backlog');
      expect(state.missed.keys, isNot(contains('pager:pagerduty')));
      expect(state.deliveredTo, contains('pager:pagerduty'));
    });

    test('the state returned cannot be used to change the engine', () async {
      value = 500;
      await run(0, 6);
      final DVAlertState state = alerting.state('mail-backlog');
      expect(
        () => state.deliveredTo.add('user:intruder'),
        throwsUnsupportedError,
      );
      expect(() => state.missed['user:x'] = 'y', throwsUnsupportedError);
    });
  });

  group('resolving', () {
    test('a firing alert whose signal cleared says since when, and stops '
        'saying it if the breach comes back', () async {
      value = 500;
      await run(0, 6);
      expect(alerting.state('mail-backlog').resolvingSince, isNull);

      value = 0;
      await run(7, 8);
      final DVAlertState clearing = alerting.state('mail-backlog');
      expect(clearing.status, DVAlertStatus.firing);
      expect(clearing.resolvingSince, at(7));

      value = 500;
      await run(9, 9);
      expect(alerting.state('mail-backlog').resolvingSince, isNull);
    });

    test('a resolve the pager refused is listed until it lands', () async {
      value = 500;
      await run(0, 6);
      pager.failing = true;
      value = 0;
      await run(7, 15);
      expect(alerting.state('mail-backlog').status, DVAlertStatus.inactive);
      expect(alerting.pendingResolves('mail-backlog'), <String>['pagerduty']);
      expect(alerting.pendingResolves('other'), isEmpty);

      pager.failing = false;
      await run(16, 16);
      expect(alerting.pendingResolves('mail-backlog'), isEmpty);
    });
  });

  group('incident authorship', () {
    test('an entry records who wrote it, through storage, and the public '
        'snapshot does not carry it', () async {
      final DVIncidents incidents = DVIncidents(
        store: DVMemoryIncidentStore(),
        newId: () => 'inc-1',
      );
      await incidents.openIncident(
        title: 'Checkout errors',
        message: 'opened',
        now: at(0),
      );
      await incidents.update(
        'inc-1',
        message: 'rolled back 2.4.1',
        status: DVIncidentStatus.monitoring,
        public: true,
        actor: 'dana',
        now: at(10),
      );
      await incidents.resolve(
        'inc-1',
        message: 'Checkout is working again.',
        actor: 'dana',
        now: at(40),
      );

      final DVIncident stored = (await incidents.find('inc-1'))!;
      expect(stored.timeline.first.actor, isNull);
      expect(stored.timeline[1].actor, 'dana');
      expect(stored.timeline.last.actor, 'dana');
      expect(stored.timeline.last.status, DVIncidentStatus.resolved);

      final DVStatusSnapshot snapshot = DVStatusSnapshot.build(
        health: const DVHealthReport(
          status: DVHealthStatus.up,
          checks: <String, DVHealthResult>{},
          uptime: Duration.zero,
        ),
        incidents: <DVIncident>[stored],
        now: at(41),
      );
      expect('${snapshot.toJson()}', isNot(contains('dana')));
    });
  });
}
