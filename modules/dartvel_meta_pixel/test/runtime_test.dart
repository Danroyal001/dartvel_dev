// What the module does with a page view or an event, in each of the three
// places it runs: a browser (the pixel's own script, and the same event sent
// through the application's backend with the same id), a device (the backend
// only) and the backend itself (the Conversions API directly).
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_meta_pixel/dartvel_meta_pixel.dart';
import 'package:dartvel_meta_pixel/src/browser.dart';
import 'package:dartvel_meta_pixel/src/runtime.dart';
import 'package:test/test.dart';

/// A browser that records what it was asked instead of calling fbq.
class FakeBrowser implements MetaPixelBrowser {
  FakeBrowser({this.available = true});

  @override
  final bool available;

  final List<String> log = <String>[];
  final Map<String, String> cookies = <String, String>{};
  bool breaks = false;

  @override
  String? pageUrl = 'https://example.com/pricing';

  @override
  String? userAgent = 'Mozilla/5.0 (Test)';

  @override
  void load(String pixelId, {required String scriptUrl}) {
    if (breaks) throw StateError('blocked');
    log.add('load $pixelId $scriptUrl');
  }

  @override
  void track(String name, Map<String, Object?> data,
      {required String eventId, required bool custom}) {
    if (breaks) throw StateError('blocked');
    log.add('${custom ? 'trackCustom' : 'track'} $name '
        '${jsonEncode(data)} $eventId');
  }

  @override
  void consent({required bool granted}) =>
      log.add('consent ${granted ? 'grant' : 'revoke'}');

  @override
  String? cookie(String name) => cookies[name];

  @override
  String? queryParameter(String name) => null;
}

