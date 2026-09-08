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

  // A link that leaves the site opens beside it rather than instead of it.
  //
  // On the web this is the browser's job, not the router's: the anchor is
  // already there, the click is already a user gesture, and `window.open`
  // from anywhere else is what a popup blocker exists to stop. So the
  // interceptor marks the anchor and steps back, and this decides which
  // anchors get marked.
  group('leaves the site', () {
    test('another origin does', () {
      expect(dvLinkLeavesTheSite(activation('https://pub.dev/packages/x')),
          isTrue);
      expect(dvLinkLeavesTheSite(activation('https://github.com/a/b')), isTrue);
    });

    test('this origin does not, however it is written', () {
      expect(dvLinkLeavesTheSite(activation('/features')), isFalse);
      expect(dvLinkLeavesTheSite(activation('cloud')), isFalse);
      expect(dvLinkLeavesTheSite(activation('https://dartvel.dev/docs')),
          isFalse);
    });

    // Not a navigation, so not a tab. A new window holding a half-written
    // mail client is worse than the thing it replaced.
    test('mailto and tel do not', () {
      expect(dvLinkLeavesTheSite(activation('mailto:hi@dartvel.dev')), isFalse);
      expect(dvLinkLeavesTheSite(activation('tel:+441234567890')), isFalse);
    });

    // Every one of these already means something to the browser, and the
    // meaning is more specific than "open it". Marking the anchor would
    // change what a download or a ctrl-click does.
    test('an instruction the browser already has is left alone', () {
      expect(
          dvLinkLeavesTheSite(
              activation('https://pub.dev/x', hasDownload: true)),
          isFalse);
      expect(
          dvLinkLeavesTheSite(
              activation('https://pub.dev/x', withModifier: true)),
          isFalse);
      expect(dvLinkLeavesTheSite(activation('https://pub.dev/x', button: 1)),
          isFalse);
      expect(
          dvLinkLeavesTheSite(
              activation('https://pub.dev/x', target: '_blank')),
          isFalse);
      expect(
          dvLinkLeavesTheSite(
              activation('https://pub.dev/x', alreadyHandled: true)),
          isFalse);
    });

    // The two answers cannot both be yes for one activation: routing it and
    // opening it beside are different destinations for the same click.
    test('nothing is both routed and sent away', () {
      for (final String href in <String>[
        '/features',
        'cloud',
        'https://dartvel.dev/docs',
        'https://pub.dev/packages/x',
        'mailto:hi@dartvel.dev',
        '#install',
      ]) {
        final DVLinkActivation a = activation(href);
        expect(dvRoutedLinkPath(a) != null && dvLinkLeavesTheSite(a), isFalse,
            reason: '$href was claimed by both');
      }
    });
  });
}
