// The consent banner and settings screen.
//
// Every failure worth a test here is a grant nobody made. A banner that
// records consent when it is closed, a screen that saves on the way out, a
// choice drawn before the stored answer was read and so offered again over
// it, a grant shown as saved when the database refused it, a tracking
// category granted on iOS without the App Tracking Transparency prompt: each
// looks like a working consent flow, so each is asserted directly.
import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const DVConsentCategory product = DVConsentCategory('product');
const DVConsentCategory marketing = DVConsentCategory('marketing');

DVAnalyticsSettings settings({String version = '2026-09-01'}) =>
    DVAnalyticsSettings.fromConfig(<String, Object?>{
      'consent': <String, Object?>{
        'version': version,
        'categories': <String, Object?>{
          'essential': <String, Object?>{'required': true},
          'product': <String, Object?>{'default': 'denied'},
          'marketing': <String, Object?>{'default': 'denied', 'tracking': true},
        },
      },
    });

/// A database whose consent writes can be made to fail.
class RefusingDatabase implements DVDatabaseAdapter {
  final MemoryDVDatabaseAdapter inner = MemoryDVDatabaseAdapter();
  bool refuseConsent = false;

  @override
  Future<int> execute(String sql, [List<Object?>? params]) {
    if (refuseConsent && sql.startsWith('INSERT INTO ${DVConsent.table}')) {
      throw StateError('the disk is full');
    }
    return inner.execute(sql, params);
  }

  @override
  Future<List<Map<String, Object?>>> query(String sql,
          [List<Object?>? params]) =>
      inner.query(sql, params);
}

Future<void> pumpApp(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

/// Lets the runtime's database work finish, which widget tests do not do on
/// their own: it is real asynchronous work, not a timer.
Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  await tester.pump();
}

Finder byKey(String key) => find.byKey(ValueKey<String>(key));

