// What a paid click needs from Meta's pixel in a browser.
//
// The framework's standard events reach the pixel as Meta's standard events
// the moment they are tracked: a lead form that reports `generate_lead` to
// Google and nothing to Meta is a Meta campaign with zero conversions. And
// the click id survives the page: Meta reads fbclid from the address the
// pixel loads on, which in a single page application is usually not the
// landing address -- the visitor accepts the banner on the second page and
// the click is lost, with nothing saying so.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_meta_pixel/dartvel_meta_pixel.dart';
import 'package:dartvel_meta_pixel/src/browser.dart';
import 'package:dartvel_meta_pixel/src/runtime.dart';
import 'package:test/test.dart';

class FakeBrowser implements MetaPixelBrowser {
  final List<String> log = <String>[];
  final Map<String, String> cookies = <String, String>{};

  @override
  bool get available => true;

  @override
  String? pageUrl = 'https://example.com/contact';

  @override
  String? userAgent = 'Mozilla/5.0 (Test)';

  @override
  void load(String pixelId, {required String scriptUrl}) => log.add('load');

  @override
  void track(String name, Map<String, Object?> data,
          {required String eventId, required bool custom}) =>
      log.add('track $name ${jsonEncode(data)} $eventId');

  @override
  void consent({required bool granted}) => log.add('consent $granted');

  @override
  String? cookie(String name) => cookies[name];

  @override
  void setCookie(String name, String value, {required Duration maxAge}) {
    cookies[name] = value;
    log.add('cookie $name=$value max-age=${maxAge.inSeconds}');
  }

  @override
  String? queryParameter(String name) => null;
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
  late List<Map<String, Object?>> relayed;
  int ids = 0;

  MetaPixelRuntime runtime() => MetaPixelRuntime(
        config: const MetaPixelConfig(pixelId: '1234567890'),
        browser: browser,
        environment: DVModuleEnvironment.web,
        consentGranted: (String _) => true,
        relay: (Map<String, Object?> event) async => relayed.add(event),
        clock: () => DateTime.utc(2026, 11, 18, 12),
        newEventId: () => 'id-${++ids}',
        attribution: () => attribution,
      );

  Future<String?> sendStandard(DVStandardEvent event) async {
    browser.log.clear();
    await runtime().standardEvent(event.toPayload());
    final Iterable<String> tracked =
        browser.log.where((String l) => l.startsWith('track '));
    return tracked.isEmpty ? null : tracked.single;
  }

  setUp(() {
    browser = FakeBrowser();
    attribution = DVAttribution(storage: MapStorage());
    relayed = <Map<String, Object?>>[];
    ids = 0;
  });

  group('standard events become Meta standard events', () {
    const DVAnalyticsItem audit = DVAnalyticsItem(
        id: 'SKU-1', name: 'Website audit', price: 45000, quantity: 2);

    test('view_item is ViewContent', () async {
      expect(
        await sendStandard(DVViewItem(
            currency: 'NGN', items: const <DVAnalyticsItem>[audit])),
        'track ViewContent {"currency":"NGN","value":90000,'
        '"content_ids":["SKU-1"],"contents":[{"id":"SKU-1","quantity":2,'
        '"item_price":45000}],"content_type":"product",'
        '"content_name":"Website audit"} id-1',
      );
    });

    test('add_to_cart is AddToCart', () async {
      expect(
          await sendStandard(DVAddToCart(
              currency: 'NGN', items: const <DVAnalyticsItem>[audit])),
          startsWith('track AddToCart {"currency":"NGN","value":90000,'));
    });

    test('begin_checkout is InitiateCheckout with the number of items',
        () async {
      final String? line = await sendStandard(DVBeginCheckout(
          currency: 'NGN', items: const <DVAnalyticsItem>[audit]));
      expect(line, startsWith('track InitiateCheckout '));
      expect(line, contains('"num_items":2'));
    });

    test('purchase is Purchase, with the event id a server purchase uses',
        () async {
      final String? line = await sendStandard(DVPurchase(
          transactionId: 'order-981', value: 90000, currency: 'NGN',
          items: const <DVAnalyticsItem>[audit]));
      expect(line, startsWith('track Purchase {"currency":"NGN","value":90000,'));
      expect(line, endsWith(' purchase.order-981'));
      expect(relayed.last['id'], 'purchase.order-981');
    });

    test('sign_up is CompleteRegistration', () async {
      expect(await sendStandard(DVSignUp(method: 'email')),
          'track CompleteRegistration {} id-1');
    });

    test('generate_lead is Lead, named after its source', () async {
      expect(await sendStandard(DVGenerateLead(leadSource: 'contact form')),
          'track Lead {"content_name":"contact form"} id-1');
      expect(relayed.last['name'], 'Lead');
    });

    test('login has no Meta standard event and sends nothing', () async {
      expect(await sendStandard(DVLogin(method: 'google')), isNull);
      expect(relayed, isEmpty);
    });

    test('a payload that is not an event is ignored', () async {
      await runtime().standardEvent('nonsense');
      await runtime().standardEvent(<String, Object?>{'name': 7});
      expect(browser.log, isEmpty);
    });
  });

  group('the click id outlives the landing page', () {
    test('a later page sends the fbclid the landing page carried, in _fbc '
        'format, and keeps it in the _fbc cookie', () async {
      attribution.capture(
          Uri.parse('https://example.com/?utm_source=facebook&fbclid=IwAR0abc'));
      final String fbc = attribution.lastTouch!.fbc!;
      await runtime()
          .pageShown(DVPageView(location: Uri.parse('/contact')));
      expect(browser.cookies['_fbc'], fbc);
      expect(browser.log.first, 'load');
      expect(browser.log[1], 'cookie _fbc=$fbc max-age=${90 * 24 * 3600}');
      expect(relayed.single['fbc'], fbc);
    });

    test('a _fbc cookie Meta already set is left alone', () async {
      attribution.capture(Uri.parse('https://example.com/?fbclid=new'));
      browser.cookies['_fbc'] = 'fb.1.1.old';
      await runtime().pageShown(DVPageView(location: Uri.parse('/')));
      expect(browser.log.where((String l) => l.startsWith('cookie')), isEmpty);
      expect(relayed.single['fbc'], 'fb.1.1.old');
    });

    test('no click, no cookie', () async {
      attribution.capture(Uri.parse('https://example.com/'));
      await runtime().pageShown(DVPageView(location: Uri.parse('/')));
      expect(browser.cookies, isEmpty);
      expect(relayed.single.containsKey('fbc'), isFalse);
    });
  });

  group('the landing page view carries the campaign', () {
    test('utm parameters on the first PageView only', () async {
      attribution.capture(Uri.parse('https://example.com/?utm_source=facebook'
          '&utm_medium=paid_social&utm_campaign=nov'));
      final MetaPixelRuntime pixel = runtime();
      await pixel.pageShown(DVPageView(location: Uri.parse('/')));
      expect(
          browser.log.last,
          'track PageView {"utm_source":"facebook","utm_medium":"paid_social",'
          '"utm_campaign":"nov"} id-1');
      await pixel.pageShown(DVPageView(location: Uri.parse('/contact')));
      expect(browser.log.last, 'track PageView {} id-2');
    });
  });
}
