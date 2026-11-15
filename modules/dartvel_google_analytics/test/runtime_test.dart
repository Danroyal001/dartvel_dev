// What the module does with a page view or an event, in each of the three
// places it runs: a browser (Google's own tag, and nothing else, since
// Google Analytics has no way to count one event sent twice as one), a
// device (through the application's backend to the Measurement Protocol)
// and the backend itself (the Measurement Protocol directly).
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_google_analytics/dartvel_google_analytics.dart';
import 'package:dartvel_google_analytics/src/browser.dart';
import 'package:dartvel_google_analytics/src/runtime.dart';
import 'package:test/test.dart';

class FakeBrowser implements GoogleAnalyticsBrowser {
  FakeBrowser({this.available = true});

  @override
  final bool available;

  final List<String> log = <String>[];
  bool breaks = false;

  @override
  String? clientId = '123456789.1700000000';

  @override
  String? sessionId = '1700000123';

  @override
  String? pageUrl = 'https://example.com/pricing?plan=pro';

  @override
  String? pageTitle = 'Pricing';

  @override
  void load(String measurementId,
      {required String scriptUrl, required bool sendPageView}) {
    if (breaks) throw StateError('blocked');
    log.add('load $measurementId $scriptUrl sendPageView=$sendPageView');
  }

  @override
  void event(String name, Map<String, Object?> params) {
    if (breaks) throw StateError('blocked');
    log.add('event $name ${jsonEncode(params)}');
  }

  @override
  void consent({required bool granted}) =>
      log.add('consent ${granted ? 'granted' : 'denied'}');
}

const String secret = 'mp-secret-0123456789abcdef';

