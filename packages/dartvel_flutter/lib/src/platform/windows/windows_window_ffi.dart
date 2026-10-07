/// The main window of a tray-resident application on Windows: found even
/// while hidden, hidden and shown from the tray, and hidden rather than
/// closed when the user closes it under `exitPolicy: explicit`.
///
/// `GetActiveWindow` answers 0 for a window that is hidden or not yet
/// shown -- the Flutter runner shows its window only after the first frame,
/// after Dart has started -- so the window is remembered once found, and
/// otherwise found by the runner's window class, owned by this process.
/// The close hook is a subclass that sees WM_CLOSE before the runner does:
/// under `explicit` it hides the window and stops the message, so the
/// runner never destroys it and never posts WM_QUIT.
library;

import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../../../dartvel_flutter.dart' show DVWindowManager;

typedef _SubclassProcNative = IntPtr Function(
    IntPtr hWnd, Uint32 message, IntPtr wParam, IntPtr lParam, UintPtr subclassId, UintPtr refData);
typedef _SetSubclassN = Int32 Function(IntPtr, Pointer<NativeFunction<_SubclassProcNative>>, UintPtr, UintPtr);
typedef _SetSubclassD = int Function(int, Pointer<NativeFunction<_SubclassProcNative>>, int, int);
typedef _DefSubclassN = IntPtr Function(IntPtr, Uint32, IntPtr, IntPtr);
typedef _DefSubclassD = int Function(int, int, int, int);
typedef _HwndN = IntPtr Function();
typedef _HwndD = int Function();
typedef _IntOfHwndN = Int32 Function(IntPtr);
typedef _IntOfHwndD = int Function(int);
typedef _ShowWindowN = Int32 Function(IntPtr, Int32);
typedef _ShowWindowD = int Function(int, int);
typedef _FindWindowExN = IntPtr Function(IntPtr, IntPtr, Pointer<Utf16>, Pointer<Utf16>);
typedef _FindWindowExD = int Function(int, int, Pointer<Utf16>, Pointer<Utf16>);
typedef _ThreadProcessIdN = Uint32 Function(IntPtr, Pointer<Uint32>);
typedef _ThreadProcessIdD = int Function(int, Pointer<Uint32>);
typedef _ProcessIdN = Uint32 Function();
typedef _ProcessIdD = int Function();

const int _wmClose = 0x0010;
const int _swHide = 0;
const int _swShow = 5;
const int _swRestore = 9;
const int _subclassId = 0x4457; // 'DW'

/// The window class the Flutter Windows runner registers.
const String _runnerClass = 'FLUTTER_RUNNER_WIN32_WINDOW';

class DVWindowsWindow {
  const DVWindowsWindow._();

  static const Set<String> implemented = <String>{'window.hide', 'window.show'};

  static DynamicLibrary? _user32;
  static DynamicLibrary? _comctl32;
  static int _window = 0;
  static int _hooked = 0;
  static NativeCallable<_SubclassProcNative>? _proc;

  static void register(void Function(String, FutureOr<Object?> Function(Object?)) bind, {required DynamicLibrary user32}) {
    _user32 = user32;
    bind('window.hide', (Object? _) {
      final int hWnd = find(user32);
      if (hWnd == 0) return false;
      ensureCloseHook();
      user32.lookupFunction<_ShowWindowN, _ShowWindowD>('ShowWindow')(hWnd, _swHide);
      return true;
    });
    bind('window.show', (Object? _) {
      final int hWnd = find(user32);
      if (hWnd == 0) return false;
      ensureCloseHook();
      final _ShowWindowD showWindow = user32.lookupFunction<_ShowWindowN, _ShowWindowD>('ShowWindow');
      final bool minimised = user32.lookupFunction<_IntOfHwndN, _IntOfHwndD>('IsIconic')(hWnd) != 0;
      showWindow(hWnd, minimised ? _swRestore : _swShow);
      user32.lookupFunction<_IntOfHwndN, _IntOfHwndD>('SetForegroundWindow')(hWnd);
      return true;
    });
    ensureCloseHook();
  }

  /// This process's main window, or 0. Remembered once found, because a
  /// hidden window is not active and cannot be found that way again.
  static int find(DynamicLibrary user32) {
    if (_window != 0 && user32.lookupFunction<_IntOfHwndN, _IntOfHwndD>('IsWindow')(_window) != 0) {
      return _window;
    }
    final int active = user32.lookupFunction<_HwndN, _HwndD>('GetActiveWindow')();
    if (active != 0) return _window = active;
    final int processId = DynamicLibrary.open('kernel32.dll').lookupFunction<_ProcessIdN, _ProcessIdD>('GetCurrentProcessId')();
    final _FindWindowExD findWindow = user32.lookupFunction<_FindWindowExN, _FindWindowExD>('FindWindowExW');
    final _ThreadProcessIdD ownerOf = user32.lookupFunction<_ThreadProcessIdN, _ThreadProcessIdD>('GetWindowThreadProcessId');
    final Pointer<Utf16> className = _runnerClass.toNativeUtf16();
    final Pointer<Uint32> owner = calloc<Uint32>();
    try {
      int candidate = 0;
      while ((candidate = findWindow(0, candidate, className, nullptr)) != 0) {
        ownerOf(candidate, owner);
        if (owner.value == processId) return _window = candidate;
      }
      return 0;
    } finally {
      calloc.free(className);
      calloc.free(owner);
    }
  }

  /// Subclasses the main window for WM_CLOSE, once.
  static bool ensureCloseHook() {
    final DynamicLibrary? user32 = _user32;
    if (user32 == null) return false;
    final int hWnd = find(user32);
    if (hWnd == 0) return false;
    if (_hooked == hWnd) return true;
    final DynamicLibrary comctl32 = _comctl32 ??= DynamicLibrary.open('comctl32.dll');
    final NativeCallable<_SubclassProcNative> proc =
        _proc ??= NativeCallable<_SubclassProcNative>.isolateLocal(_onMessage, exceptionalReturn: 0);
    if (comctl32.lookupFunction<_SetSubclassN, _SetSubclassD>('SetWindowSubclass')(hWnd, proc.nativeFunction, _subclassId, 0) == 0) {
      return false;
    }
    _hooked = hWnd;
    return true;
  }

  static int _onMessage(int hWnd, int message, int wParam, int lParam, int subclassId, int refData) {
    if (message == _wmClose && DVWindowManager.closeHidesWindow) {
      _user32!.lookupFunction<_ShowWindowN, _ShowWindowD>('ShowWindow')(hWnd, _swHide);
      return 0;
    }
    return _comctl32!.lookupFunction<_DefSubclassN, _DefSubclassD>('DefSubclassProc')(hWnd, message, wParam, lParam);
  }

  static void unregister() {
    // The subclass stays: removing it needs the window, which may be gone,
    // and it defers to DVWindowManager.closeHidesWindow on every message.
    _hooked = 0;
  }
}
