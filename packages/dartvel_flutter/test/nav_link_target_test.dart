// Owner, 20 Nov 2026, on sigmadev.digital: the Tools link in the header and
// footer opened tools.sigmadev.digital in a new tab, and the subdomains should
// feel like one site; "DVLink should give options for these". The site had
// installed its own link opener to force tabs, because the framework gave a
// link no way to say where it opens.
//
// `target:` on DVNavLink and DVNavLink.external says it: auto (what a link
// did before: a route or a host of dartvel.hosts in this tab), sameTab, or
// newTab. It holds for a pointer, for Enter, and for a screen reader's
// activation of the anchor, which the web interceptor reads from the links on
// screen.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/routing/link_interception.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final opened = <String>[];
  final inNewTab = <String>[];

  setUp(() {
    opened.clear();
    inNewTab.clear();
    DVLinkTargets.reset();
    DVLinkOpener.install((String path, {bool newTab = false}) {
      (newTab ? inNewTab : opened).add(path);
    });
  });

  tearDown(DVLinkOpener.reset);

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
        MaterialApp(home: Scaffold(body: Center(child: child))),
      );

  group('a pointer', () {
    testWidgets('an external link with target newTab opens beside the page', (tester) async {
      await pump(tester, const DVNavLink.external('https://pub.dev', target: DVLinkTarget.newTab, child: DVText('pub.dev')));
      await tester.tap(find.text('pub.dev'));
      await tester.pump();
      expect(inNewTab, <String>['https://pub.dev']);
      expect(opened, isEmpty);
    });

    testWidgets('an external link with target sameTab replaces the page', (tester) async {
      await pump(tester, const DVNavLink.external('https://tools.example.com/', target: DVLinkTarget.sameTab, child: DVText('Tools')));
      await tester.tap(find.text('Tools'));
      await tester.pump();
      expect(opened, <String>['https://tools.example.com/']);
      expect(inNewTab, isEmpty);
    });

    testWidgets('a route link with target newTab opens its page beside this one', (tester) async {
      await pump(tester, const DVNavLink(to: DVRouteTarget('/pricing'), target: DVLinkTarget.newTab, child: DVText('Pricing')));
      await tester.tap(find.text('Pricing'));
      await tester.pump();
      expect(inNewTab, <String>['/pricing']);
    });
  });

  testWidgets('Enter on a focused link honours target too', (tester) async {
    await pump(tester, const DVNavLink.external('https://pub.dev', target: DVLinkTarget.newTab, autofocus: true, child: DVText('pub.dev')));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(inNewTab, <String>['https://pub.dev']);
  });

  group('the web interceptor (keyboard and screen readers on the anchor)', () {
    testWidgets('reads the target of the links on screen, and forgets one that is gone', (tester) async {
      await pump(tester, const DVNavLink.external('https://tools.example.com/', target: DVLinkTarget.sameTab, child: DVText('Tools')));
      expect(DVLinkTargets.of('https://tools.example.com/'), DVLinkTarget.sameTab);
      await pump(tester, const SizedBox());
      expect(DVLinkTargets.of('https://tools.example.com/'), DVLinkTarget.auto);
    });

    test('a link marked sameTab to another site is followed in this tab', () {
      const DVLinkActivation activation = DVLinkActivation(
        href: 'https://tools.example.com/',
        currentUrl: 'https://example.com/',
        linkTarget: DVLinkTarget.sameTab,
      );
      expect(dvLinkLeavesTheSite(activation), isFalse);
    });

    test('a page of this site marked newTab is opened beside, not routed', () {
      const DVLinkActivation activation = DVLinkActivation(
        href: '/pricing',
        currentUrl: 'https://example.com/',
        linkTarget: DVLinkTarget.newTab,
      );
      expect(dvRoutedLinkPath(activation), isNull);
      expect(dvLinkLeavesTheSite(activation), isTrue);
    });

    test('a modified click is still the browser\'s, whatever the link asked', () {
      const DVLinkActivation activation = DVLinkActivation(
        href: 'https://tools.example.com/',
        currentUrl: 'https://example.com/',
        withModifier: true,
        linkTarget: DVLinkTarget.newTab,
      );
      expect(dvLinkLeavesTheSite(activation), isFalse);
      expect(dvRoutedLinkPath(activation), isNull);
    });
  });
}
