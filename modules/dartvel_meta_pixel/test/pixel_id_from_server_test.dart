// The pixel id from the server's secret, with nothing in the pubspec.
//
// `META_PIXEL_ID` is in the module's capabilities so the owner can turn the
// pixel on by setting it in the server's environment, with `pixelId` left
// empty and no rebuild. The backend read it, but a browser has no
// environment: `DVSecrets` there is empty by design, so the client saw no id,
// never loaded the pixel and never sent anything. The id is public (it is in
// every request the pixel makes), so the client asks its own backend for it.
import 'dart:convert';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_meta_pixel/dartvel_meta_pixel.dart';
import 'package:dartvel_meta_pixel/src/browser.dart';
import 'package:dartvel_meta_pixel/src/carrier_backend.dart';
import 'package:dartvel_meta_pixel/src/runtime.dart';
import 'package:test/test.dart';

class FakeBrowser implements MetaPixelBrowser {
  final List<String> log = <String>[];

  @override
  bool get available => true;

  @override
  String? pageUrl = 'https://example.com/tools/word-counter';

  @override
  String? userAgent = 'Mozilla/5.0 (Test)';

  @override
  void load(String pixelId, {required String scriptUrl}) =>
      log.add('load $pixelId');

  @override
  void track(String name, Map<String, Object?> data,
          {required String eventId, required bool custom}) =>
      log.add('track $name ${jsonEncode(data)} $eventId');

  @override
  void consent({required bool granted}) => log.add('consent $granted');

  @override
  String? cookie(String name) => null;

  @override
  void setCookie(String name, String value, {required Duration maxAge}) {}

  @override
  String? queryParameter(String name) => null;
}

void main() {
  late FakeBrowser browser;
  late List<Map<String, Object?>> relayed;
  late bool granted;
  late int asked;
  int ids = 0;

  MetaPixelRuntime client({
    MetaPixelConfig config = const MetaPixelConfig(pixelId: ''),
    Future<String?> Function()? answer,
  }) =>
      MetaPixelRuntime(
        config: config,
        browser: browser,
        environment: DVModuleEnvironment.web,
        consentGranted: (String category) => granted,
        relay: (Map<String, Object?> event) async => relayed.add(event),
        serverPixelId: () async {
          asked++;
          return answer == null ? '1234567890' : answer();
        },
        clock: () => DateTime.utc(2026, 11, 25, 12),
        newEventId: () => 'id-${++ids}',
      );

  DVPageView page(String address) => DVPageView(location: Uri.parse(address));

  setUp(() {
    browser = FakeBrowser();
    relayed = <Map<String, Object?>>[];
    granted = true;
    asked = 0;
    ids = 0;
    DVSecrets.reset();
  });

  tearDown(DVSecrets.reset);

  group('in a browser, with pixelId empty', () {
    test('the id comes from the server and the page is sent with it',
        () async {
      final MetaPixelRuntime pixel = client();
      await pixel.pageShown(page('/'));
      expect(browser.log, <String>['load 1234567890', 'track PageView {} id-1']);
      expect(relayed.single['id'], 'id-1');
      expect(pixel.config.isConfigured, isTrue);
    });

    test('the server is asked once, however many events follow', () async {
      final MetaPixelRuntime pixel = client();
      await Future.wait(<Future<void>>[
        pixel.pageShown(page('/')),
        pixel.track(MetaPixelEvent.lead()),
      ]);
      await pixel.pageShown(page('/tools/qr-code'));
      await pixel.track(MetaPixelEvent.viewContent());
      expect(asked, 1);
      expect(relayed.map((Map<String, Object?> e) => e['name']),
          containsAll(<String>['PageView', 'Lead', 'ViewContent']));
      expect(relayed.where((Map<String, Object?> e) => e['name'] == 'PageView'),
          hasLength(2));
    });

    test('nothing is asked before consent; once granted, the page goes out',
        () async {
      granted = false;
      final MetaPixelRuntime pixel = client();
      await pixel.pageShown(page('/'));
      await pixel.track(MetaPixelEvent.lead());
      expect(asked, 0, reason: 'a visitor who said no costs no request');
      expect(browser.log, isEmpty);

      granted = true;
      await pixel.consentChanged();
      expect(asked, 1);
      expect(browser.log, <String>['load 1234567890', 'track PageView {} id-1']);
    });

    test('a server with no id leaves the module doing nothing, and does not '
        'throw', () async {
      final MetaPixelRuntime pixel =
          client(answer: () async => null);
      await pixel.pageShown(page('/'));
      await pixel.track(MetaPixelEvent.lead());
      expect(browser.log, isEmpty);
      expect(relayed, isEmpty);
    });

    test('a server that cannot be reached is the same', () async {
      final MetaPixelRuntime pixel =
          client(answer: () async => throw StateError('offline'));
      await pixel.pageShown(page('/'));
      expect(browser.log, isEmpty);
      expect(relayed, isEmpty);
    });

    test('an answer that is not a pixel id is not used', () async {
      final MetaPixelRuntime pixel =
          client(answer: () async => '<script>');
      await pixel.pageShown(page('/'));
      expect(browser.log, isEmpty);
    });
  });

  test('a pixelId in the pubspec is used as it is; the server is not asked',
      () async {
    await client(config: const MetaPixelConfig(pixelId: '5555555555'))
        .pageShown(page('/'));
    expect(asked, 0);
    expect(browser.log.first, 'load 5555555555');
  });

  group('on the backend', () {
    test('a client asking for the id gets the server\'s META_PIXEL_ID',
        () async {
      DVSecrets.configure(<String, String>{'META_PIXEL_ID': '987654321012'});
      MetaPixelRuntime.instance =
          MetaPixelRuntime(environment: DVModuleEnvironment.backend);
      expect(await dvModuleDispatch('settings', const <String, Object?>{}),
          <String, Object?>{'pixelId': '987654321012'});
    });

    test('and null when there is none, or it is not an id', () async {
      MetaPixelRuntime.instance =
          MetaPixelRuntime(environment: DVModuleEnvironment.backend);
      expect(await dvModuleDispatch('settings', const <String, Object?>{}),
          <String, Object?>{'pixelId': null});
      DVSecrets.configure(<String, String>{'META_PIXEL_ID': 'not-an-id'});
      expect(await dvModuleDispatch('settings', const <String, Object?>{}),
          <String, Object?>{'pixelId': null});
    });

    test('the token is never in the answer', () async {
      DVSecrets.configure(<String, String>{
        'META_PIXEL_ID': '987654321012',
        'META_CONVERSIONS_API_TOKEN': 'EAAG-secret-token',
      });
      MetaPixelRuntime.instance =
          MetaPixelRuntime(environment: DVModuleEnvironment.backend);
      final Object? answer =
          await dvModuleDispatch('settings', const <String, Object?>{});
      expect(jsonEncode(answer), isNot(contains('EAAG')));
    });
  });
}
