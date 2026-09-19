/// Right-click menus on the web: Flutter's own for a page's text, and the
/// browser's when it is asked for.
///
/// A page's text is drawn by Flutter rather than laid out as DOM text, so the
/// browser's menu has nothing to offer on it, and while that menu was on
/// Flutter's selection menu stayed hidden: a right-click showed neither.
/// Dartvel turns the browser's menu off and shows Flutter's, with a "Browser
/// menu" item. Browsers have no call that opens their own menu, so the item
/// hands the next right-click to the browser instead, and Shift+right-click
/// does the same for one click without the detour.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'browser_menu_stub.dart'
    if (dart.library.js_interop) 'browser_menu_web.dart' as platform;

/// The web's two right-click menus, and which one the next click gets.
abstract final class DVBrowserMenu {
  static bool _installed = false;
  static bool _next = false;

  /// Set by a test to stand for a browser.
  @visibleForTesting
  static bool? debugIsWeb;

  static bool get isWeb => debugIsWeb ?? kIsWeb;

  /// True when the next right-click goes to the browser's menu.
  static bool get nextClickIsNative => _next;

  /// Turns the browser's menu off so Flutter's shows, once per app.
  static void install() {
    if (_installed || !kIsWeb) return;
    _installed = true;
    unawaited(BrowserContextMenu.disableContextMenu());
    platform.dvListenForNativeMenu(
      arm: () => _arm(),
      disarm: _disarm,
    );
  }

  /// Hands the next right-click to the browser's own menu.
  static void openNextNative() => _arm();

  static void _arm() {
    _next = true;
    if (kIsWeb) unawaited(BrowserContextMenu.enableContextMenu());
  }

  static void _disarm() {
    if (!_next) return;
    _next = false;
    if (kIsWeb) unawaited(BrowserContextMenu.disableContextMenu());
  }

  @visibleForTesting
  static void debugReset() {
    _next = false;
    debugIsWeb = null;
  }
}
