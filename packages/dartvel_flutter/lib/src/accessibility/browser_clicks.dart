/// The browser's count of a double- or triple-click, for the page's
/// selection.
///
/// Flutter counts consecutive clicks itself, and gives up on a run after 300
/// ms between clicks (kDoubleTapTimeout). The browser counts them with the
/// system's double-click time, which is 500 ms by default on Windows and up
/// to several seconds on macOS. A reader who clicks at an ordinary pace, 300
/// to 500 ms apart, made a triple-click the browser counted and Flutter saw
/// as three single clicks: the paragraph was not selected, the last click
/// collapsed the selection, and Ctrl+C copied nothing (Tori and Learnacer,
/// Dartvel 3.47.7). The same for a double-click and its word.
///
/// On the web the page shell hears the browser's count from the click that
/// ends each press of a run past the first, where the button came up where
/// it went down, and
/// selects the word (two) or the paragraph (three or more) under it, as
/// Flutter does when it counts the run itself. A run Flutter did count ends
/// with the same selection it made. Elsewhere nothing is reported: the
/// platform and Flutter agree on the timing there.
///
/// Not in the barrel: every selectable page has it.
library;

import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import 'browser_clicks_stub.dart' if (dart.library.js_interop) 'browser_clicks_web.dart' as platform;

/// Hears a run of [count] clicks ending at [position], in logical pixels.
typedef DVBrowserClickListener = void Function(int count, Offset position);

abstract final class DVBrowserClicks {
  static final List<DVBrowserClickListener> _listeners = <DVBrowserClickListener>[];

  /// Called by the page shell as a page is built.
  static void listen(DVBrowserClickListener listener) {
    _listeners.add(listener);
    platform.dvInstallBrowserClicks(report);
  }

  /// Called by the page shell as a page goes away.
  static void unlisten(DVBrowserClickListener listener) => _listeners.remove(listener);

  /// The browser counted [count] clicks, the last at [position]. The
  /// document half calls it; tests call it in its place.
  @visibleForTesting
  static void report(int count, Offset position) {
    if (count < 2) return;
    for (final DVBrowserClickListener listener in List<DVBrowserClickListener>.of(_listeners)) {
      listener(count, position);
    }
  }
}
