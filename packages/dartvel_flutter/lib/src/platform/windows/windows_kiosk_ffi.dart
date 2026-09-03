/// Kiosk enforcement on Windows: escape combos held with RegisterHotKey, the
/// pointer confined with ClipCursor, the window made borderless and
/// screen-sized.
///
/// A registered hot key is routed to its owner as WM_HOTKEY instead of
/// reaching the shell, which is what blocking Alt+F4 or Ctrl+Esc means. The
/// system refuses some: Ctrl+Alt+Delete is the secure attention sequence and
/// Win+L is reserved, so those come back unenforced with Win32's reason
/// rather than as a claim -- reduced enforcement is a fact for the operator.
/// Focus Assist has no public API, so notifications are never claimed held.
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../accelerator.dart';

typedef _RegisterHotKeyNative = Int32 Function(IntPtr hWnd, Int32 id, Uint32 modifiers, Uint32 vk);
typedef _RegisterHotKeyDart = int Function(int hWnd, int id, int modifiers, int vk);
typedef _UnregisterHotKeyNative = Int32 Function(IntPtr hWnd, Int32 id);
typedef _UnregisterHotKeyDart = int Function(int hWnd, int id);
typedef _ClipCursorNative = Int32 Function(Pointer<_Rect> rect);
typedef _ClipCursorDart = int Function(Pointer<_Rect> rect);
typedef _GetWindowRectNative = Int32 Function(IntPtr hWnd, Pointer<_Rect> rect);
typedef _GetWindowRectDart = int Function(int hWnd, Pointer<_Rect> rect);
typedef _GetSystemMetricsNative = Int32 Function(Int32 index);
typedef _GetSystemMetricsDart = int Function(int index);
typedef _GetActiveWindowNative = IntPtr Function();
typedef _GetActiveWindowDart = int Function();
typedef _SetWindowLongPtrNative = IntPtr Function(IntPtr hWnd, Int32 index, IntPtr value);
typedef _SetWindowLongPtrDart = int Function(int hWnd, int index, int value);
typedef _SetWindowPosNative = Int32 Function(
    IntPtr hWnd, IntPtr insertAfter, Int32 x, Int32 y, Int32 cx, Int32 cy, Uint32 flags);
typedef _SetWindowPosDart = int Function(int hWnd, int insertAfter, int x, int y, int cx, int cy, int flags);
typedef _GetLastErrorNative = Uint32 Function();
typedef _GetLastErrorDart = int Function();

final class _Rect extends Struct {
  @Int32()
  external int left;
  @Int32()
  external int top;
  @Int32()
  external int right;
  @Int32()
  external int bottom;
}

const int _modAlt = 0x0001;
const int _modControl = 0x0002;
const int _modShift = 0x0004;
const int _modWin = 0x0008;

/// `MOD_NOREPEAT`: one WM_HOTKEY per press, not one per auto-repeat.
const int _modNoRepeat = 0x4000;

const int _smCxScreen = 0;
const int _smCyScreen = 1;

const int _gwlStyle = -16;
const int _wsPopup = 0x80000000;
const int _wsVisible = 0x10000000;
const int _swpFrameChanged = 0x0020;
const int _swpShowWindow = 0x0040;

/// Hot-key ids are per thread and 0x0000-0xBFFF are the application's; the
/// kiosk takes a block of its own so a global shortcut's id cannot collide.
const int _firstId = 0x9000;

/// `ERROR_HOTKEY_ALREADY_REGISTERED`.
const int _errorAlreadyRegistered = 1409;

class DVWindowsKiosk {
  const DVWindowsKiosk._();

  static late DynamicLibrary _user32;
  static late DynamicLibrary _kernel32;

  /// Hot-key id per combo held.
  static final Map<String, int> _held = <String, int>{};
  static int _nextId = _firstId;

  /// Why the last pointer confinement was refused, for the operator and the
  /// test.
  static String? lastConfineError;

  /// Whether ClipCursor is holding the pointer.
  static bool confined = false;

  static const Set<String> implemented = <String>{'kiosk.enforce', 'kiosk.release'};

  /// Virtual-key codes for the named keys an escape combo uses.
  static const Map<String, int> _virtualKeys = <String, int>{
    'tab': 0x09,
    'enter': 0x0D,
    'return': 0x0D,
    'escape': 0x1B,
    'esc': 0x1B,
    'space': 0x20,
    'pageup': 0x21,
    'pagedown': 0x22,
    'end': 0x23,
    'home': 0x24,
    'left': 0x25,
    'up': 0x26,
    'right': 0x27,
    'down': 0x28,
    'delete': 0x2E,
    'del': 0x2E,
  };

  /// The virtual-key code for [key], or null when Win32 has no key by that
  /// name -- reported as unenforced rather than registered as something else.
  static int? virtualKeyFor(String key) {
    final String k = key.toLowerCase();
    final int? named = _virtualKeys[k];
    if (named != null) return named;
    if (k.length == 1) {
      final int code = k.codeUnitAt(0);
      if (code >= 0x61 && code <= 0x7A) return code - 0x20; // a-z -> A-Z
      if (code >= 0x30 && code <= 0x39) return code; // 0-9
      return null;
    }
    final RegExpMatch? f = RegExp(r'^f(\d{1,2})$').firstMatch(k);
    if (f != null) {
      final int n = int.parse(f.group(1)!);
      if (n >= 1 && n <= 24) return 0x70 + n - 1;
    }
    return null;
  }

