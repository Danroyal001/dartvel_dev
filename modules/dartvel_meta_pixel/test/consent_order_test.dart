// The module hears the visitor's consent whichever starts first.
//
// The generated client starts the mounted modules before it starts
// DV.Analytics. The module asked for consent changes at start, found no
// analytics runtime yet, and listened to nothing: a visitor who tapped
// Accept all was recorded as consenting and the module never loaded its
// script, on that page or any later one. Nothing failed and nothing was
// logged; the site simply measured nobody.
import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_meta_pixel/src/consent.dart';
import 'package:test/test.dart';

const DVConsentCategory analytics = DVConsentCategory('analytics');
const DVConsentCategory marketing = DVConsentCategory('marketing');

DVAnalyticsSettings settings() =>
    DVAnalyticsSettings.fromConfig(<String, Object?>{
      'consent': <String, Object?>{
        'version': '2026-11-18',
        'categories': <String, Object?>{
          'essential': <String, Object?>{'required': true},
          'analytics': <String, Object?>{'default': 'denied'},
          'marketing': <String, Object?>{'default': 'denied'},
        },
      },
    });

void main() {
  setUp(DVAnalyticsRuntime.resetForTest);
  tearDown(DVAnalyticsRuntime.resetForTest);

  test('a module started before DV.Analytics hears the stored consent and '
      'every change after it', () async {
    int heard = 0;
    dvMetaPixelOnConsent(() => heard++);

    final DVAnalyticsRuntime runtime = DVAnalyticsRuntime.start(
        settings: settings(), database: MemoryDVDatabaseAdapter.new);
    await runtime.ready;
    expect(heard, 1, reason: 'told once the stored consent has been read');

    await runtime.loadedConsent!.record(
      <DVConsentCategory, bool>{analytics: true, marketing: true},
      asked: <DVConsentCategory>{analytics, marketing},
      prompt: DVConsentPrompt.banner,
    );
    expect(heard, greaterThanOrEqualTo(2),
        reason: 'Accept all must reach the module');
    expect(dvMetaPixelConsentGranted('analytics'), isTrue);
    expect(dvMetaPixelConsentGranted('marketing'), isTrue);
  });

  test('a module started after DV.Analytics still hears it', () async {
    final DVAnalyticsRuntime runtime = DVAnalyticsRuntime.start(
        settings: settings(), database: MemoryDVDatabaseAdapter.new);
    await runtime.ready;
    int heard = 0;
    dvMetaPixelOnConsent(() => heard++);
    expect(heard, 1);
    await runtime.loadedConsent!.record(
      <DVConsentCategory, bool>{analytics: true},
      asked: <DVConsentCategory>{analytics},
      prompt: DVConsentPrompt.banner,
    );
    expect(heard, greaterThanOrEqualTo(2));
  });

  test('with no policy declared there is nothing to hear and nothing to '
      'wait for', () {
    int heard = 0;
    dvMetaPixelOnConsent(() => heard++);
    expect(heard, 0);
    expect(dvMetaPixelConsentGranted('analytics'), isTrue);
  });
}
