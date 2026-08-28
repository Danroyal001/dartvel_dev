// Which link activations the router takes, and which it must not.
//
// Semantics(linkUrl:) makes Flutter emit a real <a href>, which is what a
// crawler follows and a screen reader announces -- and what the browser
// navigates natively, tearing the document down to move between two routes.
// Measured rather than assumed: a marker set on window did not survive a link
// activation on the built site.
//
// So the anchors stay and the navigation is intercepted. The risk moves to the
// other side: an interceptor that is too eager breaks ctrl-click, external
// links and downloads, and none of those show up in a screenshot.
import 'package:dartvel_flutter/src/routing/link_interception.dart';
import 'package:flutter_test/flutter_test.dart';

DVLinkActivation activation(
  String href, {
  String currentUrl = 'https://dartvel.dev/docs',
  String? target,
  bool hasDownload = false,
  int button = 0,
  bool withModifier = false,
  bool alreadyHandled = false,
}) =>
    DVLinkActivation(
      href: href,
      currentUrl: currentUrl,
      target: target,
      hasDownload: hasDownload,
      button: button,
      withModifier: withModifier,
      alreadyHandled: alreadyHandled,
    );

void main() {
  group('the router takes it', () {
    test('a same-origin absolute path', () {
      expect(dvRoutedLinkPath(activation('/features')), '/features');
    });

    test('a relative path, resolved against where we are', () {
      expect(dvRoutedLinkPath(activation('cloud')), '/cloud');
    });

    test('a fully qualified URL on this origin', () {
      expect(dvRoutedLinkPath(activation('https://dartvel.dev/features')),
          '/features');
    });

    test('the query survives', () {
      expect(dvRoutedLinkPath(activation('/search?q=forms')), '/search?q=forms');
    });

    test('a fragment on a different page is still a route', () {
      expect(dvRoutedLinkPath(activation('/features#forms')),
          '/features#forms');
    });

    test('target="_self" is the default and changes nothing', () {
      expect(dvRoutedLinkPath(activation('/features', target: '_self')),
          '/features');
    });
  });

  group('the browser keeps it', () {
    test('a modified click, which means open in a tab or window', () {
      expect(dvRoutedLinkPath(activation('/features', withModifier: true)),
          isNull);
    });

    test('a middle click, which opens a tab', () {
      expect(dvRoutedLinkPath(activation('/features', button: 1)), isNull);
    });

    test('an anchor asking for another target', () {
      expect(dvRoutedLinkPath(activation('/features', target: '_blank')),
          isNull);
    });

    test('a download', () {
      expect(dvRoutedLinkPath(activation('/dartvel.zip', hasDownload: true)),
          isNull);
    });

    test('another origin', () {
      expect(dvRoutedLinkPath(activation('https://pub.dev/packages/dartvel_dev')),
          isNull);
    });

    test('mailto and tel, which are not navigations', () {
      expect(dvRoutedLinkPath(activation('mailto:hi@dartvel.dev')), isNull);
      expect(dvRoutedLinkPath(activation('tel:+441234567890')), isNull);
    });

    test('a fragment on the page we are already on, which is a scroll', () {
      expect(dvRoutedLinkPath(activation('#install')), isNull);
      expect(dvRoutedLinkPath(activation('/docs#install')), isNull);
    });

    test('an event another handler has already claimed', () {
      expect(dvRoutedLinkPath(activation('/features', alreadyHandled: true)),
          isNull);
    });
  });
}
