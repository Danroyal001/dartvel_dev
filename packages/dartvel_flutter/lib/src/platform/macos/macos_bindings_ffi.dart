/// macOS implementations of the `DV.Platform` bindings.
///
/// `dart:ffi` against the Objective-C runtime and CoreGraphics — no platform
/// channels, per the native integration rule.
///
/// Two different techniques, chosen per binding rather than uniformly:
///
///   * `screen.geometry` uses CoreGraphics, which is plain C. No messaging, no
///     selectors, no struct returns.
///   * The clipboard uses `objc_msgSend`, because `NSPasteboard` has no C API.
///
/// Only pointer-returning messages are sent. `objc_msgSend` needs a different
/// entry point for struct returns on some ABIs (`objc_msgSend_stret`), and
/// calling the wrong one corrupts the stack rather than failing — so anything
/// returning a struct, such as `NSScreen.frame`, is served from CoreGraphics
/// instead.
library dartvel_flutter.platform.macos.ffi;

import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';

import '../../../dartvel_flutter.dart' show DVNativeBridge;
import 'macos_capabilities.dart';
import 'macos_kiosk_ffi.dart';

export 'macos_kiosk_ffi.dart' show DVMacosKiosk;

// The Objective-C runtime, in libobjc.
typedef _ObjcGetClassNative = Pointer<Void> Function(Pointer<Utf8> name);
typedef _ObjcGetClassDart = Pointer<Void> Function(Pointer<Utf8> name);
typedef _SelRegisterNameNative = Pointer<Void> Function(Pointer<Utf8> name);
typedef _SelRegisterNameDart = Pointer<Void> Function(Pointer<Utf8> name);

// objc_msgSend, cast per call site. Objective-C messaging is variadic at the
// C level, so each distinct signature needs its own typed view of the same
// symbol.
typedef _MsgSend0Native = Pointer<Void> Function(
    Pointer<Void> receiver, Pointer<Void> selector);
typedef _MsgSend0Dart = Pointer<Void> Function(
    Pointer<Void> receiver, Pointer<Void> selector);
typedef _MsgSend1Native = Pointer<Void> Function(
    Pointer<Void> receiver, Pointer<Void> selector, Pointer<Void> a);
typedef _MsgSend1Dart = Pointer<Void> Function(
    Pointer<Void> receiver, Pointer<Void> selector, Pointer<Void> a);
typedef _MsgSend2BoolNative = Bool Function(Pointer<Void> receiver,
    Pointer<Void> selector, Pointer<Void> a, Pointer<Void> b);
typedef _MsgSend2BoolDart = bool Function(Pointer<Void> receiver,
    Pointer<Void> selector, Pointer<Void> a, Pointer<Void> b);
typedef _MsgSendUtf8Native = Pointer<Utf8> Function(
    Pointer<Void> receiver, Pointer<Void> selector);
typedef _MsgSendUtf8Dart = Pointer<Utf8> Function(
    Pointer<Void> receiver, Pointer<Void> selector);
typedef _MsgSendStrNative = Pointer<Void> Function(
    Pointer<Void> receiver, Pointer<Void> selector, Pointer<Utf8> a);
typedef _MsgSendStrDart = Pointer<Void> Function(
    Pointer<Void> receiver, Pointer<Void> selector, Pointer<Utf8> a);
typedef _MsgSendIntNative = Int64 Function(
    Pointer<Void> receiver, Pointer<Void> selector);
typedef _MsgSendIntDart = int Function(
    Pointer<Void> receiver, Pointer<Void> selector);

// CoreGraphics — plain C.
typedef _CGMainDisplayIDNative = Uint32 Function();
typedef _CGMainDisplayIDDart = int Function();
typedef _CGDisplayPixelsNative = IntPtr Function(Uint32 display);
typedef _CGDisplayPixelsDart = int Function(int display);

/// Registers the macOS bindings that are genuinely implemented.
class DVMacosBindings {
  const DVMacosBindings._();

  static bool _registered = false;
  static late DynamicLibrary _objc;
  static late DynamicLibrary _coreGraphics;

  static bool get isRegistered => _registered;

  static const Set<String> implemented = dvMacosImplementedBindings;

  static bool register() {
    if (_registered) return true;
    if (!Platform.isMacOS) return false;
    try {
      _objc = DynamicLibrary.open('/usr/lib/libobjc.A.dylib');
      _coreGraphics = DynamicLibrary.open(
          '/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics');
      // AppKit has to be loaded for NSPasteboard to exist as a class; nothing
      // is called from it directly.
      DynamicLibrary.open(
          '/System/Library/Frameworks/AppKit.framework/AppKit');
    } on ArgumentError {
      return false;
    }

    DVNativeBridge.register('clipboard.copy', (Object? arguments) {
      final text = arguments is Map ? '${arguments['text'] ?? ''}' : '';
      return _copy(text);
    });
    DVNativeBridge.register('clipboard.paste', (Object? _) => _paste());
    DVNativeBridge.register('screen.geometry', (Object? _) => _geometry());

    DVMacosKiosk.register(DVNativeBridge.register, objc: _objc);

    _registered = true;
    return true;
  }

