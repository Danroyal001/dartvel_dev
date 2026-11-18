// Every Dartvel page keeps its content inside the safe area with no app code
// (owner, 18 Nov 2026, over a phone screenshot of the Dev Launcher's app
// drawer: "DVPages should be safe area by default, 'Z' is digging into the
// system nav bar").
//
// The shell already wrapped every page in a SafeArea, so a list or a column
// stayed clear of the bars. What leaked was the screen size: inside the
// SafeArea, MediaQuery still reported the whole window while its padding read
// zero, so a page that sized itself from the screen -- a letter index of 27
// equal cells, a hero as tall as the screen -- was exactly the insets too big
// and ran under the navigation bar. Inside a page, the screen is the page's
// safe box: its size, with no padding left to subtract.
//
// And on the web, where Flutter reports no insets at all, the browser's
// env(safe-area-inset-*) reaches the app, so a notched phone or an installed
// PWA keeps content out from under the notch and the home indicator.
import 'dart:async';

import 'package:dartvel_core/dartvel.dart' show DVPageShellMode;
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/display/browser_safe_area.dart';
import 'package:dartvel_flutter/src/widgets/page_viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A phone: 400 x 800, a 24-point status bar and a 48-point three-button
/// navigation bar, drawn edge to edge as Android 15 requires.
void phone(WidgetTester tester, {FakeViewPadding insets = const FakeViewPadding(top: 24, bottom: 48)}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(400, 800);
  tester.view.padding = insets;
  tester.view.viewPadding = insets;
  addTearDown(tester.view.reset);
}

const List<String> letters = <String>[
  '#', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', //
  'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
];

/// The Dev Launcher's drawer, reduced: a letter index down the right edge
/// whose cells share the screen's height, written the way an app writes it
/// -- from the screen's size, less the insets the screen reports.
class SideIndexPage extends StatelessWidget {
  const SideIndexPage({super.key});

  @override
  Widget build(BuildContext context) {
    final Size screen = MediaQuery.sizeOf(context);
    final EdgeInsets insets = MediaQuery.paddingOf(context);
    final double top = insets.top + 8;
    final double cell = (screen.height - top - 16 - insets.bottom) / letters.length;
    return Stack(
      children: <Widget>[
        Positioned(
          right: insets.right,
          top: top,
          width: 30,
          height: cell * letters.length,
          child: Column(
            children: <Widget>[
              for (final String letter in letters) Expanded(child: Center(child: Text(letter))),
            ],
          ),
        ),
      ],
    );
  }
}

/// A full-width strip sized from the screen's width, as a carousel is.
class FullWidthStripPage extends StatelessWidget {
  const FullWidthStripPage({super.key});

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width - MediaQuery.paddingOf(context).horizontal;
    // Positioned, as a side index is, so the width it asks for is the width
    // it gets: an Align would quietly clamp it and hide the overflow.
    return Stack(
      children: <Widget>[
        Positioned(
          left: 0,
          top: 0,
          width: width,
          height: 40,
          child: const Align(alignment: Alignment.centerRight, child: Text('end')),
        ),
      ],
    );
  }
}

/// A long list the page scrolls itself.
Widget longList() => ListView(
      children: <Widget>[
        for (int row = 0; row < 40; row++) SizedBox(height: 50, child: Text('Row $row')),
        const SizedBox(height: 50, child: Text('Last row')),
      ],
    );

Widget app(Widget page, {DVPageScaffoldSpec spec = const DVPageScaffoldSpec(title: 'Page')}) =>
    MaterialApp(home: DVPageShell(spec: spec, child: page));

