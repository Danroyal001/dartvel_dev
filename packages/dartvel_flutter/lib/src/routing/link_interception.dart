/// Whether a link activation belongs to the router or to the browser.
///
/// Separated from the DOM so it can be tested off the web. The listener's job
/// is to read the event; this decides what it means, and the decisions are
/// the kind that break silently — a ctrl-click that stops opening a tab, or an
/// external link the application swallows, is not something a screenshot or a
/// smoke test notices.
library dartvel_flutter.routing.link_interception;

import 'package:dartvel_core/dartvel.dart' show dvKioskAllowsExternalUrl;

/// What the browser reported about a link activation.
class DVLinkActivation {
  const DVLinkActivation({
    required this.href,
    required this.currentUrl,
    this.target,
    this.hasDownload = false,
    this.button = 0,
    this.withModifier = false,
    this.alreadyHandled = false,
  });

  /// The anchor's `href`, exactly as written.
  final String href;

  /// The address the document is currently at, for resolving [href].
  final String currentUrl;

  /// The anchor's `target`, if it set one.
  final String? target;

  /// Whether the anchor carries `download`.
  final bool hasDownload;

  /// Which mouse button, where a mouse was involved. 0 is primary.
  final int button;

  /// Whether ctrl, meta, shift or alt was held.
  final bool withModifier;

  /// Whether another handler has already called `preventDefault`.
  final bool alreadyHandled;
}

/// The path to route to, or null when the browser should be left alone.
///
/// Null is the answer for everything the router cannot honour. A modified
/// click means open in a tab, a window, or download, and a router has no way
/// to do any of those; a second button means the same. `target` and
/// `download` are explicit instructions to the browser. Another origin or
/// another protocol is not this application's to serve, and `mailto:` and
/// `tel:` are not navigations at all. A bare fragment on the current page is a
/// scroll rather than a route.
String? dvRoutedLinkPath(DVLinkActivation activation) {
  if (activation.alreadyHandled) return null;
  if (activation.button != 0) return null;
  if (activation.withModifier) return null;
  if (activation.hasDownload) return null;

  final String? target = activation.target;
  if (target != null && target.isNotEmpty && target != '_self') return null;

  final Uri? destination = Uri.tryParse(activation.href);
  if (destination == null) return null;
  if (destination.hasScheme &&
      destination.scheme != 'http' &&
      destination.scheme != 'https') {
    return null;
  }

  final Uri? here = Uri.tryParse(activation.currentUrl);
  if (here == null) return null;
  final Uri resolved = here.resolveUri(destination);
  if (resolved.origin != here.origin) return null;

  if (resolved.path == here.path && resolved.fragment.isNotEmpty) return null;

  return resolved.path +
      (resolved.hasQuery ? '?${resolved.query}' : '') +
      (resolved.fragment.isEmpty ? '' : '#${resolved.fragment}');
}

/// Whether this activation leaves the site, and so belongs in its own tab.
///
/// A link to pub.dev is not a page of this application and never comes back
/// into it: replacing the document means the reader has left, and the way
/// back is the button that reloads everything they were part-way through.
/// Opening beside is what a site does, and it is the browser that should do
/// it — the anchor is already in the document and the click is already a user
/// gesture, which is the difference between a tab and a blocked popup.
///
/// So this is not "should the router open a tab". It is "should the anchor be
/// marked `target=_blank` and the browser left to it", and the answer is no
/// for everything the browser already has an instruction about. A download, a
/// ctrl-click, a middle click and an explicit `target` each mean something
/// more specific than "open it", and overriding any of them takes a choice
/// away from the reader.
///
/// `mailto:` and `tel:` are excluded because they are not navigations. A tab
/// that opens, hands the URL to a mail client and is left behind empty is a
/// worse outcome than the one it replaced.
///
/// This and [dvRoutedLinkPath] never both answer yes: one is a page of this
/// application and the other is not.
bool dvLinkLeavesTheSite(DVLinkActivation activation) {
  if (activation.alreadyHandled) return false;
  if (activation.button != 0) return false;
  if (activation.withModifier) return false;
  if (activation.hasDownload) return false;

  final String? target = activation.target;
  if (target != null && target.isNotEmpty && target != '_self') return false;

  final Uri? destination = Uri.tryParse(activation.href);
  if (destination == null) return false;
  // A scheme that is not the web's is not a page anywhere, so it is not a
  // page somewhere else either.
  if (destination.hasScheme &&
      destination.scheme != 'http' &&
      destination.scheme != 'https') {
    return false;
  }

  final Uri? here = Uri.tryParse(activation.currentUrl);
  if (here == null) return false;
  return here.resolveUri(destination).origin != here.origin;
}

/// Whether the running kiosk policy refuses this activation, so the browser
/// must not be allowed to act on the anchor.
///
/// Asked before anything else the interceptor decides, because the answer
/// changes what happens to the event rather than where it goes. On the web
/// the anchor is real and the browser follows it on the same click the widget
/// sees; a kiosk that decided afterwards would have decided after the tab
/// opened.
///
/// Only addresses that leave the application are judged. A route of this
/// application -- a relative href, or an absolute one back to the same origin
/// -- is `routes.allow`'s question, and a fragment is a scroll. `mailto:` and
/// `tel:` are judged even though they are not navigations: both hand the
/// address to another application, and a kiosk whose way out is the
/// contact-us link has no way out closed at all.
bool dvKioskRefusesLink(DVLinkActivation activation) {
  final Uri? destination = Uri.tryParse(activation.href);
  if (destination == null) return false;
  if (!destination.hasScheme) return false;

  final Uri? here = Uri.tryParse(activation.currentUrl);
  if (here != null &&
      (destination.scheme == 'http' || destination.scheme == 'https') &&
      here.resolveUri(destination).origin == here.origin) {
    return false;
  }

  return !dvKioskAllowsExternalUrl(activation.href);
}