  static void unregister() {
    if (_registered) DVMacosKiosk.release();
    for (final name in implemented) {
      DVNativeBridge.unregister(name);
    }
    _registered = false;
  }

  static Pointer<Void> _class(String name) {
    final getClass = _objc
        .lookupFunction<_ObjcGetClassNative, _ObjcGetClassDart>(
            'objc_getClass');
    final pointer = name.toNativeUtf8();
    try {
      return getClass(pointer);
    } finally {
      calloc.free(pointer);
    }
  }

  static Pointer<Void> _selector(String name) {
    final register = _objc
        .lookupFunction<_SelRegisterNameNative, _SelRegisterNameDart>(
            'sel_registerName');
    final pointer = name.toNativeUtf8();
    try {
      return register(pointer);
    } finally {
      calloc.free(pointer);
    }
  }

  /// An `NSString` holding [value], autoreleased by the runtime.
  static Pointer<Void> _nsString(String value) {
    final send = _objc
        .lookupFunction<_MsgSendStrNative, _MsgSendStrDart>('objc_msgSend');
    final utf8 = value.toNativeUtf8();
    try {
      return send(_class('NSString'),
          _selector('stringWithUTF8String:'), utf8);
    } finally {
      calloc.free(utf8);
    }
  }

  static bool _copy(String text) {
    final send0 =
        _objc.lookupFunction<_MsgSend0Native, _MsgSend0Dart>('objc_msgSend');
    final sendBool = _objc
        .lookupFunction<_MsgSend2BoolNative, _MsgSend2BoolDart>(
            'objc_msgSend');
    final sendInt = _objc
        .lookupFunction<_MsgSendIntNative, _MsgSendIntDart>('objc_msgSend');

    final pasteboard =
        send0(_class('NSPasteboard'), _selector('generalPasteboard'));
    if (pasteboard == nullptr) return false;

    // clearContents must come first, and returns the new change count. The
    // pasteboard rejects writes made without it.
    sendInt(pasteboard, _selector('clearContents'));

    return sendBool(
      pasteboard,
      _selector('setString:forType:'),
      _nsString(text),
      _nsString('public.utf8-plain-text'),
    );
  }

  static String? _paste() {
    final send0 =
        _objc.lookupFunction<_MsgSend0Native, _MsgSend0Dart>('objc_msgSend');
    final send1 =
        _objc.lookupFunction<_MsgSend1Native, _MsgSend1Dart>('objc_msgSend');
    final sendUtf8 = _objc
        .lookupFunction<_MsgSendUtf8Native, _MsgSendUtf8Dart>('objc_msgSend');

    final pasteboard =
        send0(_class('NSPasteboard'), _selector('generalPasteboard'));
    if (pasteboard == nullptr) return null;

    final value = send1(pasteboard, _selector('stringForType:'),
        _nsString('public.utf8-plain-text'));
    // Empty pasteboard, or nothing of this type on it. Null rather than an
    // empty string, so a caller can tell the two apart.
    if (value == nullptr) return null;

    final utf8 = sendUtf8(value, _selector('UTF8String'));
    if (utf8 == nullptr) return null;
    return utf8.toDartString();
  }

  /// The main display's pixel dimensions.
  ///
  /// CoreGraphics rather than `NSScreen.frame`, deliberately: the latter
  /// returns a struct, and a struct return through `objc_msgSend` needs
  /// `objc_msgSend_stret` on some ABIs. Calling the wrong one corrupts the
  /// stack rather than failing cleanly, and this needs no messaging at all.
  static Map<String, Object?> _geometry() {
    final mainDisplay = _coreGraphics
        .lookupFunction<_CGMainDisplayIDNative, _CGMainDisplayIDDart>(
            'CGMainDisplayID')();
    final wide = _coreGraphics
        .lookupFunction<_CGDisplayPixelsNative, _CGDisplayPixelsDart>(
            'CGDisplayPixelsWide');
    final high = _coreGraphics
        .lookupFunction<_CGDisplayPixelsNative, _CGDisplayPixelsDart>(
            'CGDisplayPixelsHigh');
    return <String, Object?>{
      'width': wide(mainDisplay),
      'height': high(mainDisplay),
    };
  }
}
