// What a paid click needs from Google's tag in a browser.
//
// Consent Mode v2: where the application declares a consent policy, the tag
// starts with every storage denied and only analytics storage is granted, by
// the visitor's own choice, before the tag is configured -- a default left
// out means Google treats the visit as consented for ad storage. A page view
// carries its path and, on the landing page, the campaign the visitor came
// from, which a single page application otherwise loses at the first route
// change. And the framework's standard events reach the tag the moment they
// are tracked.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_google_analytics/dartvel_google_analytics.dart';
import 'package:dartvel_google_analytics/src/browser.dart';
import 'package:dartvel_google_analytics/src/runtime.dart';
import 'package:test/test.dart';

class FakeBrowser implements GoogleAnalyticsBrowser {
  final List<String> log = <String>[];

  @override
  bool get available => true;

  @override
  String? clientId;

  @override
  String? sessionId;

  @override
  String? pageUrl = 'https://example.com/?utm_source=facebook';

  @override
  String? pageTitle = 'Home';

  @override
  void consentDefaults() => log.add('consent defaults');

  @override
  void load(String measurementId,
          {required String scriptUrl, required bool sendPageView}) =>
      log.add('load sendPageView=$sendPageView');

  @override
  void event(String name, Map<String, Object?> params) =>
      log.add('event $name ${jsonEncode(params)}');

  @override
  void consent({required bool granted}) =>
      log.add('consent ${granted ? 'granted' : 'denied'}');
}

class MapStorage implements DVAttributionStorage {
  final Map<String, String> values = <String, String>{};
  @override
  String? read(String key) => values[key];
  @override
  void write(String key, String value) => values[key] = value;
}

void main() {
  late FakeBrowser browser;
  late DVAttribution attribution;

  GoogleAnalyticsRuntime runtime({bool policy = false}) =>
      GoogleAnalyticsRuntime(
        config: const GoogleAnalyticsConfig(measurementId: 'G-ABC123XYZ9'),
        browser: browser,
        environment: DVModuleEnvironment.web,
        consentGranted: (String _) => true,
        consentRequired: () => policy,
        attribution: () => attribution,
      );

  setUp(() {
    browser = FakeBrowser();
    attribution = DVAttribution(storage: MapStorage());
  });

  group('Consent Mode v2', () {
    test('with a consent policy, every storage defaults to denied before the '
        'tag is configured', () async {
      await runtime(policy: true).pageShown(
          DVPageView(location: Uri.parse('/'), title: 'Home'));
      expect(browser.log.take(2), <String>['consent defaults', 'load sendPageView=true']);
    });

    test('with no policy there is nothing to default', () async {
      await runtime().pageShown(DVPageView(location: Uri.parse('/')));
      expect(browser.log.first, 'load sendPageView=true');
    });
  });

  group('page views', () {
    test('carry page_location, page_path and page_title', () async {
      final GoogleAnalyticsRuntime analytics = runtime();
      await analytics.pageShown(DVPageView(location: Uri.parse('/')));
      browser.pageUrl = 'https://example.com/services/web';
      await analytics.pageShown(DVPageView(
          location: Uri.parse('/services/web'), title: 'Web design'));
      expect(
        browser.log.last,
        'event page_view {"page_location":"https://example.com/services/web",'
        '"page_path":"/services/web","page_title":"Web design"}',
      );
    });

    // Google's tag counts the landing page itself, from the address, which
    // still has the campaign's utm_* parameters; the module adds no copy and
    // later pages do not repeat the campaign.
    test('the landing page is the tag\'s own; the next page carries no '
        'campaign', () async {
      attribution.capture(Uri.parse('https://example.com/?utm_source=facebook'
          '&utm_medium=paid_social&utm_campaign=nov&utm_content=video'
          '&utm_term=web&utm_id=42&fbclid=abc'));
      final GoogleAnalyticsRuntime analytics = runtime();
      await analytics.pageShown(DVPageView(location: Uri.parse('/')));
      expect(browser.log.where((String l) => l.startsWith('event page_view')),
          isEmpty);
      expect(browser.log.where((String l) => l.contains('sendPageView=true')),
          hasLength(1));

      browser.pageUrl = 'https://example.com/contact';
      await analytics.pageShown(DVPageView(location: Uri.parse('/contact')));
      expect(browser.log.last, isNot(contains('campaign_')));
    });

    test('a direct visit carries no campaign', () async {
      attribution.capture(Uri.parse('https://example.com/'));
      final GoogleAnalyticsRuntime analytics = runtime();
      await analytics.pageShown(DVPageView(location: Uri.parse('/')));
      await analytics.pageShown(DVPageView(location: Uri.parse('/next')));
      expect(browser.log.last, isNot(contains('campaign_')));
    });
  });

  group('standard events', () {
    test('a tracked DVStandardEvent goes to gtag as the same recommended '
        'event, at once', () async {
      final GoogleAnalyticsRuntime analytics = runtime();
      await analytics.standardEvent(DVPurchase(
        transactionId: 'order-981',
        value: 45000,
        currency: 'NGN',
        items: const <DVAnalyticsItem>[
          DVAnalyticsItem(id: 'SKU-1', name: 'Audit', price: 45000),
        ],
      ).toPayload());
      expect(
        browser.log.last,
        'event purchase {"transaction_id":"order-981","currency":"NGN",'
        '"value":45000,"items":[{"item_id":"SKU-1","item_name":"Audit",'
        '"price":45000}]}',
      );
    });

    test('a payload that is not an event is ignored', () async {
      final GoogleAnalyticsRuntime analytics = runtime();
      await analytics.standardEvent('nonsense');
      await analytics.standardEvent(<String, Object?>{'name': 'ga_reserved'});
      expect(browser.log.where((String l) => l.startsWith('event')), isEmpty);
    });
  });
}
