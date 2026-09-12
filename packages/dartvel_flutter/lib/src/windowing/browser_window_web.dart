/// A second window in a browser, which is a popup and honest about it.
///
/// `window.open` returns null when the browser refuses, and it refuses when
/// the call was not attributed to a user gesture -- the rule the
/// specification names in `DV-WINDOW-003`. Null is the browser's own way of
/// saying so, so it is reported as [DVBrowserWindowOutcome.blocked] rather
/// than as the platform declining a well-formed request.
///
/// `noopener` is deliberately not passed: a window opened with it is not
/// returned to the opener, so every call would read as blocked and the
/// application could never close the window it opened.
library dartvel_flutter.windowing.browser_window.web;

import 'package:web/web.dart' as web;

import 'browser_window_types.dart';

/// Windows this page opened, by handle. Kept so [dvCloseBrowserWindow] can
/// close one: a browser lets a page close only a window that page opened.
final Map<String, web.Window> _opened = <String, web.Window>{};

var _next = 0;

DVBrowserWindowResult dvOpenBrowserWindow(
  String url, {
  String? title,
  double? width,
  double? height,
}) {
  // Size only when the caller asked. A bare '_blank' with no features is a
  // tab, which is what a browser gives by default and what most people want;
  // features turn it into a popup window.
  final String features = <String>[
    if (width != null) 'width=${width.round()}',
    if (height != null) 'height=${height.round()}',
  ].join(',');
  final web.Window? window = web.window.open(url, title ?? '_blank', features);
  if (window == null) {
    return const DVBrowserWindowResult(DVBrowserWindowOutcome.blocked);
  }
  final String id = 'browser-${_next++}';
  _opened[id] = window;
  return DVBrowserWindowResult(DVBrowserWindowOutcome.opened, id: id);
}

/// Closes the window [id] names, if this page opened it.
///
/// False when it did not, so the caller falls through to the native path
/// rather than believing a window closed that is still on screen.
bool dvCloseBrowserWindow(String? id) {
  final web.Window? window = id == null ? null : _opened.remove(id);
  if (window == null) return false;
  window.close();
  return true;
}