void main() {
  late FakeBrowser browser;
  late List<Map<String, Object?>> relayed;
  late bool granted;
  late DVHttpFake fake;

  GoogleAnalyticsRuntime runtime({
    GoogleAnalyticsConfig config =
        const GoogleAnalyticsConfig(measurementId: 'G-ABC123XYZ9'),
    DVModuleEnvironment environment = DVModuleEnvironment.web,
    bool relayBreaks = false,
  }) =>
      GoogleAnalyticsRuntime(
        config: config,
        browser: browser,
        environment: environment,
        consentGranted: (String category) => granted,
        relay: (Map<String, Object?> event) async {
          if (relayBreaks) throw StateError('offline');
          relayed.add(event);
        },
        clock: () => DateTime.utc(2026, 11, 14, 12),
        newClientId: () => '555.1794571200',
        scriptUrl:
            'assets/packages/dartvel_google_analytics/assets/google_analytics.js',
      );

  DVPageView page(String address, {String? title}) =>
      DVPageView(location: Uri.parse(address), title: title);

  List<Map<String, Object?>> sent() => <Map<String, Object?>>[
        for (final DVHttpCall call in fake.calls)
          jsonDecode(utf8.decode(call.body)) as Map<String, Object?>,
      ];

  Map<String, Object?> onlyEvent() =>
      (sent().single['events']! as List<Object?>).single!
          as Map<String, Object?>;

  setUp(() {
    browser = FakeBrowser();
    relayed = <Map<String, Object?>>[];
    granted = true;
    DVHttp.reset();
    DVSecrets.reset();
    DVSecrets.configure(<String, String>{
      GoogleAnalyticsConfig.defaultApiSecretName: secret,
    });
    fake = const DVHttp().fake(<String, DVHttpStub>{
      'www.google-analytics.com': DVHttpStub.status(204),
    });
  });

  tearDown(() {
    DVHttp.reset();
    DVSecrets.reset();
  });

  group('in a browser', () {
    test('the first page view loads the tag, with its own page views off, '
        'and sends one', () async {
      await runtime().pageShown(page('/pricing?plan=pro', title: 'Pricing'));
      expect(browser.log, <String>[
        'load G-ABC123XYZ9 '
            'assets/packages/dartvel_google_analytics/assets/google_analytics.js '
            'sendPageView=false',
        'event page_view {"page_location":"https://example.com/pricing?plan=pro",'
            '"page_title":"Pricing"}',
      ]);
      // gtag reports it; a second copy through the backend would be a
      // second page view.
      expect(relayed, isEmpty);
      expect(fake.calls, isEmpty);
    });

    test('each route change is a page view; the tag is loaded once',
        () async {
      final GoogleAnalyticsRuntime analytics = runtime();
      await analytics.pageShown(page('/'));
      await analytics.pageShown(page('/pricing'));
      expect(browser.log.where((String l) => l.startsWith('load')),
          hasLength(1));
      expect(browser.log.where((String l) => l.startsWith('event page_view')),
          hasLength(2));
    });

    test('pageViews: automatic leaves page views to Google\'s tag',
        () async {
      final GoogleAnalyticsRuntime analytics = runtime(
        config: const GoogleAnalyticsConfig(
          measurementId: 'G-ABC123XYZ9',
          pageViews: GoogleAnalyticsPageViews.automatic,
        ),
      );
      await analytics.pageShown(page('/'));
      await analytics.pageShown(page('/pricing'));
      expect(browser.log, hasLength(1));
      expect(browser.log.single, endsWith('sendPageView=true'));
    });

    test('pageViews: off sends none, and events still work', () async {
      final GoogleAnalyticsRuntime analytics = runtime(
        config: const GoogleAnalyticsConfig(
          measurementId: 'G-ABC123XYZ9',
          pageViews: GoogleAnalyticsPageViews.off,
        ),
      );
      await analytics.pageShown(page('/'));
      expect(browser.log, isEmpty);
      await analytics.track(GoogleAnalyticsEvent.generateLead());
      expect(browser.log.first, endsWith('sendPageView=false'));
      expect(browser.log.last, 'event generate_lead {}');
    });

    test('a recommended event goes to gtag with Google\'s parameter names',
        () async {
      await runtime().track(GoogleAnalyticsEvent.beginCheckout(
        value: 45000,
        currency: 'NGN',
        items: const <GoogleAnalyticsItem>[
          GoogleAnalyticsItem(itemId: 'SKU-1', itemName: 'Audit', price: 45000, quantity: 1),
        ],
      ));
      expect(
        browser.log.last,
        'event begin_checkout {"value":45000,"currency":"NGN","items":'
        '[{"item_id":"SKU-1","item_name":"Audit","price":45000,"quantity":1}]}',
      );
    });

    test('a framework page is not a view', () async {
      await runtime().pageShown(page('/__studio/pages'));
      expect(browser.log, isEmpty);
    });

    test('the tag being blocked does not throw', () async {
      browser.breaks = true;
      await runtime().track(GoogleAnalyticsEvent.generateLead());
      await runtime().pageShown(page('/'));
    });
  });

  group('consent', () {
    test('nothing is loaded or sent before it is granted', () async {
      granted = false;
      final GoogleAnalyticsRuntime analytics = runtime();
      await analytics.pageShown(page('/pricing'));
      await analytics.track(GoogleAnalyticsEvent.generateLead());
      expect(browser.log, isEmpty);
      expect(relayed, isEmpty);
    });

    test('once granted, the page on screen is sent, once', () async {
      granted = false;
      final GoogleAnalyticsRuntime analytics = runtime();
      await analytics.pageShown(page('/pricing'));
      granted = true;
      await analytics.consentChanged();
      await analytics.consentChanged();
      expect(browser.log.where((String l) => l.startsWith('event page_view')),
          hasLength(1));
    });

    test('withdrawn, the tag is told and later events are dropped', () async {
      final GoogleAnalyticsRuntime analytics = runtime();
      await analytics.pageShown(page('/pricing'));
      granted = false;
      await analytics.consentChanged();
      await analytics.track(GoogleAnalyticsEvent.generateLead());
      expect(browser.log.last, 'consent denied');

      granted = true;
      await analytics.consentChanged();
      expect(browser.log.last, 'consent granted');
    });
  });

  group('unconfigured', () {
    test('every call does nothing and none throws', () async {
      final GoogleAnalyticsRuntime analytics =
          runtime(config: const GoogleAnalyticsConfig());
      await analytics.pageShown(page('/'));
      await analytics.track(GoogleAnalyticsEvent.generateLead());
      await analytics.consentChanged();
      final Map<String, Object?> context = <String, Object?>{};
      analytics.contributeContext(context);
      expect(browser.log, isEmpty);
      expect(relayed, isEmpty);
      expect(context, isEmpty);
    });
  });

  group('on a device', () {
    setUp(() => browser = FakeBrowser(available: false));

    test('an event goes through the backend, with a client id of the '
        'device\'s own', () async {
      await runtime(environment: DVModuleEnvironment.native)
          .track(GoogleAnalyticsEvent.generateLead(leadSource: 'app'));
      expect(browser.log, isEmpty);
      expect(relayed.single['name'], 'generate_lead');
      expect(relayed.single['params'], <String, Object?>{'lead_source': 'app'});
      expect(relayed.single['client_id'], '555.1794571200');
      expect(relayed.single['session_id'], isNotNull);
    });

    test('a page view is reported under the origin the application names',
        () async {
      await runtime(
        environment: DVModuleEnvironment.native,
        config: const GoogleAnalyticsConfig(
            measurementId: 'G-ABC123XYZ9', origin: 'https://example.com'),
      ).pageShown(page('/pricing?plan=pro', title: 'Pricing'));
      expect(relayed.single['name'], 'page_view');
      expect(relayed.single['params'], <String, Object?>{
        'page_location': 'https://example.com/pricing?plan=pro',
        'page_title': 'Pricing',
      });
    });

    test('the backend being unreachable does not throw', () async {
      await runtime(environment: DVModuleEnvironment.native, relayBreaks: true)
          .track(GoogleAnalyticsEvent.generateLead());
    });
  });

  group('what a checkout is told about the visitor', () {
    test('the client and session ids, when consent allows', () {
      final Map<String, Object?> context = <String, Object?>{};
      runtime().contributeContext(context);
      expect(context['googleAnalytics'], <String, Object?>{
        'client_id': '123456789.1700000000',
        'session_id': '1700000123',
      });
    });

    test('nothing, when it does not', () {
      granted = false;
      final Map<String, Object?> context = <String, Object?>{};
      runtime().contributeContext(context);
      expect(context, isEmpty);
    });
  });

  group('on the backend', () {
    GoogleAnalyticsRuntime backend() =>
        runtime(environment: DVModuleEnvironment.backend);

    test('an event goes straight to the Measurement Protocol', () async {
      await backend().track(
        GoogleAnalyticsEvent.generateLead(value: 10, currency: 'USD'),
        clientId: '9.8',
        userId: 'user-7',
      );
      expect(sent().single['client_id'], '9.8');
      expect(sent().single['user_id'], 'user-7');
      expect(onlyEvent()['name'], 'generate_lead');
    });

    test('without a client id there is nobody to report it for', () async {
      await backend().track(GoogleAnalyticsEvent.generateLead());
      expect(fake.calls, isEmpty);
    });

    test('a device\'s event is sent on', () async {
      final Map<String, Object?> answer =
          await backend().collect(<String, Object?>{
        'name': 'generate_lead',
        'params': <String, Object?>{'lead_source': 'app'},
        'client_id': '555.1794571200',
        'session_id': '1794571200',
      });
      expect(answer['sent'], isTrue);
      expect(sent().single['client_id'], '555.1794571200');
      final Map<String, Object?> params =
          onlyEvent()['params']! as Map<String, Object?>;
      expect(params['lead_source'], 'app');
      expect(params['session_id'], '1794571200');
    });

    test('a client cannot send what is not an event', () async {
      final GoogleAnalyticsRuntime analytics = backend();
      for (final Map<String, Object?> bad in <Map<String, Object?>>[
        <String, Object?>{},
        <String, Object?>{'name': 'session_start', 'client_id': '1.2'},
        <String, Object?>{'name': 'has space', 'client_id': '1.2'},
        <String, Object?>{'name': 'ok'},
        <String, Object?>{'name': 'ok', 'client_id': 'x' * 200},
        <String, Object?>{'name': 'ok', 'client_id': '1.2', 'params': 'no'},
        <String, Object?>{
          'name': 'ok',
          'client_id': '1.2',
          'params': <String, Object?>{'blob': 'x' * 9000},
        },
        <String, Object?>{'name': 'ok', 'client_id': '1.2', 'session_id': 'abc'},
      ]) {
        final Map<String, Object?> answer = await analytics.collect(bad);
        expect(answer['sent'], isFalse, reason: '$bad');
      }
      expect(fake.calls, isEmpty);
    });

    test('with no API secret a device\'s event is dropped, not an error',
        () async {
      DVSecrets.reset();
      final Map<String, Object?> answer = await backend().collect(
          <String, Object?>{'name': 'ok', 'client_id': '1.2'});
      expect(answer['sent'], isFalse);
      expect('${answer['reason']}', isNot(contains(secret)));
    });

    group('a purchase another module confirmed', () {
      Map<String, Object?> purchase({bool consented = true}) =>
          <String, Object?>{
            'transaction_id': '981',
            'total': 47500,
            'value': 45000,
            'tax': 1500,
            'shipping': 1000,
            'coupon': 'LAUNCH',
            'currency': 'NGN',
            'paid_at': '2026-11-14T11:58:00Z',
            'items': <Object?>[
              <String, Object?>{
                'item_id': 'SKU-1',
                'item_name': 'Website audit',
                'price': 45000,
                'quantity': 1,
              },
            ],
            'context': <String, Object?>{
              if (consented)
                'googleAnalytics': <String, Object?>{
                  'client_id': '123456789.1700000000',
                  'session_id': '1700000123',
                },
            },
          };

      test('is reported as the buyer\'s, in the session they were in',
          () async {
        await backend().purchaseConfirmed(purchase());
        expect(sent().single['client_id'], '123456789.1700000000');
        expect(sent().single['timestamp_micros'],
            DateTime.utc(2026, 11, 14, 11, 58).microsecondsSinceEpoch);
        expect(onlyEvent()['name'], 'purchase');
        final Map<String, Object?> params =
            onlyEvent()['params']! as Map<String, Object?>;
        expect(params['transaction_id'], '981');
        // The items' own total: shipping and tax have their own parameters.
        expect(params['value'], 45000);
        expect(params['tax'], 1500);
        expect(params['shipping'], 1000);
        expect(params['coupon'], 'LAUNCH');
        expect(params['currency'], 'NGN');
        expect(params['session_id'], '1700000123');
        expect(params['items'], <Object?>[
          <String, Object?>{
            'item_id': 'SKU-1',
            'item_name': 'Website audit',
            'price': 45000,
            'quantity': 1,
          },
        ]);
      });

      test('is not reported for a buyer who had not consented', () async {
        await backend().purchaseConfirmed(purchase(consented: false));
        expect(fake.calls, isEmpty);
      });

      test('that is not a purchase is ignored', () async {
        await backend().purchaseConfirmed('nonsense');
        await backend().purchaseConfirmed(<String, Object?>{'value': 1});
        expect(fake.calls, isEmpty);
      });

      test('is not reported again from the buyer\'s browser', () async {
        await runtime().purchaseConfirmed(purchase());
        expect(browser.log, isEmpty);
        expect(fake.calls, isEmpty);
      });
    });
  });
}