void main() {
  setUp(() {
    DVAnalyticsRuntime.resetForTest();
    DVPrivacyRuntime.resetForTest();
    DVConsentBanner.resetForTest();
    DVAppTrackingTransparency.applies = () => false;
    DVNativeBridge.unregister(DVAppTrackingTransparency.requestBinding);
  });

  group('the banner', () {
    testWidgets('is not shown before the stored consent has been read',
        (WidgetTester tester) async {
      final MemoryDVDatabaseAdapter db = MemoryDVDatabaseAdapter();
      final Completer<void> open = Completer<void>();
      final DVAnalyticsRuntime runtime = DVAnalyticsRuntime.start(
        settings: settings(),
        database: () async {
          await open.future;
          return db;
        },
      );
      await pumpApp(tester, DVConsentBanner(analytics: runtime, child: const Text('page')));
      expect(byKey('dv-consent-banner'), findsNothing,
          reason: 'a choice offered before the stored one is read is offered '
              'over it');
      await tester.runAsync(() async => open.complete());
      await settle(tester);
      expect(byKey('dv-consent-banner'), findsOneWidget);
      expect(find.text('page'), findsOneWidget);
    });

    testWidgets('closing it records nothing and grants nothing',
        (WidgetTester tester) async {
      final DVAnalyticsRuntime runtime = DVAnalyticsRuntime.start(
          settings: settings(), database: MemoryDVDatabaseAdapter.new);
      await pumpApp(tester, DVConsentBanner(analytics: runtime, child: const Text('page')));
      await settle(tester);

      await tester.tap(byKey('dv-consent-dismiss'));
      await settle(tester);

      expect(byKey('dv-consent-banner'), findsNothing);
      final DVConsent consent = runtime.loadedConsent!;
      expect(await tester.runAsync(consent.records), isEmpty,
          reason: 'closing the banner is not an answer');
      expect(consent.isGranted(product), isFalse);
      expect(consent.needsPrompt, isTrue);

      // And it stays closed for the rest of the session, on the next page
      // too, rather than coming back on every navigation.
      await pumpApp(tester, DVConsentBanner(analytics: runtime, child: const Text('next')));
      await settle(tester);
      expect(byKey('dv-consent-banner'), findsNothing);
    });

    testWidgets('accepting records a grant for each category it asked about',
        (WidgetTester tester) async {
      final DVAnalyticsRuntime runtime = DVAnalyticsRuntime.start(
          settings: settings(), database: MemoryDVDatabaseAdapter.new);
      await pumpApp(tester, DVConsentBanner(analytics: runtime, child: const Text('page')));
      await settle(tester);

      await tester.tap(byKey('dv-consent-accept-all'));
      await settle(tester);

      final DVConsent consent = runtime.loadedConsent!;
      expect(consent.isGranted(product), isTrue);
      expect(consent.isGranted(marketing), isTrue);
      final List<DVConsentRecord> records = (await tester.runAsync(consent.records))!;
      expect(records.single.prompt, DVConsentPrompt.banner);
      expect(records.single.asked, <String>{'product', 'marketing'});
      expect(byKey('dv-consent-banner'), findsNothing);
    });

    testWidgets('rejecting records a denial, which is an answer',
        (WidgetTester tester) async {
      final DVAnalyticsRuntime runtime = DVAnalyticsRuntime.start(
          settings: settings(), database: MemoryDVDatabaseAdapter.new);
      await pumpApp(tester, DVConsentBanner(analytics: runtime, child: const Text('page')));
      await settle(tester);

      await tester.tap(byKey('dv-consent-reject-all'));
      await settle(tester);

      final DVConsent consent = runtime.loadedConsent!;
      expect(consent.needsPrompt, isFalse);
      expect(consent.isGranted(product), isFalse);
      expect((await tester.runAsync(consent.records))!.single.answers,
          <String, bool>{'product': false, 'marketing': false});
    });

    testWidgets('a choice that could not be saved is not shown as made',
        (WidgetTester tester) async {
      final RefusingDatabase db = RefusingDatabase();
      final DVAnalyticsRuntime runtime =
          DVAnalyticsRuntime.start(settings: settings(), database: () => db);
      await pumpApp(tester, DVConsentBanner(analytics: runtime, child: const Text('page')));
      await settle(tester);
      db.refuseConsent = true;

      await tester.tap(byKey('dv-consent-accept-all'));
      await settle(tester);

      expect(runtime.loadedConsent!.isGranted(product), isFalse);
      expect(byKey('dv-consent-banner'), findsOneWidget);
      expect(byKey('dv-consent-not-saved'), findsOneWidget);
    });

    testWidgets('is not shown to somebody who answered this version',
        (WidgetTester tester) async {
      final MemoryDVDatabaseAdapter db = MemoryDVDatabaseAdapter();
      final DVAnalyticsRuntime first =
          DVAnalyticsRuntime.start(settings: settings(), database: () => db);
      final DVConsent consent = (await tester.runAsync(() => first.consent))!;
      await tester.runAsync(() => consent.record(<DVConsentCategory, bool>{product: true}));

      DVAnalyticsRuntime.resetForTest();
      final DVAnalyticsRuntime again =
          DVAnalyticsRuntime.start(settings: settings(), database: () => db);
      await pumpApp(tester, DVConsentBanner(analytics: again, child: const Text('page')));
      await settle(tester);
      expect(byKey('dv-consent-banner'), findsNothing);
    });

    testWidgets('asks again when the policy version changes',
        (WidgetTester tester) async {
      final MemoryDVDatabaseAdapter db = MemoryDVDatabaseAdapter();
      final DVAnalyticsRuntime first =
          DVAnalyticsRuntime.start(settings: settings(), database: () => db);
      final DVConsent consent = (await tester.runAsync(() => first.consent))!;
      await tester.runAsync(() => consent.record(<DVConsentCategory, bool>{product: true}));

      DVAnalyticsRuntime.resetForTest();
      final DVAnalyticsRuntime changed = DVAnalyticsRuntime.start(
          settings: settings(version: '2026-10-01'), database: () => db);
      await pumpApp(tester, DVConsentBanner(analytics: changed, child: const Text('page')));
      await settle(tester);
      expect(byKey('dv-consent-banner'), findsOneWidget);
      expect(changed.loadedConsent!.isGranted(product), isFalse,
          reason: 'an answer to last version is not consent to this one');
    });

    testWidgets('in an application with no analytics it is the page alone',
        (WidgetTester tester) async {
      await pumpApp(tester, const DVConsentBanner(child: Text('page')));
      await tester.pump();
      expect(find.text('page'), findsOneWidget);
      expect(byKey('dv-consent-banner'), findsNothing);
    });
  });

  group('the settings screen', () {
    testWidgets('shows each category as it stands, and the essential one fixed',
        (WidgetTester tester) async {
      final DVAnalyticsRuntime runtime = DVAnalyticsRuntime.start(
          settings: settings(), database: MemoryDVDatabaseAdapter.new);
      await pumpApp(tester, DVConsentSettingsPage(analytics: runtime));
      await settle(tester);

      Switch toggle(String name) =>
          tester.widget<Switch>(byKey('dv-consent-toggle-$name'));
      expect(toggle('essential').value, isTrue);
      expect(toggle('essential').onChanged, isNull);
      expect(toggle('product').value, isFalse);
      expect(toggle('marketing').value, isFalse);
    });

    testWidgets('changing a switch records nothing until saved',
        (WidgetTester tester) async {
      final DVAnalyticsRuntime runtime = DVAnalyticsRuntime.start(
          settings: settings(), database: MemoryDVDatabaseAdapter.new);
      await pumpApp(tester, DVConsentSettingsPage(analytics: runtime));
      await settle(tester);

      await tester.tap(byKey('dv-consent-toggle-product'));
      await settle(tester);
      final DVConsent consent = runtime.loadedConsent!;
      expect(consent.isGranted(product), isFalse);
      expect(await tester.runAsync(consent.records), isEmpty);

      await tester.tap(byKey('dv-consent-save'));
      await settle(tester);
      expect(consent.isGranted(product), isTrue);
      expect(consent.isGranted(marketing), isFalse);
      final DVConsentRecord record = (await tester.runAsync(consent.records))!.single;
      expect(record.prompt, DVConsentPrompt.settingsScreen);
      expect(record.answers, <String, bool>{'product': true, 'marketing': false});
    });

    testWidgets('a save the database refused says so and grants nothing',
        (WidgetTester tester) async {
      final RefusingDatabase db = RefusingDatabase();
      final DVAnalyticsRuntime runtime =
          DVAnalyticsRuntime.start(settings: settings(), database: () => db);
      await pumpApp(tester, DVConsentSettingsPage(analytics: runtime));
      await settle(tester);
      db.refuseConsent = true;

      await tester.tap(byKey('dv-consent-toggle-product'));
      await tester.tap(byKey('dv-consent-save'));
      await settle(tester);

      expect(runtime.loadedConsent!.isGranted(product), isFalse);
      expect(byKey('dv-consent-not-saved'), findsOneWidget);
    });

    testWidgets('is reachable as DV.Analytics.ConsentSettingsPage()',
        (WidgetTester tester) async {
      DVAnalyticsRuntime.start(
          settings: settings(), database: MemoryDVDatabaseAdapter.new);
      await pumpApp(tester, DV.Analytics.ConsentSettingsPage());
      await settle(tester);
      expect(byKey('dv-consent-save'), findsOneWidget);
    });
  });

  group('App Tracking Transparency', () {
    Future<DVAnalyticsRuntime> acceptAll(WidgetTester tester) async {
      final DVAnalyticsRuntime runtime = DVAnalyticsRuntime.start(
          settings: settings(), database: MemoryDVDatabaseAdapter.new);
      await pumpApp(tester, DVConsentBanner(analytics: runtime, child: const Text('page')));
      await settle(tester);
      await tester.tap(byKey('dv-consent-accept-all'));
      await settle(tester);
      return runtime;
    }

    testWidgets('a tracking category is granted only when the prompt allows it',
        (WidgetTester tester) async {
      DVAppTrackingTransparency.applies = () => true;
      int asked = 0;
      DVNativeBridge.register(DVAppTrackingTransparency.requestBinding,
          (Object? _) {
        asked++;
        return 2; // ATTrackingManagerAuthorizationStatusDenied
      });

      final DVAnalyticsRuntime runtime = await acceptAll(tester);
      final DVConsent consent = runtime.loadedConsent!;
      expect(asked, 1);
      expect(consent.isGranted(product), isTrue);
      expect(consent.isGranted(marketing), isFalse,
          reason: 'the system prompt said no; the banner does not overrule it');
      final List<DVConsentRecord> records = (await tester.runAsync(consent.records))!;
      expect(
        records.where((DVConsentRecord r) =>
            r.prompt == DVConsentPrompt.appTrackingTransparency),
        hasLength(1),
      );
    });

    testWidgets('allowed by the prompt, the tracking category is granted',
        (WidgetTester tester) async {
      DVAppTrackingTransparency.applies = () => true;
      DVNativeBridge.register(
          DVAppTrackingTransparency.requestBinding, (Object? _) => 3);
      final DVAnalyticsRuntime runtime = await acceptAll(tester);
      expect(runtime.loadedConsent!.isGranted(marketing), isTrue);
    });

    testWidgets('with no prompt to show, a tracking category stays denied',
        (WidgetTester tester) async {
      // iOS, and the binding did not load: nothing asked the system, so
      // nothing was allowed.
      DVAppTrackingTransparency.applies = () => true;
      final DVAnalyticsRuntime runtime = await acceptAll(tester);
      expect(runtime.loadedConsent!.isGranted(product), isTrue);
      expect(runtime.loadedConsent!.isGranted(marketing), isFalse);
    });

    testWidgets('off iOS the prompt is not involved',
        (WidgetTester tester) async {
      int asked = 0;
      DVNativeBridge.register(DVAppTrackingTransparency.requestBinding,
          (Object? _) {
        asked++;
        return 2;
      });
      final DVAnalyticsRuntime runtime = await acceptAll(tester);
      expect(asked, 0);
      expect(runtime.loadedConsent!.isGranted(marketing), isTrue);
    });
  });
}