void main() {
  setUp(DVPageScrollMemory.reset);
  tearDown(() {
    DVPageScrollMemory.reset();
    DVBrowserSafeArea.insets.value = EdgeInsets.zero;
  });

  group('a page stays clear of the system bars with no app code', () {
    testWidgets('a side index sized from the screen ends above the navigation bar',
        (WidgetTester tester) async {
      phone(tester);
      await tester.pumpWidget(app(const SideIndexPage()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getRect(find.text('#')).top, greaterThanOrEqualTo(24));
      expect(tester.getRect(find.text('Z')).bottom, lessThanOrEqualTo(800 - 48));
    });

    testWidgets('and under an app bar too', (WidgetTester tester) async {
      phone(tester);
      await tester.pumpWidget(app(
        const SideIndexPage(),
        spec: const DVPageScaffoldSpec(title: 'Page', showAppBar: true),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getRect(find.text('Z')).bottom, lessThanOrEqualTo(800 - 48));
    });

    testWidgets('on the Cupertino shell too', (WidgetTester tester) async {
      phone(tester, insets: const FakeViewPadding(top: 47, bottom: 34));
      await tester.pumpWidget(app(
        const SideIndexPage(),
        spec: const DVPageScaffoldSpec(title: 'Page', shell: DVPageShellMode.cupertino),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getRect(find.text('#')).top, greaterThanOrEqualTo(47));
      expect(tester.getRect(find.text('Z')).bottom, lessThanOrEqualTo(800 - 34));
    });

    testWidgets('the last row of a full-height list scrolls to above the navigation bar',
        (WidgetTester tester) async {
      phone(tester);
      await tester.pumpWidget(app(longList()));
      await tester.pumpAndSettle();
      await tester.drag(find.text('Row 3'), const Offset(0, -5000));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('Last row')).bottom, lessThanOrEqualTo(800 - 48));
    });

    testWidgets('a long page the shell scrolls ends above the navigation bar',
        (WidgetTester tester) async {
      phone(tester);
      await tester.pumpWidget(app(Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (int row = 0; row < 40; row++) SizedBox(height: 50, child: Text('Row $row')),
          const SizedBox(height: 50, child: Text('The end')),
        ],
      )));
      await tester.pumpAndSettle();
      await tester.drag(find.text('Row 3'), const Offset(0, -5000));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('The end')).bottom, lessThanOrEqualTo(800 - 48));
      expect(tester.getRect(find.text('The end')).top, greaterThanOrEqualTo(24));
    });

    testWidgets('a notch on the side in landscape: a full-width strip stops short of it',
        (WidgetTester tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 400);
      const FakeViewPadding cutout = FakeViewPadding(left: 44, right: 44, bottom: 21);
      tester.view.padding = cutout;
      tester.view.viewPadding = cutout;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(const FullWidthStripPage()));
      await tester.pumpAndSettle();
      final Rect end = tester.getRect(find.text('end'));
      expect(end.right, lessThanOrEqualTo(800 - 44));
      expect(tester.getRect(find.byType(FullWidthStripPage)).left, greaterThanOrEqualTo(44));
    });

    testWidgets('the page reads the safe box as its screen, with no insets left',
        (WidgetTester tester) async {
      phone(tester);
      late Size screen;
      late EdgeInsets insets;
      await tester.pumpWidget(app(Builder(builder: (BuildContext context) {
        screen = MediaQuery.sizeOf(context);
        insets = MediaQuery.paddingOf(context);
        return const SizedBox.expand();
      })));
      await tester.pumpAndSettle();
      expect(screen, const Size(400, 800 - 24 - 48));
      expect(insets, EdgeInsets.zero);
    });

    testWidgets('the loading bar sits below the status bar, not under it',
        (WidgetTester tester) async {
      phone(tester);
      await tester.pumpWidget(app(const Text('page')));
      final VoidCallback done = DV.progress.start();
      addTearDown(done);
      await tester.pump();
      expect(tester.getRect(find.byType(DVTopProgressBar)).top, greaterThanOrEqualTo(24));
    });

    testWidgets("a layout's footer on a short page sits above the navigation bar",
        (WidgetTester tester) async {
      phone(tester);
      await tester.pumpWidget(app(const _FooterLayout(child: Text('short page'))));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('footer')).bottom, lessThanOrEqualTo(800 - 48));
    });
  });

  group('a page can opt out for full-bleed content', () {
    testWidgets('safeArea: false draws from the very top and keeps the insets readable',
        (WidgetTester tester) async {
      phone(tester);
      late EdgeInsets insets;
      late Size screen;
      await tester.pumpWidget(app(
        Builder(builder: (BuildContext context) {
          insets = MediaQuery.paddingOf(context);
          screen = MediaQuery.sizeOf(context);
          return const Align(alignment: Alignment.topLeft, child: Text('full bleed'));
        }),
        spec: const DVPageScaffoldSpec(title: 'Page', safeArea: false),
      ));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('full bleed')).top, 0);
      expect(insets, const EdgeInsets.only(top: 24, bottom: 48));
      expect(screen, const Size(400, 800));
    });
  });

  group('on the web, the browser safe-area insets reach the app', () {
    // Flutter's web engine reports no padding at all, while Dartvel's
    // viewport meta asks for viewport-fit=cover: on a notched iPhone the page
    // ran under the notch and the home indicator. The browser knows the
    // insets as env(safe-area-inset-*); DV.run hands them to MediaQuery.
    Widget webApp(Widget page) => DVBrowserSafeArea(
          child: MaterialApp(
            home: DVPageShell(spec: const DVPageScaffoldSpec(title: 'Page'), child: page),
          ),
        );

    testWidgets('a page stays below the notch and above the home indicator',
        (WidgetTester tester) async {
      phone(tester, insets: FakeViewPadding.zero);
      DVBrowserSafeArea.insets.value = const EdgeInsets.only(top: 47, bottom: 34);
      await tester.pumpWidget(webApp(const SideIndexPage()));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('#')).top, greaterThanOrEqualTo(47));
      expect(tester.getRect(find.text('Z')).bottom, lessThanOrEqualTo(800 - 34));
    });

    testWidgets('they follow a rotation', (WidgetTester tester) async {
      phone(tester, insets: FakeViewPadding.zero);
      DVBrowserSafeArea.insets.value = const EdgeInsets.only(top: 47, bottom: 34);
      await tester.pumpWidget(webApp(const SideIndexPage()));
      await tester.pumpAndSettle();
      DVBrowserSafeArea.insets.value = const EdgeInsets.only(left: 47, right: 47, bottom: 21);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('#')).top, lessThan(47));
      expect(tester.getRect(find.text('Z')).bottom, lessThanOrEqualTo(800 - 21));
      expect(tester.getRect(find.text('Z')).right, lessThanOrEqualTo(400 - 47));
    });

    testWidgets('sheets and dialogs over the page see them too', (WidgetTester tester) async {
      phone(tester, insets: FakeViewPadding.zero);
      DVBrowserSafeArea.insets.value = const EdgeInsets.only(top: 47, bottom: 34);
      late BuildContext pageContext;
      await tester.pumpWidget(webApp(Builder(builder: (BuildContext context) {
        pageContext = context;
        return const SizedBox.expand();
      })));
      await tester.pumpAndSettle();
      late EdgeInsets sheetInsets;
      unawaited(showModalBottomSheet<void>(
        context: pageContext,
        builder: (BuildContext context) {
          sheetInsets = MediaQuery.paddingOf(Navigator.of(context).context);
          return const SafeArea(child: Text('sheet'));
        },
      ));
      await tester.pumpAndSettle();
      expect(sheetInsets.bottom, 34);
      expect(tester.getRect(find.text('sheet')).bottom, lessThanOrEqualTo(800 - 34));
    });

    testWidgets('an engine that does report insets is not padded twice',
        (WidgetTester tester) async {
      phone(tester, insets: const FakeViewPadding(top: 47, bottom: 34));
      DVBrowserSafeArea.insets.value = const EdgeInsets.only(top: 47, bottom: 34);
      late EdgeInsets seen;
      await tester.pumpWidget(DVBrowserSafeArea(
        child: Builder(builder: (BuildContext context) {
          seen = MediaQuery.paddingOf(context);
          return const SizedBox();
        }),
      ));
      expect(seen, const EdgeInsets.only(top: 47, bottom: 34));
    });
  });
}

class _FooterLayout extends DartvelLayout {
  const _FooterLayout({required super.child});

  @override
  Widget? get footer => const SizedBox(height: 40, child: Text('footer'));
}
