// Usage-based billing: what the application counts, and what reaches the
// provider.
//
// "usage-based billing" and "usage meters are typed config" are both in the
// Billing section, and nothing implemented either. A meter is where the two
// halves of the money can drift apart most quietly: an application counts
// API calls all month, the provider is told about none of them, and the
// invoice is simply lower than it should be. Nobody files that bug.
//
// The other half is the retry. Dartvel's own queues redeliver, so a usage
// record will be sent twice sooner or later, and a meter event with no
// identifier is counted twice at Stripe. That is why the identifier is a
// required argument rather than an optional one -- there is no sensible
// default for it, and a generated random one is exactly the value that
// makes a retry double the bill.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const DVUsageMeter apiCalls = DVUsageMeter('api_calls');
const DVUsageMeter unconfigured = DVUsageMeter('storage_bytes');

void main() {
  group('local', () {
    late DVLocalBillingProvider billing;
    setUp(() => billing = DVLocalBillingProvider());

    test('recorded usage accumulates per customer and meter', () async {
      await billing.recordUsage(
          customer: 'user_1', meter: apiCalls, quantity: 3, idempotencyKey: 'a');
      await billing.recordUsage(
          customer: 'user_1', meter: apiCalls, quantity: 4, idempotencyKey: 'b');
      await billing.recordUsage(
          customer: 'user_2', meter: apiCalls, quantity: 9, idempotencyKey: 'c');

      expect(billing.usage('user_1', apiCalls), 7);
      expect(billing.usage('user_2', apiCalls), 9);
      // A meter nothing was recorded against is zero, not absent.
      expect(billing.usage('user_1', unconfigured), 0);
    });

    test('the same identifier twice counts once', () async {
      // A queue that redelivers is the ordinary case, not the rare one.
      await billing.recordUsage(
          customer: 'u', meter: apiCalls, quantity: 5, idempotencyKey: 'job_1');
      await billing.recordUsage(
          customer: 'u', meter: apiCalls, quantity: 5, idempotencyKey: 'job_1');

      expect(billing.usage('u', apiCalls), 5);
    });

    test('a quantity that is not positive is refused', () async {
      // Recording a negative is how a bill gets reduced by something that
      // reads as a measurement.
      await expectLater(
        billing.recordUsage(
            customer: 'u', meter: apiCalls, quantity: -5, idempotencyKey: 'x'),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        billing.recordUsage(
            customer: 'u', meter: apiCalls, quantity: 0, idempotencyKey: 'y'),
        throwsA(isA<ArgumentError>()),
      );
      expect(billing.usage('u', apiCalls), 0);
    });
  });

  group('Stripe', () {
    late List<(String, Uri, String?)> calls;

    DVStripeBillingProvider provider({int status = 200}) {
      calls = <(String, Uri, String?)>[];
      return DVStripeBillingProvider(
        secretKey: 'sk_test_secret',
        webhookSecret: 'whsec_test',
        prices: const <String, String>{},
        entitlements: const <String, Set<Entitlement>>{},
        meters: const <String, String>{'api_calls': 'api_requests'},
        successUrl: Uri.parse('https://app.example/ok'),
        cancelUrl: Uri.parse('https://app.example/no'),
        fetch: (String method, Uri url, Map<String, String> headers,
            String? body) async {
          calls.add((method, url, body));
          return (status, '{"identifier":"job_1"}');
        },
        clock: () => DateTime.utc(2026, 9, 3, 12),
      );
    }

    test('a record reaches the meter event endpoint with everything Stripe '
        'needs to bill it', () async {
      final DVStripeBillingProvider p = provider();

      await p.recordUsage(
        customer: 'cus_123',
        meter: apiCalls,
        quantity: 42,
        idempotencyKey: 'job_1',
        at: DateTime.utc(2026, 9, 3, 11, 30),
      );

      final (String method, Uri url, String? body) = calls.single;
      expect(method, 'POST');
      expect(url.path, '/v1/billing/meter_events');
      // The meter's provider name, not Dartvel's name for it.
      expect(body, contains('event_name=api_requests'));
      expect(body, contains('payload%5Bstripe_customer_id%5D=cus_123'));
      expect(body, contains('payload%5Bvalue%5D=42'));
      // Stripe counts one event per identifier. Without it the redelivery
      // that queues guarantee is billed twice.
      expect(body, contains('identifier=job_1'));
      expect(body, contains('timestamp=${DateTime.utc(2026, 9, 3, 11, 30).millisecondsSinceEpoch ~/ 1000}'));
    });

    test('a meter with no Stripe event name configured is refused, and sends '
        'nothing', () async {
      // The silent version of this is the whole reason the check exists: a
      // meter the provider has never heard of, counted all month, billed
      // never.
      final DVStripeBillingProvider p = provider();

      await expectLater(
        p.recordUsage(
            customer: 'cus_123',
            meter: unconfigured,
            quantity: 1,
            idempotencyKey: 'k'),
        throwsA(isA<DVBillingError>().having((DVBillingError e) => e.message,
            'message', contains('storage_bytes'))),
      );
      expect(calls, isEmpty);
    });

    test('a rejected record is an error rather than a shrug', () async {
      final DVStripeBillingProvider p = provider(status: 400);

      await expectLater(
        p.recordUsage(
            customer: 'cus_123',
            meter: apiCalls,
            quantity: 1,
            idempotencyKey: 'k'),
        throwsA(isA<DVBillingError>()),
      );
    });
  });

  group('Paddle', () {
    test('refuses a usage record instead of dropping it', () async {
      // Paddle bills metered items through its own subscription flow rather
      // than through anything shaped like a meter event, and Dartvel does
      // not implement it. Accepting the call and doing nothing would be the
      // failure this whole file is about, so it says so out loud.
      final DVPaddleBillingProvider p = DVPaddleBillingProvider(
        apiKey: 'pdl_live_key',
        webhookSecret: 's',
        prices: const <String, String>{},
        entitlements: const <String, Set<Entitlement>>{},
        fetch: (String method, Uri url, Map<String, String> h,
                String? b) async =>
            fail('nothing should have been sent'),
      );

      await expectLater(
        p.recordUsage(
            customer: 'ctm_1',
            meter: apiCalls,
            quantity: 1,
            idempotencyKey: 'k'),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
