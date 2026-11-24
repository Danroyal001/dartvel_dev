/// Off the web there is no URL strategy to choose and no DOM to describe, so
/// these do nothing.
///
/// No-ops rather than throws: the generated router calls them
/// unconditionally, and a router that crashed on desktop to report a web-only
/// concern would be the worse failure.
library dartvel_flutter.routing.url_strategy.stub;

import 'dart:async';

import '../../dartvel_flutter.dart' show DVNativeBridge;

void dvUsePathUrlStrategy() {}

void dvEnsureSemantics() {}

/// No-op off the web. There is no document, no anchors and no browser
/// navigation to intercept: a link on a native platform reaches
/// [DVNavLink]'s own handler and nothing else.
void dvInterceptLinkNavigation(void Function(String path) route) {}

/// Off the web the address goes to the platform: the `links.open` binding,
/// which Android answers with ACTION_VIEW (the browser for a web address, the
/// dialer for tel:, the mail app for mailto:). [newTab] has no meaning here:
/// another app always opens beside this one.
///
/// It was a no-op, so every external link (DVNavLink.external,
/// DVLinkOpener.open) did nothing on a phone. With no binding it still does
/// nothing, and a binding that fails is swallowed: this runs in tap handlers,
/// where an exception is a red screen and not an answer.
void dvOpenUrl(String path, {bool newTab = false}) {
  if (!DVNativeBridge.isRegistered('links.open')) return;
  unawaited(
    DVNativeBridge.invoke<Object?>('links.open', <String, Object?>{'url': path}).then<void>((_) {}, onError: (Object _) {}),
  );
}

/// False off the web: there are no anchors, so nothing follows one and
/// [DVNavLink] is the only thing that can open a link.
const bool dvBrowserFollowsAnchors = false;
