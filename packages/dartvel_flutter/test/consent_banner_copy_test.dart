// The consent banner an ad-funded site can ship as it is.
//
// NDPR and GDPR ask the same three things of it: the site's own words and a
// link to its privacy policy, rejecting as easy as accepting, and a choice
// that is a choice. The silent failures are visual: a Reject button drawn
// smaller or greyer than Accept, a banner that covers the page's own call to
// action on a phone, a control a screen reader cannot name.
import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DVAnalyticsSettings settings({Map<String, Object?>? banner}) =>
    DVAnalyticsSettings.fromConfig(<String, Object?>{
      'consent': <String, Object?>{
        'version': '2026-11-18',
        'categories': <String, Object?>{
          'essential': <String, Object?>{'required': true},
          'analytics': <String, Object?>{'default': 'denied'},
          'marketing': <String, Object?>{'default': 'denied'},
        },
        'banner': ?banner,
      },
    });

Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)));
  await tester.pump();
}

Finder byKey(String key) => find.byKey(ValueKey<String>(key));

Color? fillOf(WidgetTester tester, String label) {
  final Finder box = find.ancestor(
      of: find.text(label), matching: find.byType(DecoratedBox));
  final DecoratedBox decorated = tester.widget<DecoratedBox>(box.first);
  return (decorated.decoration as BoxDecoration).color;
}

void main() {
  setUp(() {
    DVAnalyticsRuntime.resetForTest();
    DVConsentBanner.resetForTest();
    DVAppTrackingTransparency.applies = () => false;
  });

  Future<DVAnalyticsRuntime> pump(WidgetTester tester,
      {Map<String, Object?>? banner, Size size = const Size(390, 844)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final DVAnalyticsRuntime runtime = DVAnalyticsRuntime.start(
        settings: settings(banner: banner),
        database: MemoryDVDatabaseAdapter.new);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DVConsentBanner(
          analytics: runtime,
          child: const Align(
            alignment: Alignment(0, -0.2),
            child: Text('Book a call', key: ValueKey<String>('main-cta')),
          ),
        ),
      ),
    ));
    await settle(tester);
    return runtime;
  }

  testWidgets('says what the application configured, with its privacy link',
      (WidgetTester tester) async {
    await pump(tester, banner: <String, Object?>{
      'title': 'We value your privacy',
      'body': 'We use cookies to see which ads bring visitors.',
      'privacyUrl': 'https://example.com/privacy',
      'privacyLabel': 'Read our privacy policy',
    });
    expect(find.text('We value your privacy'), findsOneWidget);
    expect(find.text('We use cookies to see which ads bring visitors.'),
        findsOneWidget);
    expect(find.text('Read our privacy policy'), findsOneWidget);
    expect(
        find.ancestor(
            of: find.text('Read our privacy policy'),
            matching: find.byType(DVNavLink)),
        findsOneWidget,
        reason: 'a real link: a screen reader announces it and Enter opens it');
  });

  testWidgets('without configuration it names the categories it asks about',
      (WidgetTester tester) async {
    await pump(tester);
    expect(find.text('Your privacy choices'), findsOneWidget);
    expect(find.textContaining('Analytics, Marketing'), findsOneWidget);
  });

  testWidgets('Accept all, Reject all and Settings carry equal weight',
      (WidgetTester tester) async {
    await pump(tester);
    for (final String label in <String>['Accept all', 'Reject all', 'Settings']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    final Color? accept = fillOf(tester, 'Accept all');
    expect(fillOf(tester, 'Reject all'), accept);
    expect(fillOf(tester, 'Settings'), accept);
    final double height = tester.getSize(byKey('dv-consent-accept-all')).height;
    expect(tester.getSize(byKey('dv-consent-reject-all')).height, height);
    expect(tester.getSize(byKey('dv-consent-choose')).height, height);
  });

  testWidgets('labels are configurable', (WidgetTester tester) async {
    await pump(tester, banner: <String, Object?>{
      'acceptLabel': 'Allow',
      'rejectLabel': 'Refuse',
      'settingsLabel': 'Choose',
    });
    expect(find.text('Allow'), findsOneWidget);
    expect(find.text('Refuse'), findsOneWidget);
    expect(find.text('Choose'), findsOneWidget);
  });

  testWidgets('every control has a tooltip that is its name',
      (WidgetTester tester) async {
    await pump(tester);
    for (final String label in <String>[
      'Accept all',
      'Reject all',
      'Settings',
      'Close',
    ]) {
      expect(find.byTooltip(label), findsOneWidget, reason: label);
    }
    expect(find.bySemanticsLabel('Close'), findsWidgets);
  });

  testWidgets('on a 390 px phone it is a compact sheet that leaves the page\'s '
      'call to action uncovered', (WidgetTester tester) async {
    await pump(tester, banner: <String, Object?>{
      'title': 'We value your privacy',
      'body': 'We use cookies to see which ads bring visitors to this site, '
          'and nothing is collected until you choose.',
      'privacyUrl': '/privacy',
    });
    expect(tester.takeException(), isNull, reason: 'no overflow at 390 px');
    final Rect sheet = tester.getRect(byKey('dv-consent-banner'));
    final Rect cta = tester.getRect(byKey('main-cta'));
    expect(sheet.bottom, 844);
    expect(sheet.height, lessThan(844 * 0.4));
    expect(sheet.overlaps(cta), isFalse);
  });

  testWidgets('follows the app theme, dark included', (WidgetTester tester) async {
    final DVAnalyticsRuntime runtime = DVAnalyticsRuntime.start(
        settings: settings(), database: MemoryDVDatabaseAdapter.new);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: Scaffold(body: DVConsentBanner(analytics: runtime, child: const SizedBox())),
    ));
    await settle(tester);
    final ColorScheme scheme =
        ThemeData(brightness: Brightness.dark).colorScheme;
    final DecoratedBox sheet = tester.widget<DecoratedBox>(find
        .descendant(
            of: byKey('dv-consent-banner'), matching: find.byType(DecoratedBox))
        .first);
    expect((sheet.decoration as BoxDecoration).color, scheme.surface);
  });
}
