/// Win32 implementations of the `DV.Platform` bindings.
///
/// `dart:ffi` against user32 and kernel32 — no platform channels, per the
/// native integration rule. Registered only on Windows: the libraries do not
/// exist elsewhere and [register] reports false rather than throwing, so an
/// application can call it unconditionally at startup.
library dartvel_flutter.platform.windows.ffi;

import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';

import '../../../dartvel_flutter.dart' show DVNativeBridge;
import 'windows_capabilities.dart';

// user32
typedef _OpenClipboardNative = Int32 Function(IntPtr hWndNewOwner);
typedef _OpenClipboardDart = int Function(int hWndNewOwner);
typedef _CloseClipboardNative = Int32 Function();
typedef _CloseClipboardDart = int Function();
typedef _EmptyClipboardNative = Int32 Function();
typedef _EmptyClipboardDart = int Function();
typedef _SetClipboardDataNative = IntPtr Function(Uint32 format, IntPtr hMem);
typedef _SetClipboardDataDart = int Function(int format, int hMem);
typedef _GetClipboardDataNative = IntPtr Function(Uint32 format);
typedef _GetClipboardDataDart = int Function(int format);
typedef _GetSystemMetricsNative = Int32 Function(Int32 index);
typedef _GetSystemMetricsDart = int Function(int index);
typedef _SetWindowTextNative = Int32 Function(IntPtr hWnd, Pointer<Utf16> text);
typedef _SetWindowTextDart = int Function(int hWnd, Pointer<Utf16> text);
typedef _ShowWindowNative = Int32 Function(IntPtr hWnd, Int32 nCmdShow);
typedef _ShowWindowDart = int Function(int hWnd, int nCmdShow);
typedef _SetWindowPosNative = Int32 Function(IntPtr hWnd, IntPtr insertAfter,
    Int32 x, Int32 y, Int32 cx, Int32 cy, Uint32 flags);
typedef _SetWindowPosDart = int Function(int hWnd, int insertAfter, int x,
    int y, int cx, int cy, int flags);
typedef _GetActiveWindowNative = IntPtr Function();
typedef _GetActiveWindowDart = int Function();

// kernel32
typedef _GlobalAllocNative = IntPtr Function(Uint32 flags, IntPtr bytes);
typedef _GlobalAllocDart = int Function(int flags, int bytes);
typedef _GlobalLockNative = Pointer<Void> Function(IntPtr hMem);
typedef _GlobalLockDart = Pointer<Void> Function(int hMem);
typedef _GlobalUnlockNative = Int32 Function(IntPtr hMem);
typedef _GlobalUnlockDart = int Function(int hMem);

/// `CF_UNICODETEXT`. The ANSI format would mangle anything outside the active
/// code page, which is most of the world.
const int _cfUnicodeText = 13;

/// `GMEM_MOVEABLE`. The clipboard takes ownership of moveable global memory,
/// which is why the allocation is not freed here.
const int _gmemMoveable = 0x0002;

const int _smCxScreen = 0;
const int _smCyScreen = 1;

/// `SWP_NOMOVE | SWP_NOZORDER`: change the size and nothing else. Without
/// these the window jumps to 0,0 and to the front, neither of which was asked
/// for.
const int _swpNoMove = 0x0002;
const int _swpNoZOrder = 0x0004;

const int _swMaximize = 3;
const int _swMinimize = 6;
const int _swRestore = 9;

/// Registers the Windows bindings that are genuinely implemented.
class DVWindowsBindings {
  const DVWindowsBindings._();

  static bool _registered = false;
  static late DynamicLibrary _user32;
  static late DynamicLibrary _kernel32;

  static bool get isRegistered => _registered;

  static const Set<String> implemented = dvWindowsImplementedBindings;

  static bool register() {
    if (_registered) return true;
    if (!Platform.isWindows) return false;
    try {
      _user32 = DynamicLibrary.open('user32.dll');
      _kernel32 = DynamicLibrary.open('kernel32.dll');
    } on ArgumentError {
      return false;
    }

    DVNativeBridge.register('clipboard.copy', (Object? arguments) {
      final text = arguments is Map ? '${arguments['text'] ?? ''}' : '';
      return _copy(text);
    });
    DVNativeBridge.register('clipboard.paste', (Object? _) => _paste());
    DVNativeBridge.register('screen.geometry', (Object? _) => _geometry());

    DVNativeBridge.register('window.setTitle', (Object? arguments) {
      final map = arguments is Map ? arguments : const <Object?, Object?>{};
      return _setTitle('${map['title'] ?? ''}');
    });
    DVNativeBridge.register(
        'window.maximize', (Object? _) => _showWindow(_swMaximize));
    DVNativeBridge.register(
        'window.minimize', (Object? _) => _showWindow(_swMinimize));
    DVNativeBridge.register(
        'window.restore', (Object? _) => _showWindow(_swRestore));
    DVNativeBridge.register('window.setSize', (Object? arguments) {
      final map = arguments is Map ? arguments : const <Object?, Object?>{};
      final width = map['width'];
      final height = map['height'];
      // Refused rather than coerced: a resize to a nonsensical size is a
      // caller mistake, and clamping it hides the mistake behind a window
      // that is the wrong size for reasons nobody can see.
      if (width is! int || height is! int || width <= 0 || height <= 0) {
        throw ArgumentError(
          'window.setSize needs positive integer width and height, '
          'got width=$width height=$height.',
        );
      }
      return _setSize(width, height);
    });

    _registered = true;
    return true;
  }

