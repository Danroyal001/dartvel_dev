// The status page: what it publishes, and what it does when the application
// it reports on is the thing that is down.
//
// A status page hosted inside the application goes down with it, and the
// first thing a customer sees during an outage is a blank page where the
// explanation should be. So the page reads a snapshot through the API, keeps
// the last one it got, and serves that -- marked stale, with the time it was
// true -- when the application cannot be reached.
//
// The silent failures are all plausible pages: a stale snapshot served as if it
// were current, stamped with the time it was served rather than the time it
// was true; an error body from a failing gateway cached over the last good
// snapshot; a request that hangs rather than fails, so the page waits with the
// application; and a public page carrying a health check's internal detail or
// an alert's metric names because the timeline was published whole.
import 'dart:async';
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

final DateTime t0 = DateTime.utc(2026, 9, 1, 12);

class _Diagnostics {
  final List<String> codes = <String>[];
  void call(String code, String message) => codes.add(code);
  int count(String code) => codes.where((String c) => c == code).length;
}

class _SpyProvider implements DVNotificationProvider {
  @override
  DVNotificationProviderKind get kind => DVNotificationProviderKind.local;

  final Set<String> failFor = <String>{};
  final List<DVSentNotification> sent = <DVSentNotification>[];

  @override
  Future<void> send(String recipient, DVNotificationMessage message) async {
    if (failFor.contains(recipient)) throw StateError('unreachable');
    sent.add(DVSentNotification(recipient: recipient, message: message));
  }
}

DVHealthReport health(Map<String, DVHealthResult> checks) {
  DVHealthStatus worst = DVHealthStatus.up;
  for (final DVHealthResult r in checks.values) {
    if (r.status.index > worst.index) worst = r.status;
  }
  return DVHealthReport(
      status: worst, checks: checks, uptime: const Duration(hours: 1));
}

DVIncident incident({
  String id = 'inc-1',
  DVIncidentStatus status = DVIncidentStatus.investigating,
  DateTime? resolvedAt,
  List<DVIncidentEntry>? timeline,
}) =>
    DVIncident(
      id: id,
      title: 'Checkout is failing',
      openedAt: t0.subtract(const Duration(minutes: 30)),
      status: status,
      resolvedAt: resolvedAt,
      components: <String>['checkout'],
      timeline: timeline ??
          <DVIncidentEntry>[
            DVIncidentEntry(
              at: t0.subtract(const Duration(minutes: 30)),
              message: 'alert checkout-latency fired: p95 of createOrder is '
                  '950ms on db-primary-3',
              source: 'alert',
            ),
            DVIncidentEntry(
              at: t0.subtract(const Duration(minutes: 20)),
              message: 'We are investigating failed payments.',
              status: DVIncidentStatus.investigating,
              public: true,
            ),
          ],
    );