void main() {
  late FakeBrowser browser;
  late List<Map<String, Object?>> relayed;
  late bool granted;
  int ids = 0;

  MetaPixelRuntime runtime({
    MetaPixelConfig config = const MetaPixelConfig(pixelId: '1234567890'),
    DVModuleEnvironment environment = DVModuleEnvironment.web,
    bool relayBreaks = false,
  }) =>
      MetaPixelRuntime(
        config: config,
        browser: browser,
        environment: environment,
        consentGranted: (String category) => granted,
        relay: (Map<String, Object?> event) async {
          if (relayBreaks) throw StateError('offline');
          relayed.add(event);
        },
        clock: () => DateTime.utc(2026, 11, 14, 12),
        newEventId: () => 'id-${++ids}',
        scriptUrl: 'assets/packages/dartvel_meta_pixel/assets/meta_pixel.js',
      );

  DVPageView page(String address, {String? title}) =>
      DVPageView(location: Uri.parse(address), title: title);

  setUp(() {
    browser = FakeBrowser();
    relayed = <Map<String, Object?>>[];
    granted = true;
    ids = 0;
    DVHttp.reset();
    DVSecrets.reset();
  });

  tearDown(() {
    DVHttp.reset();
    DVSecrets.reset();
  });

  group('in a browser', () {
    test('the first page view loads the pixel and is sent both ways with one '
        'id', () async {
      await runtime().pageShown(page('/pricing'));

      expect(browser.log, <String>[
        'load 1234567890 '
            'assets/packages/dartvel_meta_pixel/assets/meta_pixel.js',
        'track PageView {} id-1',
      ]);
      expect(relayed.single['name'], 'PageView');
      expect(relayed.single['id'], 'id-1');
      expect(relayed.single['url'], 'https://example.com/pricing');
      expect(relayed.single['source'], 'website');
    });

    test('the pixel is loaded once, however many events follow', () async {
      final MetaPixelRuntime pixel = runtime();
      await pixel.pageShown(page('/'));
      await pixel.pageShown(page('/pricing'));
      await pixel.track(MetaPixelEvent.contact());
      expect(
          browser.log.where((String l) => l.startsWith('load')), hasLength(1));
      expect(relayed.map((Map<String, Object?> e) => e['name']),
          <String>['PageView', 'PageView', 'Contact']);
    });

    test('a purchase carries its value and currency to both', () async {
      await runtime().track(
        MetaPixelEvent.purchase(value: 45000, currency: 'NGN'),
        eventId: 'order-981',
      );
      expect(browser.log.last,
          'track Purchase {"value":45000,"currency":"NGN"} order-981');
      expect(relayed.single['id'], 'order-981');
      expect(relayed.single['data'],
          <String, Object?>{'value': 45000, 'currency': 'NGN'});
    });

    test('a custom event is tracked as one', () async {
      await runtime().track(MetaPixelEvent.custom('BookedDemo',
          data: <String, Object?>{'plan': 'pro'}));
      expect(browser.log.last, 'trackCustom BookedDemo {"plan":"pro"} id-1');
      expect(relayed.single['custom'], isTrue);
    });

    test('the cookies Meta matches a visitor by go with the event', () async {
      browser.cookies['_fbp'] = 'fb.1.1700000000000.123';
      browser.cookies['_fbc'] = 'fb.1.1700000000000.AbC';
      await runtime().track(MetaPixelEvent.lead());
      expect(relayed.single['fbp'], 'fb.1.1700000000000.123');
      expect(relayed.single['fbc'], 'fb.1.1700000000000.AbC');
    });

    test('the same page twice running is one view', () async {
      final MetaPixelRuntime pixel = runtime();
      await pixel.pageShown(page('/pricing'));
      await pixel.pageShown(page('/pricing'));
      expect(relayed, hasLength(1));
    });

    test('a framework page is not a view', () async {
      await runtime().pageShown(page('/__studio/pages'));
      expect(browser.log, isEmpty);
      expect(relayed, isEmpty);
    });

    test('the pixel\'s script being blocked does not stop the server event, '
        'and does not throw', () async {
      browser.breaks = true;
      await runtime().track(MetaPixelEvent.contact());
      expect(relayed.single['name'], 'Contact');
    });

    test('the backend being unreachable does not throw either', () async {
      await runtime(relayBreaks: true).track(MetaPixelEvent.contact());
      expect(browser.log.last, startsWith('track Contact'));
    });

    test('serverEvents: false keeps events in the browser', () async {
      await runtime(
        config: const MetaPixelConfig(pixelId: '1234567890', serverEvents: false),
      ).track(MetaPixelEvent.contact());
      expect(browser.log.last, startsWith('track Contact'));
      expect(relayed, isEmpty);
    });
  });

  group('consent', () {
    test('nothing is loaded or sent before it is granted', () async {
      granted = false;
      final MetaPixelRuntime pixel = runtime();
      await pixel.pageShown(page('/pricing'));
      await pixel.track(MetaPixelEvent.lead());
      expect(browser.log, isEmpty);
      expect(relayed, isEmpty);
    });

    test('once granted, the page on screen is sent, once', () async {
      granted = false;
      final MetaPixelRuntime pixel = runtime();
      await pixel.pageShown(page('/pricing'));

      granted = true;
      await pixel.consentChanged();
      await pixel.consentChanged();

      expect(browser.log.where((String l) => l.startsWith('track PageView')),
          hasLength(1));
      expect(relayed, hasLength(1));
    });

    test('withdrawn, the pixel is told and later events are dropped',
        () async {
      final MetaPixelRuntime pixel = runtime();
      await pixel.pageShown(page('/pricing'));
      granted = false;
      await pixel.consentChanged();
      await pixel.track(MetaPixelEvent.lead());

      expect(browser.log.last, 'consent revoke');
      expect(relayed.map((Map<String, Object?> e) => e['name']),
          <String>['PageView']);
    });

    test('granted again, the pixel is told', () async {
      final MetaPixelRuntime pixel = runtime();
      await pixel.pageShown(page('/pricing'));
      granted = false;
      await pixel.consentChanged();
      granted = true;
      await pixel.consentChanged();
      expect(browser.log, contains('consent grant'));
    });
  });

  group('unconfigured', () {
    test('every call does nothing and none throws', () async {
      final MetaPixelRuntime pixel = runtime(config: const MetaPixelConfig());
      await pixel.pageShown(page('/'));
      await pixel.track(MetaPixelEvent.purchase(value: 1, currency: 'USD'));
      await pixel.outboundClick(Uri.parse('https://wa.me/2348030000000'));
      await pixel.consentChanged();
      final Map<String, Object?> context = <String, Object?>{};
      pixel.contributeContext(context);

      expect(browser.log, isEmpty);
      expect(relayed, isEmpty);
      expect(context, isEmpty);
    });
  });

  group('on a device', () {
    test('there is no pixel script: the event goes through the backend',
        () async {
      browser = FakeBrowser(available: false);
      await runtime(environment: DVModuleEnvironment.native)
          .track(MetaPixelEvent.lead());
      expect(browser.log, isEmpty);
      expect(relayed.single['name'], 'Lead');
      expect(relayed.single['source'], 'device');
    });
  });

  group('a tap that leaves the application', () {
    test('WhatsApp, a phone number and an email address are a Contact',
        () async {
      final MetaPixelRuntime pixel = runtime();
      await pixel.outboundClick(Uri.parse('https://wa.me/2348030000000'));
      await pixel.outboundClick(Uri.parse('tel:+2348030000000'));
      await pixel.outboundClick(Uri.parse('mailto:hello@example.com'));
      await pixel.outboundClick(
          Uri.parse('https://api.whatsapp.com/send?phone=2348030000000'));
      expect(relayed.map((Map<String, Object?> e) => e['name']),
          <String>['Contact', 'Contact', 'Contact', 'Contact']);
    });

    test('the caller can say it is a Lead instead', () async {
      await runtime().outboundClick(
        Uri.parse('https://wa.me/2348030000000'),
        event: MetaPixelEvent.lead(contentName: 'WhatsApp'),
      );
      expect(relayed.single['name'], 'Lead');
    });

    test('any other link is a custom OutboundClick naming where it went, '
        'without its query', () async {
      await runtime().outboundClick(
          Uri.parse('https://partner.example/offer?token=secret'));
      expect(relayed.single['name'], 'OutboundClick');
      expect(relayed.single['data'],
          <String, Object?>{'destination': 'https://partner.example/offer'});
    });
  });

  group('what a checkout is told about the visitor', () {
    test('the cookies and the page, when consent allows', () {
      browser.cookies['_fbp'] = 'fb.1.1700000000000.123';
      final Map<String, Object?> context = <String, Object?>{};
      runtime().contributeContext(context);
      expect(context['metaPixel'], <String, Object?>{
        'fbp': 'fb.1.1700000000000.123',
        'url': 'https://example.com/pricing',
        'agent': 'Mozilla/5.0 (Test)',
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
    const String token = 'EAAB-test-access-token-0123456789';
    late DVHttpFake fake;

    List<Map<String, Object?>> sent() => <Map<String, Object?>>[
          for (final DVHttpCall call in fake.calls)
            ...(jsonDecode(Uri.splitQueryString(utf8.decode(call.body))['data']!)
                    as List<Object?>)
                .cast<Map<String, Object?>>(),
        ];

    setUp(() {
      DVSecrets.configure(<String, String>{
        MetaPixelConfig.defaultAccessTokenSecret: token,
      });
      fake = const DVHttp().fake(<String, DVHttpStub>{
        'graph.facebook.com':
            DVHttpStub.json(<String, Object?>{'events_received': 1}),
      });
    });

    MetaPixelRuntime backend() =>
        runtime(environment: DVModuleEnvironment.backend);

    test('an event goes straight to the Conversions API', () async {
      await backend().track(
        MetaPixelEvent.lead(contentName: 'Callback form'),
        user: const MetaUserData(email: 'ada@example.com'),
        sourceUrl: Uri.parse('https://example.com/contact'),
      );
      expect(browser.log, isEmpty);
      expect(relayed, isEmpty);
      final Map<String, Object?> event = sent().single;
      expect(event['event_name'], 'Lead');
      expect(event['event_source_url'], 'https://example.com/contact');
      expect((event['user_data']! as Map<String, Object?>)['em'], isNotNull);
    });

    test('a client\'s event is sent on with the address and user agent of '
        'the request it arrived on', () async {
      final Map<String, Object?> answer = await DVModuleRpc.withRequest(
        Request(
          method: 'POST',
          url: Uri.parse('https://example.com/api/_dv/modules/metaPixel/collect'),
          headers: Headers(<String, Object?>{'user-agent': 'Mozilla/5.0 (Real)'}),
          bodyStream: const Stream<List<int>>.empty(),
          peerAddress: DVPeerAddress(DVIpAddress.parse('203.0.113.9'), port: 443),
        ),
        () => backend().collect(<String, Object?>{
          'name': 'Purchase',
          'custom': false,
          'id': 'order-981',
          'time': DateTime.utc(2026, 11, 14, 11, 59).millisecondsSinceEpoch ~/ 1000,
          'url': 'https://example.com/thanks',
          'data': <String, Object?>{'value': 45000, 'currency': 'NGN'},
          'fbp': 'fb.1.1700000000000.123',
          'source': 'website',
          // What the client says its user agent is does not outrank the
          // request's own header.
          'agent': 'Spoofed/1.0',
        }),
      );

      expect(answer['sent'], isTrue);
      final Map<String, Object?> event = sent().single;
      expect(event['event_name'], 'Purchase');
      expect(event['event_id'], 'order-981');
      expect(event['action_source'], 'website');
      expect(event['event_source_url'], 'https://example.com/thanks');
      expect(event['custom_data'],
          <String, Object?>{'value': 45000, 'currency': 'NGN'});
      final Map<String, Object?> user =
          event['user_data']! as Map<String, Object?>;
      expect(user['client_user_agent'], 'Mozilla/5.0 (Real)');
      expect(user['client_ip_address'], '203.0.113.9');
      expect(user['fbp'], 'fb.1.1700000000000.123');
    });

    test('a client cannot send what is not an event', () async {
      final MetaPixelRuntime pixel = backend();
      for (final Map<String, Object?> bad in <Map<String, Object?>>[
        <String, Object?>{},
        <String, Object?>{'name': 'x' * 51, 'custom': true},
        <String, Object?>{'name': 'NotStandard', 'custom': false},
        <String, Object?>{'name': 'Lead', 'url': 'javascript:alert(1)'},
        <String, Object?>{'name': 'Lead', 'data': 'not a map'},
        <String, Object?>{
          'name': 'Lead',
          'data': <String, Object?>{'blob': 'x' * 5000},
        },
        <String, Object?>{'name': 'Lead', 'fbp': 'not-a-cookie'},
      ]) {
        final Map<String, Object?> answer = await pixel.collect(bad);
        expect(answer['sent'], isFalse, reason: '$bad');
      }
      expect(fake.calls, isEmpty);
    });

    test('a client\'s event dated outside the last week is dated now',
        () async {
      await backend().collect(<String, Object?>{
        'name': 'Lead',
        'time': 1,
        'url': 'https://example.com/',
      });
      expect(sent().single['event_time'],
          DateTime.utc(2026, 11, 14, 12).millisecondsSinceEpoch ~/ 1000);
    });

    test('with no access token a client\'s event is dropped, not an error',
        () async {
      DVSecrets.reset();
      final Map<String, Object?> answer = await backend()
          .collect(<String, Object?>{'name': 'Lead', 'url': 'https://example.com/'});
      expect(answer['sent'], isFalse);
      expect('${answer['reason']}', isNot(contains(token)));
    });

    group('a purchase another module confirmed', () {
      Map<String, Object?> purchase({bool consented = true}) =>
          <String, Object?>{
            'transaction_id': '981',
            'total': 47500,
            'value': 45000,
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
            'customer': <String, Object?>{
              'email': 'ada@example.com',
              'phone': '+2348030000000',
              'first_name': 'Ada',
              'last_name': 'Obi',
              'country': 'NG',
            },
            'context': <String, Object?>{
              if (consented)
                'metaPixel': <String, Object?>{
                  'fbp': 'fb.1.1700000000000.123',
                  'url': 'https://example.com/cart',
                  'agent': 'Mozilla/5.0 (Buyer)',
                },
              'request': <String, Object?>{'ip': '203.0.113.9'},
            },
          };

      test('is reported with an id the browser\'s own report shares',
          () async {
        await backend().purchaseConfirmed(purchase());
        final Map<String, Object?> event = sent().single;
        expect(event['event_name'], 'Purchase');
        expect(event['event_id'], 'purchase.981');
        expect(event['event_time'],
            DateTime.utc(2026, 11, 14, 11, 58).millisecondsSinceEpoch ~/ 1000);
        expect(event['event_source_url'], 'https://example.com/cart');
        final Map<String, Object?> custom =
            event['custom_data']! as Map<String, Object?>;
        expect(custom['value'], 47500);
        expect(custom['currency'], 'NGN');
        expect(custom['content_type'], 'product');
        expect(custom['contents'], <Object?>[
          <String, Object?>{'id': 'SKU-1', 'quantity': 1, 'item_price': 45000},
        ]);
        final Map<String, Object?> user =
            event['user_data']! as Map<String, Object?>;
        expect(user['em'], isNotNull);
        expect(user['fbp'], 'fb.1.1700000000000.123');
        expect(user['client_user_agent'], 'Mozilla/5.0 (Buyer)');
        expect(user['client_ip_address'], '203.0.113.9');
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

      test('in the buyer\'s browser it is the pixel\'s Purchase, with the '
          'same id and no second server event', () async {
        await runtime().purchaseConfirmed(purchase());
        expect(
          browser.log.last,
          startsWith('track Purchase {"value":47500,"currency":"NGN"'),
        );
        expect(browser.log.last, endsWith('purchase.981'));
        expect(relayed, isEmpty);
        expect(fake.calls, isEmpty);
      });
    });
  });
}