  static void unregister() {
    for (final name in implemented) {
      DVNativeBridge.unregister(name);
    }
    _registered = false;
  }

  static bool _copy(String text) {
    final openClipboard = _user32
        .lookupFunction<_OpenClipboardNative, _OpenClipboardDart>(
            'OpenClipboard');
    final closeClipboard = _user32
        .lookupFunction<_CloseClipboardNative, _CloseClipboardDart>(
            'CloseClipboard');
    final emptyClipboard = _user32
        .lookupFunction<_EmptyClipboardNative, _EmptyClipboardDart>(
            'EmptyClipboard');
    final setClipboardData = _user32
        .lookupFunction<_SetClipboardDataNative, _SetClipboardDataDart>(
            'SetClipboardData');
    final globalAlloc =
        _kernel32.lookupFunction<_GlobalAllocNative, _GlobalAllocDart>(
            'GlobalAlloc');
    final globalLock = _kernel32
        .lookupFunction<_GlobalLockNative, _GlobalLockDart>('GlobalLock');
    final globalUnlock = _kernel32
        .lookupFunction<_GlobalUnlockNative, _GlobalUnlockDart>('GlobalUnlock');

    if (openClipboard(0) == 0) return false;
    try {
      emptyClipboard();

      // UTF-16 code units plus a terminator, in moveable global memory.
      final units = text.codeUnits;
      final bytes = (units.length + 1) * 2;
      final handle = globalAlloc(_gmemMoveable, bytes);
      if (handle == 0) return false;

      final target = globalLock(handle).cast<Uint16>();
      if (target == nullptr) return false;
      for (var i = 0; i < units.length; i++) {
        target[i] = units[i];
      }
      target[units.length] = 0;
      globalUnlock(handle);

      // On success the clipboard owns the handle, so it must not be freed
      // here — freeing it is a use-after-free the moment anything pastes.
      return setClipboardData(_cfUnicodeText, handle) != 0;
    } finally {
      closeClipboard();
    }
  }

  static String? _paste() {
    final openClipboard = _user32
        .lookupFunction<_OpenClipboardNative, _OpenClipboardDart>(
            'OpenClipboard');
    final closeClipboard = _user32
        .lookupFunction<_CloseClipboardNative, _CloseClipboardDart>(
            'CloseClipboard');
    final getClipboardData = _user32
        .lookupFunction<_GetClipboardDataNative, _GetClipboardDataDart>(
            'GetClipboardData');
    final globalLock = _kernel32
        .lookupFunction<_GlobalLockNative, _GlobalLockDart>('GlobalLock');
    final globalUnlock = _kernel32
        .lookupFunction<_GlobalUnlockNative, _GlobalUnlockDart>('GlobalUnlock');

    if (openClipboard(0) == 0) return null;
    try {
      final handle = getClipboardData(_cfUnicodeText);
      if (handle == 0) return null;
      final data = globalLock(handle).cast<Utf16>();
      if (data == nullptr) return null;
      final text = data.toDartString();
      globalUnlock(handle);
      return text;
    } finally {
      closeClipboard();
    }
  }

  static Map<String, Object?> _geometry() {
    final getSystemMetrics = _user32
        .lookupFunction<_GetSystemMetricsNative, _GetSystemMetricsDart>(
            'GetSystemMetrics');
    return <String, Object?>{
      'width': getSystemMetrics(_smCxScreen),
      'height': getSystemMetrics(_smCyScreen),
    };
  }

  /// The process's own top-level window.
  ///
  /// `GetActiveWindow` is thread-scoped and returns 0 when the calling thread
  /// owns no active window — which is a real state, not an error, and the
  /// callers below report it as failure rather than guessing at another
  /// window. Guessing is how a binding ends up retitling somebody else's app.
  static int _ownWindow() => _user32
      .lookupFunction<_GetActiveWindowNative, _GetActiveWindowDart>(
          'GetActiveWindow')();

  static bool _setTitle(String title) {
    final hWnd = _ownWindow();
    if (hWnd == 0) return false;
    final setWindowText = _user32
        .lookupFunction<_SetWindowTextNative, _SetWindowTextDart>(
            'SetWindowTextW');
    final pointer = title.toNativeUtf16();
    try {
      return setWindowText(hWnd, pointer) != 0;
    } finally {
      calloc.free(pointer);
    }
  }

  static bool _setSize(int width, int height) {
    final hWnd = _ownWindow();
    if (hWnd == 0) return false;
    final setWindowPos = _user32
        .lookupFunction<_SetWindowPosNative, _SetWindowPosDart>(
            'SetWindowPos');
    // SWP_NOMOVE and SWP_NOZORDER because only the size was asked for. Without
    // them the window also jumps to 0,0 and to the front.
    return setWindowPos(hWnd, 0, 0, 0, width, height,
            _swpNoMove | _swpNoZOrder) !=
        0;
  }

  static bool _showWindow(int command) {
    final hWnd = _ownWindow();
    if (hWnd == 0) return false;
    _user32.lookupFunction<_ShowWindowNative, _ShowWindowDart>('ShowWindow')(
        hWnd, command);
    // ShowWindow returns the *previous* visibility, so a zero return means
    // "it was hidden before", not "this failed". Reporting it as failure
    // would make the first maximise of a fresh window look broken.
    return true;
  }
}
