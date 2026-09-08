// Links that leave the site.
//
// DVNavLink only took a route target, so there was no way to write a link to
// GitHub or pub.dev. The dartvel.dev footer worked around it by styling text
// blue and never wiring anything up: it took a `url` argument and did not use
// it, so every footer link was dead by construction and looked exactly like a
// working one.
//
// An external link is a link. It needs a real anchor for a crawler and a
// screen reader, it needs to open, and it must not be routed -- the router has
// no route for another origin, and the interceptor already leaves other
// origins to the browser.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final opened = <String>[];
  final inNewTab = <String>[];

  setUp(() {
    opened.clear();
    inNewTab.clear();
    DVLinkOpener.install((String path, {bool newTab = false}) {
      (newTab ? inNewTab : opened).add(path);
    });
  });

  tearDown(DVLinkOpener.reset);

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
        MaterialApp(home: Scaffold(body: Center(child: child))),
      );

  testWidgets('it opens the address rather than routing', (tester) async {
    await pump(
      tester,
      const DVNavLink.external(
        'https://pub.dev/packages/dartvel_dev',
        child: DVText('pub.dev'),
      ),
    );

    await tester.tap(find.text('pub.dev'));
    await tester.pump();

    expect(opened, <String>['https://pub.dev/packages/dartvel_dev']);
  });

  testWidgets('it announces itself as a link to that address', (tester) async {
    // What a crawler follows and a screen reader reads out. The footer's
    // styled text announced nothing at all.
    final SemanticsHandle handle = tester.ensureSemantics();
    await pump(
      tester,
      const DVNavLink.external(
        'https://github.com/Danroyal001/dartvel_dev',
        child: DVText('GitHub'),
      ),
    );

    expect(
      tester.getSemantics(find.byType(DVNavLink)),
      isSemantics(isLink: true),
    );
    handle.dispose();
  });

  testWidgets('it takes keyboard focus and answers Enter', (tester) async {
    await pump(
      tester,
      const DVNavLink.external(
        'https://dartvel.dev',
        autofocus: true,
        child: DVText('Home'),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(opened, <String>['https://dartvel.dev']);
  });

  testWidgets('a disabled external link does nothing', (tester) async {
    await pump(
      tester,
      const DVNavLink.external(
        'https://dartvel.dev',
        enabled: false,
        child: DVText('Home'),
      ),
    );

    await tester.tap(find.text('Home'), warnIfMissed: false);
    await tester.pump();

    expect(opened, isEmpty);
  });

  testWidgets('following it replaces the page rather than opening a tab',
      (tester) async {
    // Two different intentions that used to be one function. A footer link
    // followed normally should replace the page; a middle click should not.
    await pump(
      tester,
      const DVNavLink.external('https://dartvel.dev', child: DVText('Home')),
    );

    await tester.tap(find.text('Home'));
    await tester.pump();

    expect(opened, <String>['https://dartvel.dev']);
    expect(inNewTab, isEmpty);
  });

  testWidgets('it previews nothing, because it cannot build another site',
      (tester) async {
    // A route preview renders the destination. There is no destination widget
    // for another origin, and a card that said nothing would be worse than no
    // card.
    await pump(
      tester,
      const DVNavLink.external('https://dartvel.dev', child: DVText('Home')),
    );

    final gesture =
        await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: tester.getCenter(find.text('Home')));
    addTearDown(gesture.removePointer);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));

    expect(find.byType(Card), findsNothing);
  });

  // Where the browser follows anchors itself, the widget must not open the
  // link as well.
  //
  // Every DVNavLink renders a real anchor in the semantics tree, and on the
  // web the browser activates that anchor on the same click the widget sees.
  // While both went to the same address in the same tab that was invisible --
  // two navigations to one place look like one. It stops being invisible the
  // moment either of them opens a tab: a middle click opened two, and an
  // external link marked to open beside would open one tab and send the page
  // the reader was on to the same address.
  group('the browser follows the anchor', () {
    setUp(() {
      DVLinkOpener.install(
        (String path, {bool newTab = false}) {
          (newTab ? inNewTab : opened).add(path);
        },
        browserFollowsAnchors: true,
      );
    });

    testWidgets('an external link is left to it', (tester) async {
      await pump(
        tester,
        const DVNavLink.external(
          'https://pub.dev/packages/dartvel_dev',
          child: DVText('pub.dev'),
        ),
      );

      await tester.tap(find.text('pub.dev'));
      await tester.pump();

      expect(opened, isEmpty);
      expect(inNewTab, isEmpty);
    });

    testWidgets('a middle click is left to it', (tester) async {
      await pump(
        tester,
        const DVNavLink.external(
          'https://pub.dev/packages/dartvel_dev',
          child: DVText('pub.dev'),
        ),
      );

      final TestGesture gesture =
          await tester.createGesture(buttons: kMiddleMouseButton);
      await gesture.down(tester.getCenter(find.text('pub.dev')));
      await gesture.up();
      await tester.pump();

      expect(inNewTab, isEmpty);
    });
  });

  // Off the web there is no anchor and no browser, so the widget is the only
  // thing that can open anything.
  testWidgets('without one, the widget opens it', (tester) async {
    await pump(
      tester,
      const DVNavLink.external(
        'https://pub.dev/packages/dartvel_dev',
        child: DVText('pub.dev'),
      ),
    );

    await tester.tap(find.text('pub.dev'));
    await tester.pump();

    expect(opened, <String>['https://pub.dev/packages/dartvel_dev']);
  });
}