  static int modifiersFor(DVAccelerator combo) {
    var mods = _modNoRepeat;
    for (final DVModifierKey m in combo.modifiers) {
      mods |= switch (m) {
        DVModifierKey.control => _modControl,
        DVModifierKey.alt => _modAlt,
        DVModifierKey.shift => _modShift,
        DVModifierKey.meta => _modWin,
      };
    }
    return mods;
  }

  static void register(
    void Function(String, Object? Function(Object?)) bind, {
    required DynamicLibrary user32,
    required DynamicLibrary kernel32,
  }) {
    _user32 = user32;
    _kernel32 = kernel32;
    bind('kiosk.enforce', (Object? arguments) {
      final Map<Object?, Object?> map = arguments is Map ? arguments : const <Object?, Object?>{};
      release();
      final List<String> blocked = <String>[];
      final Map<String, String> unenforced = <String, String>{};
      for (final Object? raw in (map['combos'] as List?) ?? const <Object?>[]) {
        final String text = '$raw';
        final String? refusal = _hold(text);
        if (refusal == null) {
          blocked.add(text);
        } else {
          unenforced[text] = refusal;
        }
      }
      final bool wentFullscreen = map['fullscreen'] == true && _fullscreen();
      if (map['confinePointer'] == true) {
        lastConfineError = _confine();
        confined = lastConfineError == null;
      }
      return <String, Object?>{
        'blocked': blocked,
        'unenforced': unenforced,
        'fullscreen': wentFullscreen,
        'confined': confined,
        // Focus Assist has no public API. Claiming it would be a kiosk that
        // reports success and shows toasts.
        'notificationsSuppressed': false,
      };
    });
    bind('kiosk.release', (Object? _) {
      release();
      return true;
    });
  }

  /// Holds [text] as a hot key. Null when held; else why not.
  static String? _hold(String text) {
    final DVAccelerator combo;
    try {
      combo = DVAccelerator.parse(text);
    } on FormatException catch (e) {
      return e.message;
    }
    final int? vk = virtualKeyFor(combo.key);
    if (vk == null) return 'no Win32 virtual key named "${combo.key}"';
    final String canonical = combo.canonical;
    if (_held.containsKey(canonical)) return null;

    final registerHotKey =
        _user32.lookupFunction<_RegisterHotKeyNative, _RegisterHotKeyDart>('RegisterHotKey');
    final int id = _nextId++;
    if (registerHotKey(0, id, modifiersFor(combo), vk) == 0) {
      final int error = _lastError();
      return 'RegisterHotKey refused (Win32 error $error'
          '${error == _errorAlreadyRegistered ? ', already registered by another window' : ''})';
    }
    _held[canonical] = id;
    return null;
  }

  static int _lastError() =>
      _kernel32.lookupFunction<_GetLastErrorNative, _GetLastErrorDart>('GetLastError')();

  static int _ownWindow() =>
      _user32.lookupFunction<_GetActiveWindowNative, _GetActiveWindowDart>('GetActiveWindow')();

  /// Confines the pointer to the process's window, or to the screen when the
  /// thread owns no window. Null when it took; else why not.
  static String? _confine() {
    final clipCursor = _user32.lookupFunction<_ClipCursorNative, _ClipCursorDart>('ClipCursor');
    final Pointer<_Rect> rect = calloc<_Rect>();
    try {
      final int hWnd = _ownWindow();
      var haveRect = false;
      if (hWnd != 0) {
        final getWindowRect =
            _user32.lookupFunction<_GetWindowRectNative, _GetWindowRectDart>('GetWindowRect');
        haveRect = getWindowRect(hWnd, rect) != 0;
      }
      if (!haveRect) {
        final metrics =
            _user32.lookupFunction<_GetSystemMetricsNative, _GetSystemMetricsDart>('GetSystemMetrics');
        rect.ref
          ..left = 0
          ..top = 0
          ..right = metrics(_smCxScreen)
          ..bottom = metrics(_smCyScreen);
      }
      if (clipCursor(rect) == 0) return 'ClipCursor refused (Win32 error ${_lastError()})';
      return null;
    } finally {
      calloc.free(rect);
    }
  }

  /// Borderless and screen-sized. False when the thread owns no window: a
  /// harness has none, and claiming fullscreen there would be claiming a
  /// window.
  static bool _fullscreen() {
    final int hWnd = _ownWindow();
    if (hWnd == 0) return false;
    final setStyle =
        _user32.lookupFunction<_SetWindowLongPtrNative, _SetWindowLongPtrDart>('SetWindowLongPtrW');
    final setPos = _user32.lookupFunction<_SetWindowPosNative, _SetWindowPosDart>('SetWindowPos');
    final metrics =
        _user32.lookupFunction<_GetSystemMetricsNative, _GetSystemMetricsDart>('GetSystemMetrics');
    setStyle(hWnd, _gwlStyle, _wsPopup | _wsVisible);
    return setPos(hWnd, 0, 0, 0, metrics(_smCxScreen), metrics(_smCyScreen),
            _swpFrameChanged | _swpShowWindow) !=
        0;
  }

  /// Lets go of every hot key and the pointer.
  static void release() {
    final unregisterHotKey =
        _user32.lookupFunction<_UnregisterHotKeyNative, _UnregisterHotKeyDart>('UnregisterHotKey');
    for (final int id in _held.values) {
      unregisterHotKey(0, id);
    }
    _held.clear();
    if (confined) {
      _user32.lookupFunction<_ClipCursorNative, _ClipCursorDart>('ClipCursor')(nullptr);
      confined = false;
    }
  }

  /// Every combo currently held, canonical.
  static List<String> get held => List<String>.unmodifiable(_held.keys);
}
