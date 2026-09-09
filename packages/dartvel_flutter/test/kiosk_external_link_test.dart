// What `routes.external` stops, at the point where a link actually leaves.
//
// The policy key was parsed by nothing and enforced by nothing, so a kiosk
// that declared `external: block` still opened the browser on top of itself
// when somebody tapped the footer. On a lobby display that is the end of the
// kiosk: the person now has a browser, an address bar and a machine.
//
// Two paths lead out and both are covered here. DVLinkOpener is the funnel
// every DVNavLink.external goes through off the web. On the web the browser
// follows the anchor itself, so the interceptor has to decide before the
// default action is taken -- which is what dvKioskRefusesLink answers.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:dartvel_flutter/src/routing/link_interception.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

DVKioskPolicy _policy({
  required String external,
  List<String> allow = const <String>[],
}) =>
    DVKioskPolicy.parse(<String, Object?>{
      'kiosk': <String, Object?>{
        'enabled': true,
        'routes': <String, Object?>{
          'external': external,
          'externalAllow': allow,
        },
      },
    });

DVLinkActivation _click(String href) => DVLinkActivation(
      href: href,
      currentUrl: 'https://kiosk.example.com/welcome',
    );

void main() {
  final opened = <String>[];

  setUp(() {
    opened.clear();
    dvResetKioskContainment();
    DVLinkOpener.install((String path, {bool newTab = false}) {
      opened.add(path);
    });
  });

  tearDown(() {
    DVLinkOpener.reset();
    dvResetKioskContainment();
  });

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
        MaterialApp(home: Scaffold(body: Center(child: child))),
      );

  group('the opener refuses what the policy refuses', () {
    testWidgets('a blocked address never reaches the platform',
        (tester) async {
      dvApplyKioskContainment(_policy(external: 'block'));
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
    });

    testWidgets('an allowed address opens exactly as it always did',
        (tester) async {
      dvApplyKioskContainment(_policy(
        external: 'allowlist',
        allow: <String>['https://help.example.com/**'],
      ));
      await pump(
        tester,
        const DVNavLink.external(
          'https://help.example.com/kiosk',
          child: DVText('Help'),
        ),
      );

      await tester.tap(find.text('Help'));
      await tester.pump();

      expect(opened, <String>['https://help.example.com/kiosk']);
    });

    testWidgets('an address off the allowlist does not open', (tester) async {
      dvApplyKioskContainment(_policy(
        external: 'allowlist',
        allow: <String>['https://help.example.com/**'],
      ));
      await pump(
        tester,
        const DVNavLink.external(
          'https://social.example.com/kiosk',
          child: DVText('Elsewhere'),
        ),
      );

      await tester.tap(find.text('Elsewhere'));
      await tester.pump();

      expect(opened, isEmpty);
    });

    testWidgets('with no kiosk installed nothing is refused', (tester) async {
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
  });

  group('the web interceptor decides before the browser acts', () {
    test('a cross-origin link is refused under block', () {
      dvApplyKioskContainment(_policy(external: 'block'));

      expect(dvKioskRefusesLink(_click('https://pub.dev/packages/x')), isTrue);
    });

    test('a mail or telephone link is refused too', () {
      // Neither is a navigation, and both hand the address to another
      // application. A kiosk that blocks the way out blocks these as well,
      // or the way out is the contact-us link.
      dvApplyKioskContainment(_policy(external: 'block'));

      expect(dvKioskRefusesLink(_click('mailto:hi@example.com')), isTrue);
      expect(dvKioskRefusesLink(_click('tel:+441234567890')), isTrue);
    });

    test('a dialler on the allowlist is let through', () {
      dvApplyKioskContainment(
          _policy(external: 'allowlist', allow: <String>['tel:']));

      expect(dvKioskRefusesLink(_click('tel:+441234567890')), isFalse);
      expect(dvKioskRefusesLink(_click('mailto:hi@example.com')), isTrue);
    });

    test('a page of this application is never refused here', () {
      // Its own routes are routes.allow's question. Refusing them here would
      // stop the kiosk navigating itself the moment external was declared.
      dvApplyKioskContainment(_policy(external: 'block'));

      expect(dvKioskRefusesLink(_click('/order/12')), isFalse);
      expect(
        dvKioskRefusesLink(_click('https://kiosk.example.com/order/12')),
        isFalse,
      );
    });

    test('a fragment on the current page is not a way out', () {
      dvApplyKioskContainment(_policy(external: 'block'));

      expect(dvKioskRefusesLink(_click('#terms')), isFalse);
    });

    test('with no kiosk installed nothing is refused', () {
      expect(dvKioskRefusesLink(_click('https://pub.dev/packages/x')), isFalse);
    });
  });
}
