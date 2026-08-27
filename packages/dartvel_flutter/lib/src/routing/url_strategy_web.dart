/// Web-only routing and accessibility setup.
library dartvel_flutter.routing.url_strategy.web;

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_web_plugins/url_strategy.dart' as web;

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
