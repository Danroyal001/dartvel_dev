/// Right-click menus on the web: Flutter's own for a page's text, and the
/// browser's when it is asked for.
///
/// A page's text is drawn by Flutter rather than laid out as DOM text, so the
/// browser's menu has nothing to offer on it, and while that menu was on
/// Flutter's selection menu stayed hidden: a right-click showed neither.
/// Dartvel turns the browser's menu off and shows Flutter's, with a More
/// item. Browsers have no call that opens their own menu, so More hands the
/// next right-click to the browser instead and says so where the menu was,
/// and Shift+right-click does the same for one click without the detour.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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

  /// What More says, since nothing else visible happens when it is pressed.
  static const String hint = "Right-click again for your browser's menu";

  static OverlayEntry? _hint;
  static Timer? _hintTimer;

  /// Shows [hint] at [at] for a few seconds.
  static void showHint(BuildContext context, Offset at) {
    final OverlayState? overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _clearHint();
    final OverlayEntry entry = OverlayEntry(
      builder: (BuildContext context) => Positioned(
        left: at.dx,
        top: at.dy,
        child: IgnorePointer(
          child: Material(
            color: const Color(0xE6202124),
            borderRadius: BorderRadius.circular(6),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(hint,
                  style: TextStyle(color: Color(0xFFFFFFFF), fontSize: 13)),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    _hint = entry;
    _hintTimer = Timer(const Duration(seconds: 4), _clearHint);
  }

  static void _clearHint() {
    _hintTimer?.cancel();
    _hintTimer = null;
    _hint?.remove();
    _hint = null;
  }

  static void _arm() {
    _next = true;
    if (kIsWeb) unawaited(BrowserContextMenu.enableContextMenu());
  }

  static void _disarm() {
    _clearHint();
    if (!_next) return;
    _next = false;
    if (kIsWeb) unawaited(BrowserContextMenu.disableContextMenu());
  }

  @visibleForTesting
  static void debugReset() {
    _clearHint();
    _next = false;
    debugIsWeb = null;
  }
}
