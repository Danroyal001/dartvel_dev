// Consent in a browser outlives the page.
//
// On the web the analytics database was the in-memory one, so every page
// load started with no answer on record and the banner asked again -- on
// every visit, on every reload, after the visitor had already said yes or
// no. Worse than annoying: a visitor who rejected and reloaded was asked
// again as if they never had, which is not what NDPR or GDPR call a choice.
//
// The browser keeps the consent records and the install id in IndexedDB,
// through the same snapshot store offline data models use. It keeps nothing
// else: the event outbox stays in memory, because rewriting a growing table
// into IndexedDB on every tracked event would cost the page more than the
// event is worth.
import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_core/src/analytics/local_database_snapshots.dart';
import 'package:dartvel_core/src/data/offline_database.dart';
import 'package:test/test.dart';

/// IndexedDB without a browser: what was written, by table.
class FakeSnapshots implements DVTableSnapshots {
  final Map<String, String> tables = <String, String>{};

  @override
  Future<Map<String, String>> readAll() async =>
      Map<String, String>.of(tables);

  @override
  Future<void> write(String table, String snapshot) async =>
      tables[table] = snapshot;

  @override
  Future<void> remove(String table) async => tables.remove(table);
}

const DVConsentCategory analytics = DVConsentCategory('analytics');
const DVConsentCategory marketing = DVConsentCategory('marketing');

DVAnalyticsSettings settings({String version = '2026-11-18'}) =>
    DVAnalyticsSettings.fromConfig(<String, Object?>{
      'consent': <String, Object?>{
        'version': version,
        'categories': <String, Object?>{
          'essential': <String, Object?>{'required': true},
          'analytics': <String, Object?>{'default': 'denied'},
          'marketing': <String, Object?>{
            'default': 'denied',
            'tracking': true,
          },
        },
      },
    });

class PageRead extends DVAnalyticsEvent {
  const PageRead();
  @override
  String get name => 'page_read';
  @override
  DVConsentCategory get category => analytics;
}

/// A page load: a fresh runtime over whatever the browser kept.
Future<DVAnalyticsRuntime> load(FakeSnapshots kept,
    {String version = '2026-11-18'}) async {
  DVAnalyticsRuntime.resetForTest();
  final DVAnalyticsRuntime runtime = DVAnalyticsRuntime.start(
    settings: settings(version: version),
    database: () => dvAnalyticsSnapshotDatabase(kept),
  );
  await runtime.ready;
  return runtime;
}

void main() {
  tearDown(DVAnalyticsRuntime.resetForTest);

  test('a choice made on one page load is still made on the next', () async {
    final FakeSnapshots browser = FakeSnapshots();
    final DVAnalyticsRuntime first = await load(browser);
    expect(first.loadedConsent!.needsPrompt, isTrue);
    expect(
      await first.loadedConsent!.record(
        <DVConsentCategory, bool>{analytics: true, marketing: false},
        asked: <DVConsentCategory>{analytics, marketing},
        prompt: DVConsentPrompt.banner,
      ),
      isTrue,
    );

    final DVAnalyticsRuntime second = await load(browser);
    final DVConsent consent = second.loadedConsent!;
    expect(consent.needsPrompt, isFalse,
        reason: 'the banner must not ask again on the next page load');
    expect(consent.isGranted(analytics), isTrue);
    expect(consent.isGranted(marketing), isFalse);
  });

  test('a rejection is remembered too, not only a grant', () async {
    final FakeSnapshots browser = FakeSnapshots();
    final DVAnalyticsRuntime first = await load(browser);
    await first.loadedConsent!.record(
      <DVConsentCategory, bool>{analytics: false, marketing: false},
      asked: <DVConsentCategory>{analytics, marketing},
      prompt: DVConsentPrompt.banner,
    );
    final DVConsent consent = (await load(browser)).loadedConsent!;
    expect(consent.needsPrompt, isFalse);
    expect(consent.isGranted(analytics), isFalse);
  });

  test('a withdrawal on a later page load stays withdrawn', () async {
    final FakeSnapshots browser = FakeSnapshots();
    await (await load(browser)).loadedConsent!.record(
      <DVConsentCategory, bool>{analytics: true, marketing: true},
      asked: <DVConsentCategory>{analytics, marketing},
      prompt: DVConsentPrompt.banner,
    );
    await (await load(browser)).loadedConsent!.record(
      <DVConsentCategory, bool>{marketing: false},
      asked: <DVConsentCategory>{marketing},
      prompt: DVConsentPrompt.settingsScreen,
    );
    final DVConsent consent = (await load(browser)).loadedConsent!;
    expect(consent.isGranted(marketing), isFalse);
    expect(consent.isGranted(analytics), isTrue);
  });

  test('a new policy version asks again, kept records or not', () async {
    final FakeSnapshots browser = FakeSnapshots();
    await (await load(browser)).loadedConsent!.record(
      <DVConsentCategory, bool>{analytics: true, marketing: true},
      asked: <DVConsentCategory>{analytics, marketing},
      prompt: DVConsentPrompt.banner,
    );
    final DVConsent consent =
        (await load(browser, version: '2026-12-01')).loadedConsent!;
    expect(consent.needsPrompt, isTrue);
  });

  test('the install id is the same visitor across page loads', () async {
    final FakeSnapshots browser = FakeSnapshots();
    final String first = (await load(browser)).loadedConsent!.installId;
    final String second = (await load(browser)).loadedConsent!.installId;
    expect(second, first);
  });

  test('only consent and identity are kept; events stay in memory', () async {
    final FakeSnapshots browser = FakeSnapshots();
    final DVAnalyticsRuntime runtime = await load(browser);
    await runtime.loadedConsent!.record(
      <DVConsentCategory, bool>{analytics: true},
      asked: <DVConsentCategory>{analytics},
      prompt: DVConsentPrompt.banner,
    );
    final DVTrackResult tracked = await runtime.track(const PageRead());
    expect(tracked.accepted, isTrue);
    expect(browser.tables.keys.toSet(),
        <String>{DVConsent.table, DVAnalytics.identityTable});
  });
}
