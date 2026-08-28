/// Whether a link activation belongs to the router or to the browser.
///
/// Separated from the DOM so it can be tested off the web. The listener's job
/// is to read the event; this decides what it means, and the decisions are
/// the kind that break silently — a ctrl-click that stops opening a tab, or an
/// external link the application swallows, is not something a screenshot or a
/// smoke test notices.
library dartvel_flutter.routing.link_interception;

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
