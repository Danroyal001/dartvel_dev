// The consent banner sits at the bottom of the screen over any page.
//
// It was placed inside the page, under the layout and the page shell's own
// scroll view. On a real site -- a layout with a header, the page, a footer,
// all inside a scroll view -- the banner's stack was sized to the content,
// so the banner was drawn at the end of the page content, scrolled out of
// sight, and nobody ever answered it: every default-denied category stayed
// denied and no analytics module ever loaded. The build-time capture held
// its text, so nothing looked wrong until somebody looked at the screen.
import 'package:dartvel_core/dartvel.dart';
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

DVAnalyticsSettings settings() => DVAnalyticsSettings.fromConfig(<String, Object?>{
      'consent': <String, Object?>{
        'version': '2026-11-18',
        'categories': <String, Object?>{
          'essential': <String, Object?>{'required': true},
          'analytics': <String, Object?>{'default': 'denied'},
        },
      },
    });

Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)));
  await tester.pump();
  await tester.pump();
}

/// A site's layout: a header, the page, a long footer, in its own scroll
/// view, as sigmadev.digital's _layout is.
class SiteLayout extends StatelessWidget {
  const SiteLayout({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        child: Column(
          children: <Widget>[
            const SizedBox(height: 80, child: Text('Header')),
            child,
            const SizedBox(height: 1200, child: Text('Footer')),
          ],
        ),
      );
}

void main() {
  setUp(() {
    DVAnalyticsRuntime.resetForTest();
    DVConsentBanner.resetForTest();
    DVAppTrackingTransparency.applies = () => false;
  });

  Future<void> pumpPage(WidgetTester tester, {bool scroll = true}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    DVAnalyticsRuntime.start(
        settings: settings(), database: MemoryDVDatabaseAdapter.new);
    await tester.pumpWidget(MaterialApp(
      home: DVPageShell(
        spec: DVPageScaffoldSpec(title: 'Home', scroll: scroll),
        child: const SiteLayout(
          child: SizedBox(height: 900, child: Text('Page')),
        ),
      ),
    ));
    await settle(tester);
  }

  testWidgets('a page inside a layout\'s scroll view: the banner is at the '
      'bottom of the screen, on screen', (WidgetTester tester) async {
    await pumpPage(tester);
    final Finder banner = find.byKey(const ValueKey<String>('dv-consent-banner'));
    expect(banner, findsOneWidget);
    final Rect rect = tester.getRect(banner);
    expect(rect.bottom, 844, reason: 'the banner ends at the screen\'s bottom');
    expect(rect.top, greaterThan(0));
    expect(find.text('Accept all').hitTestable(), findsOneWidget,
        reason: 'it can be tapped where it is');
  });

  testWidgets('it stays there when the page scrolls', (WidgetTester tester) async {
    await pumpPage(tester);
    await tester.drag(find.text('Header'), const Offset(0, -600));
    await tester.pump();
    final Rect rect = tester.getRect(
        find.byKey(const ValueKey<String>('dv-consent-banner')));
    expect(rect.bottom, 844);
  });

  testWidgets('a page the shell scrolls itself, no layout scroll view',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    DVAnalyticsRuntime.start(
        settings: settings(), database: MemoryDVDatabaseAdapter.new);
    await tester.pumpWidget(const MaterialApp(
      home: DVPageShell(
        spec: DVPageScaffoldSpec(title: 'Home'),
        child: Column(children: <Widget>[
          SizedBox(height: 2000, child: Text('Tall page')),
        ]),
      ),
    ));
    await settle(tester);
    final Rect rect = tester.getRect(
        find.byKey(const ValueKey<String>('dv-consent-banner')));
    expect(rect.bottom, 844);
  });

  testWidgets('answered, it is gone and the page is untouched',
      (WidgetTester tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('Reject all'));
    await settle(tester);
    expect(find.byKey(const ValueKey<String>('dv-consent-banner')), findsNothing);
    expect(find.text('Page'), findsOneWidget);
  });

  testWidgets('an application with no analytics gets no banner and the same '
      'page', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
      home: DVPageShell(
        spec: DVPageScaffoldSpec(title: 'Home'),
        child: SiteLayout(child: Text('Page')),
      ),
    ));
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('dv-consent-banner')), findsNothing);
    expect(find.text('Page'), findsOneWidget);
  });

  // Owner, 19 Nov 2026 (sigmadev.digital at phone width): the banner's three
  // buttons sat at three natural widths with a gap on the right. They share
  // the banner's width, one edge each side, labels centred; on a screen too
  // narrow for three side by side they stack, each the full width.
  const List<String> buttons = <String>['dv-consent-accept-all', 'dv-consent-reject-all', 'dv-consent-choose'];
  Rect rectOf(WidgetTester tester, String key) => tester.getRect(find.byKey(ValueKey<String>(key)));

  Future<void> pumpAt(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    DVAnalyticsRuntime.start(settings: settings(), database: MemoryDVDatabaseAdapter.new);
    await tester.pumpWidget(MaterialApp(
      home: DVPageShell(
        spec: const DVPageScaffoldSpec(title: 'Home'),
        child: const SiteLayout(child: SizedBox(height: 900, child: Text('Page'))),
      ),
    ));
    await settle(tester);
  }

  void expectLabelsCentred(WidgetTester tester) {
    for (final String key in buttons) {
      final Rect button = rectOf(tester, key);
      final Rect label = tester.getRect(find.descendant(of: find.byKey(ValueKey<String>(key)), matching: find.byType(Text)).first);
      expect(label.center.dx, moreOrLessEquals(button.center.dx, epsilon: 1), reason: '$key label centred');
    }
  }

  testWidgets('on a phone the banner buttons share its width in one row', (WidgetTester tester) async {
    await pumpAt(tester, 390);
    // The banner's content sits 16 px inside its edges.
    final Rect banner = tester.getRect(find.byKey(const ValueKey<String>('dv-consent-banner')));
    final List<Rect> rects = <Rect>[for (final String key in buttons) rectOf(tester, key)];
    expect(rects.first.left, moreOrLessEquals(banner.left + 16, epsilon: 0.5), reason: 'starts at the content edge');
    expect(rects.last.right, moreOrLessEquals(banner.right - 16, epsilon: 0.5), reason: 'ends at the other content edge');
    for (final Rect rect in rects) {
      expect(rect.top, moreOrLessEquals(rects.first.top, epsilon: 0.5), reason: 'one row');
      expect(rect.width, moreOrLessEquals(rects.first.width, epsilon: 0.5), reason: 'one width');
      expect(rect.height, moreOrLessEquals(rects.first.height, epsilon: 0.5), reason: 'one height');
    }
    expectLabelsCentred(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('on a very narrow screen they stack, each the full width', (WidgetTester tester) async {
    await pumpAt(tester, 280);
    final List<Rect> rects = <Rect>[for (final String key in buttons) rectOf(tester, key)];
    for (final (int i, Rect rect) in rects.indexed) {
      expect(rect.left, moreOrLessEquals(rects.first.left, epsilon: 0.5));
      expect(rect.right, moreOrLessEquals(rects.first.right, epsilon: 0.5));
      if (i > 0) expect(rect.top, greaterThan(rects[i - 1].bottom - 0.5), reason: 'stacked');
    }
    expect(rects.first.width, greaterThan(280 - 2 * 20));
    expectLabelsCentred(tester);
    expect(tester.takeException(), isNull);
  });
}
