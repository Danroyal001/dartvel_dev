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

  // Where the browser follows anchors, it may follow only the ones a keyboard
  // or a screen reader activates. A pointer is Flutter's to read.
  //
  // Every DVNavLink renders a real anchor in the semantics tree, and on the
  // web that anchor is positioned by the semantics update rather than by the
  // compositor. Inside a scrolled sidebar it stayed where it had been drawn
  // before the scroll, so the element under the mouse was a different link
  // from the one on screen, and the browser followed that one: a click on
  // "Models" opened "Localization". The interceptor now cancels every pointer
  // click on a semantics anchor, as url_launcher's Link does, and the link
  // Flutter's own hit test found opens its destination itself.
  group('the browser follows the anchor', () {
    setUp(() {
      DVLinkOpener.install(
        (String path, {bool newTab = false}) {
          (newTab ? inNewTab : opened).add(path);
        },
        browserFollowsAnchors: true,
      );
    });

    testWidgets('a tapped external link opens itself', (tester) async {
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
      expect(inNewTab, isEmpty);
    });

    testWidgets('a middle click opens it beside, once', (tester) async {
      await pump(
        tester,
        const DVNavLink.external(
          'https://pub.dev/packages/dartvel_dev',
          child: DVText('pub.dev'),
        ),
      );

      final TestGesture gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse, buttons: kMiddleMouseButton);
      await gesture.down(tester.getCenter(find.text('pub.dev')));
      await gesture.up();
      await tester.pump();

      expect(inNewTab, <String>['https://pub.dev/packages/dartvel_dev']);
      expect(opened, isEmpty);
    });

    testWidgets('a screen reader activation is left to the anchor',
        (tester) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      await pump(
        tester,
        const DVNavLink.external(
          'https://pub.dev/packages/dartvel_dev',
          semanticLabel: 'Dartvel on pub.dev',
          child: DVText('pub.dev'),
        ),
      );

      tester.semantics.tap(find.semantics.byLabel('Dartvel on pub.dev'));
      await tester.pump();

      expect(opened, isEmpty);
      expect(inNewTab, isEmpty);
      semantics.dispose();
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
