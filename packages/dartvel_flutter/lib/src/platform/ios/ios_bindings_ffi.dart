/// iOS implementations of the `DV.Platform` bindings.
///
/// `dart:ffi` against the Objective-C runtime — no platform channels, per the
/// native integration rule. On iOS the runtime is inside the app binary rather
/// than a separate dylib, so the process itself is opened.
///
/// Only pointer-returning messages are sent. `objc_msgSend` needs a different
/// entry point for struct returns on some ABIs, and calling the wrong one
/// corrupts the stack rather than failing — which is why `screen.geometry` is
/// absent here while macOS has it: macOS can ask CoreGraphics instead, and iOS
/// has no equivalent C path.
///
/// Haptics take the same preference further and skip the Objective-C runtime
/// altogether. `UIImpactFeedbackGenerator` must be built and called on the
/// main thread and Flutter's root isolate runs on the UI thread, so the
/// documented API is the unusable one here; `AudioServicesPlaySystemSound` is
/// plain C and thread-safe.
library dartvel_flutter.platform.ios.ffi;

import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';

import '../../../dartvel_flutter.dart' show DVNativeBridge;
import 'ios_capabilities.dart';

typedef _ObjcGetClassNative = Pointer<Void> Function(Pointer<Utf8> name);
typedef _ObjcGetClassDart = Pointer<Void> Function(Pointer<Utf8> name);
typedef _SelRegisterNameNative = Pointer<Void> Function(Pointer<Utf8> name);
typedef _SelRegisterNameDart = Pointer<Void> Function(Pointer<Utf8> name);

typedef _MsgSend0Native = Pointer<Void> Function(
    Pointer<Void> receiver, Pointer<Void> selector);
typedef _MsgSend0Dart = Pointer<Void> Function(
    Pointer<Void> receiver, Pointer<Void> selector);
typedef _MsgSendVoidNative = Void Function(
    Pointer<Void> receiver, Pointer<Void> selector, Pointer<Void> a);
typedef _MsgSendVoidDart = void Function(
    Pointer<Void> receiver, Pointer<Void> selector, Pointer<Void> a);
typedef _MsgSendUtf8Native = Pointer<Utf8> Function(
    Pointer<Void> receiver, Pointer<Void> selector);
typedef _MsgSendUtf8Dart = Pointer<Utf8> Function(
    Pointer<Void> receiver, Pointer<Void> selector);
typedef _MsgSendStrNative = Pointer<Void> Function(
    Pointer<Void> receiver, Pointer<Void> selector, Pointer<Utf8> a);
typedef _MsgSendStrDart = Pointer<Void> Function(
    Pointer<Void> receiver, Pointer<Void> selector, Pointer<Utf8> a);

/// `AudioServicesPlaySystemSound(SystemSoundID inSystemSoundID)`.
///
/// `SystemSoundID` is a `UInt32`. Plain C, and documented as safe to call from
/// any thread -- which is the whole reason haptics go through AudioToolbox
/// here rather than through `UIImpactFeedbackGenerator`.
typedef _PlaySystemSoundNative = Void Function(Uint32 soundId);
typedef _PlaySystemSoundDart = void Function(int soundId);

/// Registers the iOS bindings that are genuinely implemented.
class DVIosBindings {
  const DVIosBindings._();

  static bool _registered = false;
  static late DynamicLibrary _objc;
  static _PlaySystemSoundDart? _playSystemSound;

  static bool get isRegistered => _registered;

  static const Set<String> implemented = dvIosImplementedBindings;

  static bool register() {
    if (_registered) return true;
    if (!Platform.isIOS) return false;
    try {
      // The Objective-C runtime is linked into the app on iOS rather than
      // living in a dylib that can be opened by path.
      _objc = DynamicLibrary.process();
      // Proves the runtime is actually reachable before anything depends on
      // it, so a bad assumption fails here rather than mid-call.
      _objc.lookup<NativeFunction<_ObjcGetClassNative>>('objc_getClass');
    } on ArgumentError {
      return false;
    }

    DVNativeBridge.register('clipboard.copy', (Object? arguments) {
      final text = arguments is Map ? '${arguments['text'] ?? ''}' : '';
      return _copy(text);
    });
    DVNativeBridge.register('clipboard.paste', (Object? _) => _paste());

    // AudioToolbox is opened by path out of the dyld shared cache rather than
    // assumed to be linked into the app. If it is not there, registration
    // fails as a whole rather than installing a subset: `implemented` is what
    // callers check, and a partial install would leave it claiming haptics
    // that throw on first use.
    _playSystemSound = _lookupPlaySystemSound();
    if (_playSystemSound == null) {
      DVNativeBridge.unregister('clipboard.copy');
      DVNativeBridge.unregister('clipboard.paste');
      return false;
    }
    for (final name in const <String>[
      'haptics.impact',
      'haptics.lightVibrate',
      'haptics.vibrate',
    ]) {
      DVNativeBridge.register(name, (Object? _) {
        _playSystemSound!(dvIosHapticSoundId(name));
        return null;
      });
    }

    _registered = true;
    return true;
  }

  /// The AudioToolbox entry point, or null when the framework is not present.
  static _PlaySystemSoundDart? _lookupPlaySystemSound() {
    try {
      final audioToolbox = DynamicLibrary.open(
          '/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox');
      return audioToolbox.lookupFunction<_PlaySystemSoundNative,
          _PlaySystemSoundDart>('AudioServicesPlaySystemSound');
    } on ArgumentError {
      return null;
    }
  }

  static void unregister() {
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

  static Pointer<Void> _nsString(String value) {
    final send = _objc
        .lookupFunction<_MsgSendStrNative, _MsgSendStrDart>('objc_msgSend');
    final utf8 = value.toNativeUtf8();
    try {
      return send(
          _class('NSString'), _selector('stringWithUTF8String:'), utf8);
    } finally {
      calloc.free(utf8);
    }
  }

  static bool _copy(String text) {
    final send0 =
        _objc.lookupFunction<_MsgSend0Native, _MsgSend0Dart>('objc_msgSend');
    final sendVoid = _objc
        .lookupFunction<_MsgSendVoidNative, _MsgSendVoidDart>('objc_msgSend');

    final pasteboard =
        send0(_class('UIPasteboard'), _selector('generalPasteboard'));
    if (pasteboard == nullptr) return false;

    // setString: returns void, so success is the absence of a crash. UIKit
    // gives no result to check, and inventing one would be a lie.
    sendVoid(pasteboard, _selector('setString:'), _nsString(text));
    return true;
  }

  static String? _paste() {
    final send0 =
        _objc.lookupFunction<_MsgSend0Native, _MsgSend0Dart>('objc_msgSend');
    final sendUtf8 = _objc
        .lookupFunction<_MsgSendUtf8Native, _MsgSendUtf8Dart>('objc_msgSend');

    final pasteboard =
        send0(_class('UIPasteboard'), _selector('generalPasteboard'));
    if (pasteboard == nullptr) return null;

    final value = send0(pasteboard, _selector('string'));
    // Nil when the pasteboard holds nothing textual. Null rather than an empty
    // string, so a caller can tell "nothing there" from "an empty string".
    if (value == nullptr) return null;

    final utf8 = sendUtf8(value, _selector('UTF8String'));
    if (utf8 == nullptr) return null;
    return utf8.toDartString();
  }
}
