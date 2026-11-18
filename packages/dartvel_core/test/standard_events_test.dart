// The events a shop or a lead form tracks, one call each.
//
// Each is tracked once through DV.Analytics and reaches every analytics
// module the application mounted -- Google Analytics as its recommended
// event, Meta's pixel as its standard event -- at once, not in the next
// batch flush: a visitor who sends a form and closes the tab has left
// before a batch would go.
//
// The silent failures: a value with no currency (Google Analytics drops the
// value and keeps the event, so revenue reads zero), a price in the wrong
// field, an event that waits for a flush the tab never lives to see.
import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

const DVConsentCategory analytics = DVConsentCategory('analytics');

DVAnalyticsSettings settings({bool declareAnalytics = true}) =>
    DVAnalyticsSettings.fromConfig(<String, Object?>{
      'consent': <String, Object?>{
        'version': '2026-11-18',
        'categories': <String, Object?>{
          'essential': <String, Object?>{'required': true},
          if (declareAnalytics)
            'analytics': <String, Object?>{'default': 'granted'},
          'marketing': <String, Object?>{'default': 'denied'},
        },
      },
    });

const DVAnalyticsItem audit = DVAnalyticsItem(
  id: 'SKU-1',
  name: 'Website audit',
  price: 45000,
  quantity: 1,
  category: 'Services',
);

void main() {
  setUp(() {
    DVAnalyticsRuntime.resetForTest();
    dvModuleRegistry.resetForTesting();
  });

  group('each event has Google Analytics recommended name and parameters', () {
    test('view_item', () {
      final DVViewItem event =
          DVViewItem(items: const <DVAnalyticsItem>[audit], currency: 'NGN');
      expect(event.name, 'view_item');
      expect(event.properties, <String, Object?>{
        'currency': 'NGN',
        'value': 45000,
        'items': <Object?>[
          <String, Object?>{
            'item_id': 'SKU-1',
            'item_name': 'Website audit',
            'price': 45000,
            'quantity': 1,
            'item_category': 'Services',
          },
        ],
      });
    });

    test('add_to_cart adds up the items when no value is given', () {
      final DVAddToCart event = DVAddToCart(
        currency: 'USD',
        items: const <DVAnalyticsItem>[
          DVAnalyticsItem(id: 'a', price: 10, quantity: 2),
          DVAnalyticsItem(id: 'b', price: 5.5),
        ],
      );
      expect(event.name, 'add_to_cart');
      expect(event.properties['value'], 25.5);
    });

    test('begin_checkout', () {
      final DVBeginCheckout event = DVBeginCheckout(
          value: 45000,
          currency: 'NGN',
          coupon: 'NOV10',
          items: const <DVAnalyticsItem>[audit]);
      expect(event.name, 'begin_checkout');
      expect(event.properties['coupon'], 'NOV10');
      expect(event.properties['value'], 45000);
    });

    test('purchase carries the transaction id', () {
      final DVPurchase event = DVPurchase(
        transactionId: 'order-981',
        value: 45000,
        currency: 'NGN',
        tax: 0,
        items: const <DVAnalyticsItem>[audit],
      );
      expect(event.name, 'purchase');
      expect(event.properties['transaction_id'], 'order-981');
      expect(event.properties['tax'], 0);
    });

    test('sign_up, login and generate_lead', () {
      expect(DVSignUp(method: 'email').name, 'sign_up');
      expect(DVSignUp(method: 'email').properties,
          <String, Object?>{'method': 'email'});
      expect(DVLogin(method: 'google').name, 'login');
      final DVGenerateLead lead =
          DVGenerateLead(leadSource: 'contact form', value: 50, currency: 'USD');
      expect(lead.name, 'generate_lead');
      expect(lead.properties, <String, Object?>{
        'currency': 'USD',
        'value': 50,
        'lead_source': 'contact form',
      });
      expect(DVGenerateLead().properties, isEmpty);
    });
  });

  group('a mistake Google Analytics would swallow is refused when made', () {
    test('a value without a currency', () {
      expect(() => DVPurchase(transactionId: 't', value: 10, currency: ''),
          throwsArgumentError);
      expect(() => DVGenerateLead(value: 10), throwsArgumentError);
    });

    test('a currency that is not an ISO 4217 code', () {
      expect(() => DVViewItem(value: 10, currency: 'naira'),
          throwsArgumentError);
      expect(() => DVViewItem(value: 10, currency: 'ngn'), throwsArgumentError);
    });

    test('a purchase without a transaction id', () {
      expect(() => DVPurchase(transactionId: ' ', value: 1, currency: 'USD'),
          throwsArgumentError);
    });

    test('an item with neither id nor name', () {
      expect(() => DVViewItem(items: const <DVAnalyticsItem>[
            DVAnalyticsItem(price: 3),
          ]), throwsArgumentError);
    });
  });

  group('tracking one reaches the mounted analytics modules at once', () {
    test('published on analytics.event before the stored consent is read',
        () async {
      final List<Object?> heard = <Object?>[];
      dvModuleRegistry.subscribe(DVStandardEvent.topic, heard.add);
      final Completer<DVDatabaseAdapter> slow = Completer<DVDatabaseAdapter>();
      final DVAnalyticsRuntime runtime = DVAnalyticsRuntime.start(
          settings: settings(), database: () => slow.future);

      unawaited(runtime.track(DVGenerateLead(leadSource: 'contact form')));
      // No await: a module hears it synchronously, as the call is made.
      expect(heard, <Object?>[
        <String, Object?>{
          'name': 'generate_lead',
          'params': <String, Object?>{'lead_source': 'contact form'},
        },
      ]);
      slow.complete(MemoryDVDatabaseAdapter());
      await runtime.ready;
    });

    test('kept in the application\'s own store when its category is declared',
        () async {
      final DVAnalyticsRuntime runtime = DVAnalyticsRuntime.start(
          settings: settings(), database: MemoryDVDatabaseAdapter.new);
      final DVTrackResult result =
          await runtime.track(DVLogin(method: 'email'));
      expect(result.accepted, isTrue);
    });

    test('not kept, and not an error, when the application declares no '
        'analytics category; the modules still hear it', () async {
      final List<Object?> heard = <Object?>[];
      dvModuleRegistry.subscribe(DVStandardEvent.topic, heard.add);
      final DVAnalyticsRuntime runtime = DVAnalyticsRuntime.start(
          settings: settings(declareAnalytics: false),
          database: MemoryDVDatabaseAdapter.new);
      final DVTrackResult result = await runtime.track(DVSignUp());
      expect(result.accepted, isFalse);
      expect(result.reason, contains('analytics'));
      expect(heard, hasLength(1));
    });
  });
}
