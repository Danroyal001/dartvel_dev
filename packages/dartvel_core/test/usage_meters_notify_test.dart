// A notifyAt threshold sends through Notifications, not only into the log.
//
// A quota approached with two warnings is a renewal conversation; one reached
// with none is a support ticket. A threshold that only writes DV-METER-003 to
// a log nobody on the customer's side reads is the second case dressed as the
// first.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

void main() {
  late DVMemoryNotificationProvider inbox;

  DVMeterDefinition meter() => DVMeterDefinition(
        'api_calls',
        unit: 'call',
        limit: const DVLimit.fixed(10),
        atLimit: DVQuota.block,
        notifyAt: const <double>[0.8, 1.0],
      );

  setUp(() {
    inbox = DVMemoryNotificationProvider();
    const DVNotificationsService().register(inbox);
  });

  tearDown(() {
    DVTenants.reset();
    const DVNotificationsService().resetRouting();
  });

  test('crossing a threshold notifies the tenant, once', () async {
    final DVMeters meters = DVMeters(
      store: DVMemoryMeterStore(),
      clock: () => DateTime.utc(2026, 9, 15, 12),
    );
    final DVMeterDefinition calls = meter();
    await const DVTenants().withTenant('acme', () async {
      await meters.record(calls, 7, idempotencyKey: 'a');
      expect(inbox.sent, isEmpty, reason: 'under every threshold');
      await meters.record(calls, 1, idempotencyKey: 'b');
      await meters.record(calls, 1, idempotencyKey: 'c');
    });

    final DVSentNotification sent = inbox.sent.single;
    expect(sent.recipient, 'acme');
    expect(sent.message.data['code'], 'DV-METER-003');
    expect(sent.message.data['meter'], 'api_calls');
    expect(sent.message.data['threshold'], '0.8');
    expect(sent.message.body, contains('8'));
    expect(sent.message.body, contains('10'));
  });

  test('the recipients can be named per tenant', () async {
    final DVMeters meters = DVMeters(
      store: DVMemoryMeterStore(),
      clock: () => DateTime.utc(2026, 9, 15, 12),
      thresholdRecipients: (String tenant) =>
          <String>['owner-of-$tenant', 'billing-of-$tenant'],
    );
    await const DVTenants().withTenant('acme', () async {
      await meters.record(meter(), 10, idempotencyKey: 'a');
    });
    // Both thresholds crossed by one recording: one message per threshold
    // per recipient.
    expect(
      inbox.sent.map((DVSentNotification s) =>
          '${s.recipient}@${s.message.data['threshold']}'),
      unorderedEquals(<String>[
        'owner-of-acme@0.8',
        'billing-of-acme@0.8',
        'owner-of-acme@1.0',
        'billing-of-acme@1.0',
      ]),
    );
  });

  test('a notification that cannot be delivered does not undo the recording',
      () async {
    final DVMeters meters = DVMeters(
      store: DVMemoryMeterStore(),
      clock: () => DateTime.utc(2026, 9, 15, 12),
      thresholdRecipients: (String tenant) =>
          throw StateError('the directory is down'),
    );
    late DVMeterOutcome outcome;
    await const DVTenants().withTenant('acme', () async {
      outcome = await meters.record(meter(), 9, idempotencyKey: 'a');
    });
    expect(outcome.recorded, isTrue);
    expect(outcome.crossed, <double>[0.8]);
    expect(await meters.usage(meter(), tenant: 'acme'), 9);
  });

  test('an onThreshold handler replaces the default send', () async {
    final List<double> handled = <double>[];
    final DVMeters meters = DVMeters(
      store: DVMemoryMeterStore(),
      clock: () => DateTime.utc(2026, 9, 15, 12),
      onThreshold: (DVMeterThreshold t) => handled.add(t.fraction),
    );
    await const DVTenants().withTenant('acme', () async {
      await meters.record(meter(), 9, idempotencyKey: 'a');
    });
    expect(handled, <double>[0.8]);
    expect(inbox.sent, isEmpty);
  });
}
