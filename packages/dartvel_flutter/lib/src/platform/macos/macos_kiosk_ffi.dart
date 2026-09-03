/// Kiosk enforcement on macOS: NSApplication's presentation options.
///
/// macOS has one kiosk mechanism and it is this: the Dock and menu bar
/// hidden, process switching, force quit, session termination and hiding
/// disabled. Which escape combos that covers is a matter of record -- Cmd+Tab
/// is process switching, Cmd+Option+Esc is force quit, Cmd+H is hide,
/// Cmd+Shift+Q is log out -- and each is reported blocked only because the
/// option that covers it is in effect. What it does not cover, Cmd+Q above
/// all, comes back unenforced: quitting is refused in the application's
/// terminate delegate, not here. The pointer cannot be confined on macOS and
/// notifications cannot be held; neither is claimed.
///
/// Sent from the calling isolate, which on macOS is the platform thread now
/// that Flutter runs the root isolate there. A message sent from another
/// thread would not fail cleanly, which is why this is the only AppKit
/// state the bindings touch.
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../accelerator.dart';

typedef _ObjcGetClassNative = Pointer<Void> Function(Pointer<Utf8> name);
typedef _ObjcGetClassDart = Pointer<Void> Function(Pointer<Utf8> name);
typedef _SelRegisterNameNative = Pointer<Void> Function(Pointer<Utf8> name);
typedef _SelRegisterNameDart = Pointer<Void> Function(Pointer<Utf8> name);
typedef _MsgSend0Native = Pointer<Void> Function(Pointer<Void> receiver, Pointer<Void> selector);
typedef _MsgSend0Dart = Pointer<Void> Function(Pointer<Void> receiver, Pointer<Void> selector);
typedef _MsgSendSetUIntNative = Void Function(Pointer<Void> receiver, Pointer<Void> selector, UintPtr value);
typedef _MsgSendSetUIntDart = void Function(Pointer<Void> receiver, Pointer<Void> selector, int value);
typedef _MsgSendGetUIntNative = UintPtr Function(Pointer<Void> receiver, Pointer<Void> selector);
typedef _MsgSendGetUIntDart = int Function(Pointer<Void> receiver, Pointer<Void> selector);

class DVMacosKiosk {
  const DVMacosKiosk._();

  static late DynamicLibrary _objc;

  static const Set<String> implemented = <String>{'kiosk.enforce', 'kiosk.release'};

  // NSApplicationPresentationOptions.
  static const int hideDock = 1 << 1;
  static const int hideMenuBar = 1 << 3;
  static const int disableProcessSwitching = 1 << 5;
  static const int disableForceQuit = 1 << 6;
  static const int disableSessionTermination = 1 << 7;
  static const int disableHideApplication = 1 << 8;

  /// The kiosk set. Every member is allowed with every other: HideMenuBar and
  /// DisableProcessSwitching each require HideDock, which is here. An
  /// inconsistent set raises an Objective-C exception, which cannot be
  /// caught from Dart, so the set is fixed rather than composed per policy.
  static const int kioskOptions = hideDock |
      hideMenuBar |
      disableProcessSwitching |
      disableForceQuit |
      disableSessionTermination |
      disableHideApplication;

  /// Which option covers which escape combo, by canonical spelling.
  static const Map<String, int> _coveredBy = <String, int>{
    'Meta+Tab': disableProcessSwitching,
    'Shift+Meta+Tab': disableProcessSwitching,
    'Alt+Meta+Escape': disableForceQuit,
    'Meta+H': disableHideApplication,
    'Alt+Meta+H': disableHideApplication,
    'Shift+Meta+Q': disableSessionTermination,
    'Alt+Shift+Meta+Q': disableSessionTermination,
  };

  static bool _held = false;

  static void register(void Function(String, Object? Function(Object?)) bind, {required DynamicLibrary objc}) {
    _objc = objc;
    bind('kiosk.enforce', (Object? arguments) {
      final Map<Object?, Object?> map = arguments is Map ? arguments : const <Object?, Object?>{};
      _setOptions(kioskOptions);
      _held = true;
      final int inEffect = presentationOptions;
      final List<String> blocked = <String>[];
      final Map<String, String> unenforced = <String, String>{};
      for (final Object? raw in (map['combos'] as List?) ?? const <Object?>[]) {
        final String text = '$raw';
        final String canonical;
        try {
          canonical = DVAccelerator.parse(text, primaryIsMeta: true).canonical;
        } on FormatException catch (e) {
          unenforced[text] = e.message;
          continue;
        }
        final int? option = _coveredBy[canonical];
        if (option == null) {
          unenforced[text] = canonical == 'Meta+Q'
              ? 'no presentation option covers Cmd+Q; refuse it in the terminate delegate'
              : 'no presentation option covers $text';
        } else if (inEffect & option == option) {
          blocked.add(text);
        } else {
          unenforced[text] = 'presentation option not in effect';
        }
      }
      return <String, Object?>{
        'blocked': blocked,
        'unenforced': unenforced,
        // Hiding the Dock and menu bar is the surface, not the window's size;
        // the window is the embedder's, and it is not claimed fullscreen.
        'fullscreen': false,
        'confined': false,
        'notificationsSuppressed': false,
        'presentationOptions': inEffect,
      };
    });
    bind('kiosk.release', (Object? _) {
      release();
      return true;
    });
  }

  static Pointer<Void> _class(String name) {
    final getClass = _objc.lookupFunction<_ObjcGetClassNative, _ObjcGetClassDart>('objc_getClass');
    final Pointer<Utf8> p = name.toNativeUtf8();
    try {
      return getClass(p);
    } finally {
      calloc.free(p);
    }
  }

  static Pointer<Void> _selector(String name) {
    final sel = _objc.lookupFunction<_SelRegisterNameNative, _SelRegisterNameDart>('sel_registerName');
    final Pointer<Utf8> p = name.toNativeUtf8();
    try {
      return sel(p);
    } finally {
      calloc.free(p);
    }
  }

  /// `[NSApplication sharedApplication]`, created on first use.
  static Pointer<Void> _app() =>
      _objc.lookupFunction<_MsgSend0Native, _MsgSend0Dart>('objc_msgSend')(
          _class('NSApplication'), _selector('sharedApplication'));

  static void _setOptions(int options) {
    final Pointer<Void> app = _app();
    if (app == nullptr) return;
    _objc.lookupFunction<_MsgSendSetUIntNative, _MsgSendSetUIntDart>('objc_msgSend')(
        app, _selector('setPresentationOptions:'), options);
  }

  /// What NSApplication reports in effect.
  static int get presentationOptions {
    final Pointer<Void> app = _app();
    if (app == nullptr) return 0;
    return _objc.lookupFunction<_MsgSendGetUIntNative, _MsgSendGetUIntDart>('objc_msgSend')(
        app, _selector('presentationOptions'));
  }

  /// Back to the default presentation.
  static void release() {
    if (!_held) return;
    _setOptions(0);
    _held = false;
  }
}