void main() {
  group('the snapshot', () {
    test('components come from health checks, without their detail', () {
      final DVStatusSnapshot snapshot = DVStatusSnapshot.build(
        health: health(<String, DVHealthResult>{
          'database': DVHealthResult.down(
              'connection refused: postgres://app:hunter2@10.0.0.3/app'),
          'cache': DVHealthResult.up(),
        }),
        incidents: const <DVIncident>[],
        now: t0,
      );
      expect(snapshot.components, <String, DVComponentStatus>{
        'database': DVComponentStatus.outage,
        'cache': DVComponentStatus.operational,
      });
      expect(snapshot.overall, DVComponentStatus.outage);
      final String published = jsonEncode(snapshot.toJson());
      expect(published, isNot(contains('hunter2')));
      expect(published, isNot(contains('10.0.0.3')));
    });

    test('an open incident is published with its public updates only', () {
      final DVStatusSnapshot snapshot = DVStatusSnapshot.build(
        health: health(<String, DVHealthResult>{'api': DVHealthResult.up()}),
        incidents: <DVIncident>[incident()],
        now: t0,
      );
      final String published = jsonEncode(snapshot.toJson());
      expect(published, contains('We are investigating failed payments.'));
      expect(published, isNot(contains('db-primary-3')));
      expect(published, isNot(contains('createOrder')));
      expect(snapshot.incidents.single.updates, hasLength(1));
    });

    test('an incident nobody has written a public update for is not on the '
        'page', () {
      // An alert opens its incident internally, titled after the rule. Until
      // a person says something in public it is not the public's.
      final DVStatusSnapshot snapshot = DVStatusSnapshot.build(
        health: health(<String, DVHealthResult>{'api': DVHealthResult.up()}),
        incidents: <DVIncident>[
          DVIncident(
            id: 'internal',
            title: 'Alert mail-backlog',
            openedAt: t0,
            timeline: <DVIncidentEntry>[
              DVIncidentEntry(
                  at: t0, message: 'queueDepth mail is 500', source: 'alert'),
            ],
          ),
        ],
        now: t0,
      );
      expect(snapshot.incidents, isEmpty);
      expect(jsonEncode(snapshot.toJson()), isNot(contains('mail-backlog')));
    });

    test('an open incident is not reported as all systems operational', () {
      final DVStatusSnapshot snapshot = DVStatusSnapshot.build(
        health: health(<String, DVHealthResult>{'api': DVHealthResult.up()}),
        incidents: <DVIncident>[incident()],
        now: t0,
      );
      expect(snapshot.overall, DVComponentStatus.degraded);
    });

    test('a resolved incident stays up for a while, then drops off', () {
      final DVIncident recent = incident(
          id: 'recent',
          status: DVIncidentStatus.resolved,
          resolvedAt: t0.subtract(const Duration(days: 2)));
      final DVIncident old = incident(
          id: 'old',
          status: DVIncidentStatus.resolved,
          resolvedAt: t0.subtract(const Duration(days: 30)));
      final DVStatusSnapshot snapshot = DVStatusSnapshot.build(
        health: health(<String, DVHealthResult>{'api': DVHealthResult.up()}),
        incidents: <DVIncident>[recent, old],
        now: t0,
      );
      expect(snapshot.incidents.map((DVPublicIncident i) => i.id),
          <String>['recent']);
      expect(snapshot.overall, DVComponentStatus.operational);
    });

    test('survives the trip through JSON', () {
      final DVStatusSnapshot snapshot = DVStatusSnapshot.build(
        health: health(<String, DVHealthResult>{
          'api': DVHealthResult.degraded('slow'),
        }),
        incidents: <DVIncident>[incident()],
        now: t0,
      );
      final DVStatusSnapshot back = DVStatusSnapshot.fromJson(
          jsonDecode(jsonEncode(snapshot.toJson())) as Map<String, Object?>);
      expect(back.generatedAt, t0);
      expect(back.components, snapshot.components);
      expect(back.incidents.single.updates.single.message,
          'We are investigating failed payments.');
    });
  });

  group('the page, when the application is unreachable', () {
    late DVStatusSnapshot good;
    late DVMemoryStatusSnapshotCache cache;
    late _Diagnostics diagnostics;
    late DateTime now;
    late FutureOr<DVHttpResponse> Function() respond;

    setUp(() {
      good = DVStatusSnapshot.build(
        health: health(<String, DVHealthResult>{'api': DVHealthResult.up()}),
        incidents: const <DVIncident>[],
        now: t0,
      );
      cache = DVMemoryStatusSnapshotCache();
      diagnostics = _Diagnostics();
      now = t0;
      respond = () => DVHttpResponse(
          statusCode: 200, body: jsonEncode(good.toJson()));
    });

    DVStatusPageClient client({Duration timeout = const Duration(seconds: 2)}) =>
        DVStatusPageClient(
          fetch: () async => respond(),
          cache: cache,
          timeout: timeout,
          clock: () => now,
          onDiagnostic: diagnostics.call,
        );

    test('a reachable application is served fresh', () async {
      final DVStatusView view = await client().load();
      expect(view.stale, isFalse);
      expect(view.snapshot!.overall, DVComponentStatus.operational);
      expect(diagnostics.codes, isEmpty);
    });

    test('an unreachable one serves the last snapshot, marked stale, with the '
        'time it was true', () async {
      final DVStatusPageClient page = client();
      await page.load();

      now = t0.add(const Duration(minutes: 40));
      respond = () => throw const SocketLikeException();
      final DVStatusView view = await page.load();

      expect(view.stale, isTrue);
      expect(view.snapshot, isNotNull);
      // Stamped with when it was true. Stamped with now, a forty-minute-old
      // "all operational" reads as current during the outage.
      expect(view.asOf, t0);
      expect(view.asOf, isNot(now));
      expect(diagnostics.count('DV-ALERT-004'), 1);
    });

    test('an error from a gateway is not cached over the last good snapshot',
        () async {
      final DVStatusPageClient page = client();
      await page.load();

      respond = () => DVHttpResponse(
          statusCode: 503,
          body: jsonEncode(<String, Object?>{
            'generatedAt': t0.add(const Duration(hours: 1)).toIso8601String(),
            'components': <String, Object?>{},
            'incidents': <Object?>[],
          }));
      final DVStatusView view = await page.load();
      expect(view.stale, isTrue);
      expect(view.asOf, t0);

      respond = () => const DVHttpResponse(statusCode: 200, body: '<html>');
      final DVStatusView garbled = await page.load();
      expect(garbled.stale, isTrue);
      expect(garbled.asOf, t0);
    });

    test('a request that hangs is given up on, not waited for', () async {
      final DVStatusPageClient page =
          client(timeout: const Duration(milliseconds: 50));
      await page.load();

      respond = () => Completer<DVHttpResponse>().future;
      final Stopwatch watch = Stopwatch()..start();
      final DVStatusView view = await page.load();
      expect(view.stale, isTrue);
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('a page that restarts during the outage still has the last snapshot',
        () async {
      await client().load();
      respond = () => throw const SocketLikeException();
      final DVStatusView view = await client().load();
      expect(view.stale, isTrue);
      expect(view.asOf, t0);
    });

    test('with nothing ever fetched it says it does not know, rather than '
        'failing', () async {
      respond = () => throw const SocketLikeException();
      final DVStatusView view = await client().load();
      expect(view.snapshot, isNull);
      expect(view.isUnknown, isTrue);
    });

    test('staleness is reported once per outage, and again for the next',
        () async {
      final DVStatusPageClient page = client();
      await page.load();
      respond = () => throw const SocketLikeException();
      await page.load();
      await page.load();
      await page.load();
      expect(diagnostics.count('DV-ALERT-004'), 1);

      respond = () =>
          DVHttpResponse(statusCode: 200, body: jsonEncode(good.toJson()));
      expect((await page.load()).stale, isFalse);
      respond = () => throw const SocketLikeException();
      await page.load();
      expect(diagnostics.count('DV-ALERT-004'), 2);
    });
  });

  group('incidents', () {
    test('a crash spike joins the newest open incident instead of opening a '
        'second one', () async {
      final DVIncidents incidents =
          DVIncidents(store: DVMemoryIncidentStore());
      await incidents.openIncident(
          title: 'Older', message: 'first', now: t0);
      final DVIncident newer = await incidents.openIncident(
          title: 'Newer', message: 'second', now: t0.add(const Duration(minutes: 5)));

      final DVIncident linked = await incidents.linkCrashSpike(
        fingerprint: 'fp-checkout',
        release: '2.0.0',
        message: 'crash-free sessions fell to 91%',
        now: t0.add(const Duration(minutes: 6)),
      );
      expect(linked.id, newer.id);
      expect((await incidents.find(newer.id))!.crashFingerprints,
          <String>{'fp-checkout'});
      expect(await incidents.open(), hasLength(2));
    });

    test('with nothing open, a crash spike opens its own', () async {
      final DVIncidents incidents =
          DVIncidents(store: DVMemoryIncidentStore());
      final DVIncident opened = await incidents.linkCrashSpike(
        fingerprint: 'fp-profile',
        release: '2.0.0',
        message: 'crash-free sessions fell to 91%',
        now: t0,
      );
      expect(opened.timeline.single.source, 'crash');
      expect((await incidents.find(opened.id))!.crashFingerprints,
          <String>{'fp-profile'});
    });

    test('a person retitles and resolves it, in public', () async {
      final DVIncidents incidents =
          DVIncidents(store: DVMemoryIncidentStore());
      final DVIncident opened = await incidents.openIncident(
          title: 'Alert checkout-latency', message: 'fired', now: t0);
      await incidents.update(opened.id,
          title: 'Slow checkout',
          message: 'We are looking into slow payments.',
          public: true,
          now: t0.add(const Duration(minutes: 1)));
      final DVIncident resolved = await incidents.resolve(opened.id,
          message: 'Payments are back to normal.',
          now: t0.add(const Duration(minutes: 30)));

      expect(resolved.title, 'Slow checkout');
      expect(resolved.status, DVIncidentStatus.resolved);
      expect(resolved.resolvedAt, t0.add(const Duration(minutes: 30)));
      expect(resolved.timeline.last.public, isTrue);
      expect(await incidents.open(), isEmpty);
    });

    test('a changed copy is not the stored incident until it is saved',
        () async {
      final DVMemoryIncidentStore store = DVMemoryIncidentStore();
      final DVIncidents incidents = DVIncidents(store: store);
      final DVIncident opened =
          await incidents.openIncident(title: 'x', message: 'y', now: t0);
      opened.status = DVIncidentStatus.resolved;
      expect((await store.find(opened.id))!.status,
          DVIncidentStatus.investigating);
    });
  });

  group('subscribers', () {
    const DVNotificationsService notifications = DVNotificationsService();
    late _SpyProvider provider;

    setUp(() {
      provider = _SpyProvider();
      notifications
        ..resetRouting()
        ..register(provider);
    });

    test('hear the latest public update, and one unreachable subscriber does '
        'not stop the rest', () async {
      final DVStatusSubscribers subscribers =
          DVStatusSubscribers(notifications: notifications)
            ..subscribe('ana')
            ..subscribe('bo')
            ..subscribe('cy');
      provider.failFor.add('bo');

      final int delivered = await subscribers.announce(incident());
      expect(delivered, 2);
      expect(provider.sent.map((DVSentNotification n) => n.recipient),
          <String>['ana', 'cy']);
      expect(provider.sent.first.message.body,
          'We are investigating failed payments.');
    });

    test('hear nothing from an incident with no public update', () async {
      final DVStatusSubscribers subscribers =
          DVStatusSubscribers(notifications: notifications)..subscribe('ana');
      final int delivered = await subscribers.announce(incident(
        timeline: <DVIncidentEntry>[
          DVIncidentEntry(
              at: t0, message: 'db-primary-3 is out of disk', source: 'alert'),
        ],
      ));
      expect(delivered, 0);
      expect(provider.sent, isEmpty);
    });
  });
}

class SocketLikeException implements Exception {
  const SocketLikeException();
  @override
  String toString() => 'connection refused';
}
