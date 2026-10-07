/// The main window of a tray-resident application on macOS: hidden and
/// shown from the status item, and hidden rather than closed when the user
/// closes it under `exitPolicy: explicit`.
///
/// The main window is the first of NSApp's windows that can become main,
/// which leaves out the status bar's own window. Hide is orderOut:; show
/// activates the application and makeKeyAndOrderFront:s the window, which
/// is what "Show" in a menu-bar application's menu does. The close hook is
/// windowShouldClose: on the window's delegate -- the menus' runtime target
/// when the window has none -- answering NO and ordering the window out
/// under `explicit`, so the window is never closed and the Flutter
/// template's applicationShouldTerminateAfterLastWindowClosed: never fires.
/// AppKit sends it on the main thread, where Flutter runs the root isolate.
library;

import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../../../dartvel_flutter.dart' show DVWindowManager;
import 'macos_menus_ffi.dart';

typedef _ShouldCloseN = Bool Function(Pointer<Void> self, Pointer<Void> cmd, Pointer<Void> sender);
typedef _AddMethodN = Bool Function(Pointer<Void>, Pointer<Void>, Pointer<NativeFunction<_ShouldCloseN>>, Pointer<Utf8>);
typedef _AddMethodD = bool Function(Pointer<Void>, Pointer<Void>, Pointer<NativeFunction<_ShouldCloseN>>, Pointer<Utf8>);
typedef _ObjectGetClassN = Pointer<Void> Function(Pointer<Void>);
typedef _ObjectGetClassD = Pointer<Void> Function(Pointer<Void>);
typedef _RespondsN = Bool Function(Pointer<Void>, Pointer<Void>, Pointer<Void>);
typedef _RespondsD = bool Function(Pointer<Void>, Pointer<Void>, Pointer<Void>);

class DVMacosWindow {
  const DVMacosWindow._();

  static const Set<String> implemented = <String>{'window.hide', 'window.show'};

  static DynamicLibrary? _objc;
  static NativeCallable<_ShouldCloseN>? _shouldClose;
  static int _hooked = 0;

  /// Why the close hook is not in place, for the operator and the test.
  static String? lastError;

  static void register(void Function(String, FutureOr<Object?> Function(Object?)) bind, {required DynamicLibrary objc}) {
    _objc = objc;
    bind('window.hide', (Object? _) {
      final DVMacosObjc o = DVMacosObjc(objc);
      final Pointer<Void>? window = mainWindow();
      if (window == null) return false;
      ensureCloseHook();
      o.send1(window, 'orderOut:', nullptr);
      return true;
    });
    bind('window.show', (Object? _) {
      final DVMacosObjc o = DVMacosObjc(objc);
      final Pointer<Void>? window = mainWindow();
      if (window == null) return false;
      ensureCloseHook();
      final Pointer<Void> app = o.send0(o.cls('NSApplication'), 'sharedApplication');
      o.send1(app, 'unhide:', nullptr);
      o.sendBool(app, 'activateIgnoringOtherApps:', true);
      o.send1(window, 'makeKeyAndOrderFront:', nullptr);
      return true;
    });
    ensureCloseHook();
  }

  /// The application's main window: the first that can become main.
  static Pointer<Void>? mainWindow() {
    final DynamicLibrary? objc = _objc;
    if (objc == null) return null;
    final DVMacosObjc o = DVMacosObjc(objc);
    final Pointer<Void> app = o.send0(o.cls('NSApplication'), 'sharedApplication');
    if (app == nullptr) return null;
    final Pointer<Void> windows = o.send0(app, 'windows');
    final int count = o.getInt(windows, 'count');
    for (var i = 0; i < count; i++) {
      final Pointer<Void> window = o.getAt(windows, 'objectAtIndex:', i);
      if (o.getBool(window, 'canBecomeMainWindow')) return window;
    }
    return null;
  }

  /// Puts windowShouldClose: on the main window's delegate, once. A
  /// delegate that already answers it is the application's own and is left
  /// alone, said in [lastError].
  static bool ensureCloseHook() {
    final DynamicLibrary objc = _objc!;
    final DVMacosObjc o = DVMacosObjc(objc);
    final Pointer<Void>? window = mainWindow();
    if (window == null) {
      lastError = 'no main window yet';
      return false;
    }
    if (_hooked == window.address) return true;

    final NativeCallable<_ShouldCloseN> callable = _shouldClose ??= NativeCallable<_ShouldCloseN>.isolateLocal(
      (Pointer<Void> self, Pointer<Void> cmd, Pointer<Void> sender) {
        if (!DVWindowManager.closeHidesWindow) return true;
        DVMacosObjc(objc).send1(sender, 'orderOut:', nullptr);
        return false;
      },
      exceptionalReturn: true,
    );

    Pointer<Void> delegate = o.send0(window, 'delegate');
    if (delegate == nullptr) {
      // The menus' runtime target is retained for the process, which a
      // window's delegate -- a weak reference -- needs.
      delegate = DVMacosMenus.ensureTarget();
      o.send1(window, 'setDelegate:', delegate);
    }
    final Pointer<Void> selector = o.sel('windowShouldClose:');
    final bool responds = objc.lookupFunction<_RespondsN, _RespondsD>('objc_msgSend')(
        delegate, o.sel('respondsToSelector:'), selector);
    if (responds && delegate != DVMacosMenus.ensureTarget()) {
      lastError = 'the window delegate answers windowShouldClose: itself';
      return false;
    }
    if (!responds) {
      final Pointer<Utf8> types = 'c@:@'.toNativeUtf8();
      try {
        final Pointer<Void> cls = objc.lookupFunction<_ObjectGetClassN, _ObjectGetClassD>('object_getClass')(delegate);
        objc.lookupFunction<_AddMethodN, _AddMethodD>('class_addMethod')(cls, selector, callable.nativeFunction, types);
      } finally {
        calloc.free(types);
      }
    }
    _hooked = window.address;
    lastError = null;
    return true;
  }

  static void unregister() {
    // The method stays on the class -- a method cannot be removed -- and so
    // does its callable, for the reason the tray's does.
    _hooked = 0;
  }
}
