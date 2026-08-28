/// Web-only routing and accessibility setup.
library dartvel_flutter.routing.url_strategy.web;

import 'dart:js_interop';

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_web_plugins/url_strategy.dart' as web;
import 'package:web/web.dart' as web_dom;

import 'link_interception.dart';

/// Switch the browser off the default hash strategy.
///
/// Idempotent: the generated router calls it on every construction, and a
/// second call replaces the strategy with an equivalent one.
void dvUsePathUrlStrategy() => web.usePathUrlStrategy();

/// Build the semantics tree from the start, rather than when Flutter decides
/// assistive technology is present.
///
/// Two things depend on it, and both were broken without it.
///
/// Flutter web renders to a canvas and only emits real DOM elements for the
/// semantics tree. With no tree there is nothing for the browser to focus, so
/// the first Tab is spent entering the canvas and every stop after is off by
/// one — a keyboard user presses Tab, nothing visibly happens, and they press
/// it again. With the tree, links are real elements the browser tabs to
/// directly.
///
/// And a screen reader only works when the tree exists. Flutter builds it on
/// detecting assistive technology, which is a guess: it misses a user who
/// turns their reader on after the page loads, and it misses browsers that do
/// not advertise. For a website that guess is not worth making.
///
/// The cost is the tree itself, which is built anyway the moment anyone with
/// a reader arrives.
/// The handle is held, not discarded.
///
/// `ensureSemantics()` returns a handle that keeps the tree alive; dropping it
/// releases the request immediately. The first version called it and threw the
/// handle away, which left the browser showing Flutter's "enable
/// accessibility" placeholder button instead of the tree — semantics offered,
/// not switched on, and Tab still landing on the canvas.
SemanticsHandle? _semanticsHandle;

void dvEnsureSemantics() {
  if (_semanticsHandle != null) return;
  // The binding first. createDartvelRouter() is evaluated as an argument to
  // runApp, so it runs *before* runApp initialises the binding -- asking
  // SemanticsBinding.instance for anything at that point is asking a binding
  // that does not exist yet, and the request was quietly lost. The browser
  // kept showing Flutter's "enable accessibility" placeholder, and the DOM
  // had zero semantics nodes.
  WidgetsFlutterBinding.ensureInitialized();
  _semanticsHandle = SemanticsBinding.instance.ensureSemantics();
}

/// Route in-app links instead of letting the browser reload the document.
///
/// `Semantics(link: true, linkUrl: ...)` makes Flutter emit a real `<a href>`
/// in the semantics DOM, which is what a crawler follows and what a screen
/// reader announces. It is also what the browser navigates on click or Enter,
/// natively, before Flutter's gesture handling sees anything — so every link
/// tore the document down and rebuilt the whole application to move between
/// two routes. Measured rather than assumed: a marker set on `window` did not
/// survive a link activation.
///
/// So the anchors stay, and the navigation is intercepted. An in-app link
/// pushes the route; anything that is not an in-app link is left alone, which
/// is the only correct default — a browser does a great many things with a
/// click that an application should not take over.
///
/// Left to the browser, deliberately:
///
///  * a modified click — ctrl, meta, shift or alt — because those mean open in
///    a tab, a window, or download, and a router cannot honour any of them;
///  * anything but the primary button, so middle-click still opens a tab;
///  * `target` other than `_self`, and any anchor carrying `download`;
///  * another origin, another protocol, and `mailto:`/`tel:`;
///  * a fragment on the current page, which is a scroll rather than a route;
///  * an event another handler has already claimed.
void dvInterceptLinkNavigation(void Function(String path) route) {
  if (_intercepting) return;
  _intercepting = true;

  void handle(web_dom.Event event) {
    final web_dom.MouseEvent? mouse =
        event.isA<web_dom.MouseEvent>() ? event as web_dom.MouseEvent : null;
    final web_dom.KeyboardEvent? keys = event.isA<web_dom.KeyboardEvent>()
        ? event as web_dom.KeyboardEvent
        : null;
    // Enter activates a focused anchor; every other key leaves it alone.
    if (keys != null && keys.key != 'Enter') return;

    final web_dom.EventTarget? target = event.target;
    if (target == null || !target.isA<web_dom.Element>()) return;
    final web_dom.Element? anchor =
        (target as web_dom.Element).closest('a[href]');
    if (anchor == null) return;

    final String? path = dvRoutedLinkPath(DVLinkActivation(
      href: anchor.getAttribute('href') ?? '',
      currentUrl: web_dom.window.location.href,
      target: anchor.getAttribute('target'),
      hasDownload: anchor.hasAttribute('download'),
      button: mouse?.button ?? 0,
      withModifier: mouse != null &&
          (mouse.ctrlKey || mouse.metaKey || mouse.shiftKey || mouse.altKey),
      alreadyHandled: event.defaultPrevented,
    ));
    if (path == null) return;

    event.preventDefault();
    route(path);
  }

  // Capture phase, so this runs before the anchor's own default action is
  // committed and before anything inside the semantics tree stops the event.
  web_dom.document.addEventListener('click', handle.toJS, true.toJS);
  web_dom.document.addEventListener('keydown', handle.toJS, true.toJS);
}

bool _intercepting = false;
