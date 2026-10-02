import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

/// Subscription lifecycle on Stripe and Paddle, checked by the exact requests
/// each provider sends, against recorded response shapes. No live keys.
const BillingPlan pro = BillingPlan(
    id: 'pro', displayName: 'Pro', priceMinorUnits: 4000, currency: 'USD');
const BillingPlan team = BillingPlan(
    id: 'team', displayName: 'Team', priceMinorUnits: 9000, currency: 'USD');

typedef SentRequest = ({String method, Uri url, String? body});

void main() {
  group('Stripe', () {
    late List<SentRequest> sent;

    DVStripeBillingProvider stripe(List<Map<String, Object?>> subscriptions) {
      sent = <SentRequest>[];
      return DVStripeBillingProvider(
        secretKey: 'sk_test_secret',
        webhookSecret: 'whsec_test',
        prices: <String, String>{'pro': 'price_pro', 'team': 'price_team'},
        entitlements: <String, Set<Entitlement>>{},
        successUrl: Uri.parse('https://app.example/billing'),
        cancelUrl: Uri.parse('https://app.example/billing/cancel'),
        fetch: (String method, Uri url, Map<String, String> headers, String? body) async {
          sent.add((method: method, url: url, body: body));
          if (url.path == '/v1/subscriptions' && method == 'GET') {
            return (200, jsonEncode(<String, Object?>{'data': subscriptions}));
          }
          if (url.path == '/v1/prices/price_team') {
            return (200, '{"id":"price_team","unit_amount":9000,"currency":"usd"}');
          }
          if (url.path == '/v1/billing_portal/sessions') {
            return (200, '{"url":"https://billing.stripe.com/p/session_1"}');
          }
          return (200, '{"id":"sub_live"}');
        },
      );
    }

    final Map<String, Object?> canceledOld = <String, Object?>{'id': 'sub_old', 'status': 'canceled'};
    final Map<String, Object?> active = <String, Object?>{
      'id': 'sub_live',
      'status': 'active',
      'cancel_at_period_end': false,
      'current_period_end': 1793750400,
      'items': <String, Object?>{
        'data': <Object?>[<String, Object?>{'id': 'si_1', 'price': <String, Object?>{'id': 'price_pro'}}],
      },
    };

    test('acts on the current subscription, not the newest canceled one', () async {
      final DVStripeBillingProvider provider = stripe(<Map<String, Object?>>[canceledOld, active]);
      await provider.cancelSubscription(customer: 'cus_1', atPeriodEnd: true);
      expect(sent.last.method, 'POST');
      expect(sent.last.url.path, '/v1/subscriptions/sub_live');
      expect(sent.last.body, 'cancel_at_period_end=true');
    });

    test('cancelling now deletes the subscription', () async {
      final DVStripeBillingProvider provider = stripe(<Map<String, Object?>>[active]);
      await provider.cancelSubscription(customer: 'cus_1');
      expect(sent.last.method, 'DELETE');
      expect(sent.last.url.path, '/v1/subscriptions/sub_live');
    });

    test('pause uses pause_collection, and resume clears it and any pending cancel', () async {
      final DVStripeBillingProvider provider = stripe(<Map<String, Object?>>[active]);
      await provider.pauseSubscription(customer: 'cus_1');
      expect(Uri.splitQueryString(sent.last.body!), <String, String>{'pause_collection[behavior]': 'void'});
      await provider.resumeSubscription(customer: 'cus_1');
      expect(Uri.splitQueryString(sent.last.body!),
          <String, String>{'cancel_at_period_end': 'false', 'pause_collection': ''});
    });

    test('a plan change replaces the existing item, prorated by default', () async {
      final DVStripeBillingProvider provider = stripe(<Map<String, Object?>>[active]);
      await provider.changeSubscriptionPlan(customer: 'cus_1', plan: team);
      expect(Uri.splitQueryString(sent.last.body!), <String, String>{
        'items[0][id]': 'si_1',
        'items[0][price]': 'price_team',
        'proration_behavior': 'create_prorations',
      });
      await provider.changeSubscriptionPlan(customer: 'cus_1', plan: team, prorate: false);
      expect(Uri.splitQueryString(sent.last.body!)['proration_behavior'], 'none');
    });

    test('status reads the current subscription, and a paused one says paused', () async {
      DVSubscriptionStatus status = await stripe(<Map<String, Object?>>[canceledOld, active])
          .subscriptionStatus(customer: 'cus_1');
      expect(status.status, 'active');
      expect(status.currentPeriodEnd, DateTime.fromMillisecondsSinceEpoch(1793750400 * 1000, isUtc: true));
      status = await stripe(<Map<String, Object?>>[
        <String, Object?>{...active, 'pause_collection': <String, Object?>{'behavior': 'void'}},
      ]).subscriptionStatus(customer: 'cus_1');
      expect(status.status, 'paused');
      status = await stripe(const <Map<String, Object?>>[]).subscriptionStatus(customer: 'cus_1');
      expect(status.status, 'none');
    });

    test('the portal link comes back to the app', () async {
      final String url = await stripe(<Map<String, Object?>>[active]).customerPortalUrl(customer: 'cus 1');
      expect(url, 'https://billing.stripe.com/p/session_1');
      expect(Uri.splitQueryString(sent.last.body!),
          <String, String>{'customer': 'cus 1', 'return_url': 'https://app.example/billing'});
    });

    test('no subscription is a clear error, not a guess', () async {
      expect(() => stripe(const <Map<String, Object?>>[]).pauseSubscription(customer: 'cus_1'),
          throwsA(isA<DVBillingError>()));
    });
  });

  group('Paddle', () {
    late List<SentRequest> sent;

    DVPaddleBillingProvider paddle(List<Map<String, Object?>> subscriptions) {
      sent = <SentRequest>[];
      return DVPaddleBillingProvider(
        apiKey: 'pdl_sdbx_apikey',
        webhookSecret: 'pdl_ntf_secret',
        prices: <String, String>{'pro': 'pri_pro', 'team': 'pri_team'},
        entitlements: <String, Set<Entitlement>>{},
        fetch: (String method, Uri url, Map<String, String> headers, String? body) async {
          sent.add((method: method, url: url, body: body));
          if (url.path == '/subscriptions' && method == 'GET') {
            return (200, jsonEncode(<String, Object?>{'data': subscriptions}));
          }
          if (url.path.endsWith('/portal-sessions')) {
            return (201, jsonEncode(<String, Object?>{
              'data': <String, Object?>{
                'urls': <String, Object?>{'general': <String, Object?>{'overview': 'https://customer-portal.paddle.com/cpl_1'}},
              },
            }));
          }
          return (200, '{"data":{}}');
        },
      );
    }

    final Map<String, Object?> active = <String, Object?>{
      'id': 'sub_live',
      'status': 'active',
      'scheduled_change': null,
      'current_billing_period': <String, Object?>{'ends_at': '2026-11-02T00:00:00Z'},
    };

    Map<String, Object?> jsonBody() => jsonDecode(sent.last.body!) as Map<String, Object?>;

    test('pause, resume and cancel are Paddle actions, not status writes', () async {
      DVPaddleBillingProvider provider = paddle(<Map<String, Object?>>[active]);
      await provider.pauseSubscription(customer: 'ctm_1');
      expect((sent.last.method, sent.last.url.path), ('POST', '/subscriptions/sub_live/pause'));
      expect(jsonBody(), <String, Object?>{'effective_from': 'next_billing_period'});

      await provider.cancelSubscription(customer: 'ctm_1', atPeriodEnd: true);
      expect((sent.last.method, sent.last.url.path), ('POST', '/subscriptions/sub_live/cancel'));
      expect(jsonBody(), <String, Object?>{'effective_from': 'next_billing_period'});

      provider = paddle(<Map<String, Object?>>[<String, Object?>{...active, 'status': 'paused'}]);
      await provider.resumeSubscription(customer: 'ctm_1');
      expect((sent.last.method, sent.last.url.path), ('POST', '/subscriptions/sub_live/resume'));
      expect(jsonBody(), <String, Object?>{'effective_from': 'immediately'});
    });

    test('resuming an active subscription removes a scheduled cancellation', () async {
      await paddle(<Map<String, Object?>>[active]).resumeSubscription(customer: 'ctm_1');
      expect((sent.last.method, sent.last.url.path), ('PATCH', '/subscriptions/sub_live'));
      expect(jsonBody(), <String, Object?>{'scheduled_change': null});
    });

    test('a plan change patches the items with a real proration mode', () async {
      final DVPaddleBillingProvider provider = paddle(<Map<String, Object?>>[active]);
      await provider.changeSubscriptionPlan(customer: 'ctm_1', plan: team);
      expect((sent.last.method, sent.last.url.path), ('PATCH', '/subscriptions/sub_live'));
      expect(jsonBody()['proration_billing_mode'], 'prorated_immediately');
      expect(jsonBody()['items'], <Object?>[<String, Object?>{'price_id': 'pri_team', 'quantity': 1}]);
    });

    test('status reads a scheduled cancellation and the period end', () async {
      final DVSubscriptionStatus status = await paddle(<Map<String, Object?>>[
        <String, Object?>{...active, 'scheduled_change': <String, Object?>{'action': 'cancel'}},
      ]).subscriptionStatus(customer: 'ctm_1');
      expect(status.status, 'active');
      expect(status.cancelAtPeriodEnd, isTrue);
      expect(status.currentPeriodEnd, DateTime.utc(2026, 11, 2));
    });

    test('the portal link is the general overview from a portal session', () async {
      final String url = await paddle(<Map<String, Object?>>[active]).customerPortalUrl(customer: 'ctm_1');
      expect(url, 'https://customer-portal.paddle.com/cpl_1');
      expect((sent.last.method, sent.last.url.path), ('POST', '/customers/ctm_1/portal-sessions'));
    });
  });
}
