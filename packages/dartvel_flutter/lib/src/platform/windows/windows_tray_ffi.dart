/// The tray icon on Windows: Shell_NotifyIcon on the process's window.
///
/// The icon is the file the application named, loaded as an icon, else the
/// application's own; the tooltip is the notification area's; the menu is a
/// popup shown on a click, and the item chosen arrives as WM_COMMAND on the
/// window, which is subclassed for it and dispatches the item's id. No
/// window, or no notification area to put the icon in -- a session without
/// a shell -- is refusal, said rather than an icon that went nowhere.
library;

import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../../../dartvel_flutter.dart' show DVTray;

// NOTIFYICONDATAW, as Win32 x64 lays it out.
final class _NotifyIconData extends Struct {
  @Uint32()
  external int cbSize;
  @IntPtr()
  external int hWnd;
  @Uint32()
  external int uID;
  @Uint32()
  external int uFlags;
  @Uint32()
  external int uCallbackMessage;
  @IntPtr()
  external int hIcon;
  @Array(128)
  external Array<Uint16> szTip;
  @Uint32()
  external int dwState;
  @Uint32()
  external int dwStateMask;
  @Array(256)
  external Array<Uint16> szInfo;
  @Uint32()
  external int uVersion;
  @Array(64)
  external Array<Uint16> szInfoTitle;
  @Uint32()
  external int dwInfoFlags;
  @Array(16)
  external Array<Uint8> guidItem;
  @IntPtr()
  external int hBalloonIcon;
}

final class _Point extends Struct {
  @Int32()
  external int x;
  @Int32()
  external int y;
}

typedef _SubclassProcNative = IntPtr Function(
    IntPtr hWnd, Uint32 message, IntPtr wParam, IntPtr lParam, UintPtr subclassId, UintPtr refData);
typedef _SetSubclassN = Int32 Function(IntPtr, Pointer<NativeFunction<_SubclassProcNative>>, UintPtr, UintPtr);
typedef _SetSubclassD = int Function(int, Pointer<NativeFunction<_SubclassProcNative>>, int, int);
typedef _RemoveSubclassN = Int32 Function(IntPtr, Pointer<NativeFunction<_SubclassProcNative>>, UintPtr);
typedef _RemoveSubclassD = int Function(int, Pointer<NativeFunction<_SubclassProcNative>>, int);
typedef _DefSubclassN = IntPtr Function(IntPtr, Uint32, IntPtr, IntPtr);
typedef _DefSubclassD = int Function(int, int, int, int);

const int _nimAdd = 0x0;
const int _nimModify = 0x1;
const int _nimDelete = 0x2;
const int _nifMessage = 0x1;
const int _nifIcon = 0x2;
const int _nifTip = 0x4;
const int _wmCommand = 0x0111;
const int _wmApp = 0x8000;
const int _wmTrayCallback = _wmApp + 3;
const int _wmRButtonUp = 0x0205;
const int _wmLButtonUp = 0x0202;
const int _mfString = 0x0000;
const int _mfGrayed = 0x0001;
const int _tpmReturnCmd = 0x0100;
const int _subclassId = 0x4454; // 'DT'
const int _iconId = 1;
const int _idiApplication = 32512;
const int _imageIcon = 1;
const int _lrLoadFromFile = 0x0010;

/// Tray commands start above the application menu's block so the two
/// subclasses on one window cannot mistake each other's WM_COMMAND.
const int _firstCommand = 0x1000;

class DVWindowsTray {
  const DVWindowsTray._();

  static const Set<String> implemented = <String>{'tray.show', 'tray.hide'};

  static late DynamicLibrary _user32;
  static DynamicLibrary? _shell32;
  static DynamicLibrary? _comctl32;
  static NativeCallable<_SubclassProcNative>? _proc;
  static int? _window;
  static int? _menu;
  static int? _loadedIcon;
  static bool _shown = false;
  static final List<String> _idsByCommand = <String>[];

  /// Why the last show was refused, for the operator and the test.
  static String? lastError;

  /// Whether an icon is in the notification area now.
  static bool get shown => _shown;

  static void register(void Function(String, FutureOr<Object?> Function(Object?)) bind, {required DynamicLibrary user32}) {
    _user32 = user32;
    bind('tray.show', (Object? arguments) {
      final Map<Object?, Object?> map = arguments is Map ? arguments : const <Object?, Object?>{};
      return _show(
        icon: '${map['icon'] ?? ''}',
        tooltip: '${map['tooltip'] ?? ''}',
        menu: map['menu'] is List ? map['menu']! as List<Object?> : const <Object?>[],
      );
    });
    bind('tray.hide', (Object? _) {
      _hide();
      return true;
    });
  }

  static int _ownWindow() => _user32.lookupFunction<IntPtr Function(), int Function()>('GetActiveWindow')();

  static bool _show({required String icon, required String tooltip, required List<Object?> menu}) {
    final int hWnd = _window ?? _ownWindow();
    if (hWnd == 0) {
      lastError = 'no window to own the icon';
      return false;
    }
    final DynamicLibrary shell32 = _shell32 ??= DynamicLibrary.open('shell32.dll');
    final DynamicLibrary comctl32 = _comctl32 ??= DynamicLibrary.open('comctl32.dll');

    _buildMenu(menu);

    final Pointer<_NotifyIconData> data = calloc<_NotifyIconData>();
    try {
      data.ref
        ..cbSize = sizeOf<_NotifyIconData>()
        ..hWnd = hWnd
        ..uID = _iconId
        ..uFlags = _nifMessage | _nifIcon | _nifTip
        ..uCallbackMessage = _wmTrayCallback
        ..hIcon = _icon(icon);
      final List<int> units = tooltip.codeUnits.take(127).toList();
      for (var i = 0; i < units.length; i++) {
        data.ref.szTip[i] = units[i];
      }
      data.ref.szTip[units.length] = 0;

      final notify = shell32.lookupFunction<
          Int32 Function(Uint32, Pointer<_NotifyIconData>),
          int Function(int, Pointer<_NotifyIconData>)>('Shell_NotifyIconW');
      if (notify(_shown ? _nimModify : _nimAdd, data) == 0) {
        lastError = 'Shell_NotifyIcon refused: no notification area in this session';
        return false;
      }
    } finally {
      calloc.free(data);
    }

    if (_window != hWnd) {
      _unsubclass();
      final NativeCallable<_SubclassProcNative> proc =
          NativeCallable<_SubclassProcNative>.isolateLocal(_onMessage, exceptionalReturn: 0);
      if (comctl32.lookupFunction<_SetSubclassN, _SetSubclassD>('SetWindowSubclass')(hWnd, proc.nativeFunction, _subclassId, 0) == 0) {
        proc.close();
        lastError = 'the window could not be subclassed for the icon';
        return false;
      }
      _proc = proc;
      _window = hWnd;
    }
    _shown = true;
    lastError = null;
    return true;
  }

  /// The named icon file, else the application's own icon. A file that is
  /// not an icon is not an error worth refusing the tray for; the icon is
  /// the shell's default then, and the app still has a presence.
  static int _icon(String path) {
    if (_loadedIcon != null) {
      _user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('DestroyIcon')(_loadedIcon!);
      _loadedIcon = null;
    }
    if (path.isNotEmpty) {
      final Pointer<Utf16> name = path.toNativeUtf16();
      try {
        final int loaded = _user32.lookupFunction<
            IntPtr Function(IntPtr, Pointer<Utf16>, Uint32, Int32, Int32, Uint32),
            int Function(int, Pointer<Utf16>, int, int, int, int)>('LoadImageW')(0, name, _imageIcon, 0, 0, _lrLoadFromFile);
        if (loaded != 0) return _loadedIcon = loaded;
      } finally {
        calloc.free(name);
      }
    }
    return _user32.lookupFunction<IntPtr Function(IntPtr, IntPtr), int Function(int, int)>('LoadIconW')(0, _idiApplication);
  }

  static void _buildMenu(List<Object?> items) {
    final int? previous = _menu;
    if (previous != null) {
      _user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('DestroyMenu')(previous);
    }
    _idsByCommand.clear();
    final int popup = _user32.lookupFunction<IntPtr Function(), int Function()>('CreatePopupMenu')();
    final appendMenu = _user32.lookupFunction<
        Int32 Function(IntPtr, Uint32, UintPtr, Pointer<Utf16>),
        int Function(int, int, int, Pointer<Utf16>)>('AppendMenuW');
    for (final Object? raw in items) {
      if (raw is! Map) continue;
      _idsByCommand.add('${raw['id'] ?? ''}');
      final Pointer<Utf16> text = '${raw['label'] ?? ''}'.toNativeUtf16();
      try {
        appendMenu(popup, _mfString | (raw['enabled'] == false ? _mfGrayed : 0), _firstCommand + _idsByCommand.length - 1, text);
      } finally {
        calloc.free(text);
      }
    }
    _menu = popup;
  }

  /// The command id [id] is under, for a test that chooses it as Win32 would.
  static int? debugCommandFor(String id) {
    final int index = _idsByCommand.indexOf(id);
    return index < 0 ? null : _firstCommand + index;
  }

  static int _onMessage(int hWnd, int message, int wParam, int lParam, int subclassId, int refData) {
    if (message == _wmTrayCallback && (lParam == _wmRButtonUp || lParam == _wmLButtonUp)) {
      _popup(hWnd);
      return 0;
    }
    if (message == _wmCommand && (wParam >> 16) & 0xFFFF == 0) {
      final int command = wParam & 0xFFFF;
      final int index = command - _firstCommand;
      if (index >= 0 && index < _idsByCommand.length) {
        DVTray.dispatch(_idsByCommand[index]);
        return 0;
      }
    }
    return _comctl32!.lookupFunction<_DefSubclassN, _DefSubclassD>('DefSubclassProc')(hWnd, message, wParam, lParam);
  }

  /// The menu at the pointer. SetForegroundWindow first, as the notification
  /// area requires, or the menu would not go away when the user clicks off it.
  static void _popup(int hWnd) {
    final int? menu = _menu;
    if (menu == null) return;
    final Pointer<_Point> at = calloc<_Point>();
    try {
      _user32.lookupFunction<Int32 Function(Pointer<_Point>), int Function(Pointer<_Point>)>('GetCursorPos')(at);
      _user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('SetForegroundWindow')(hWnd);
      final int chosen = _user32.lookupFunction<
          Int32 Function(IntPtr, Uint32, Int32, Int32, Int32, IntPtr, Pointer<Void>),
          int Function(int, int, int, int, int, int, Pointer<Void>)>('TrackPopupMenu')(
        menu, _tpmReturnCmd, at.ref.x, at.ref.y, 0, hWnd, nullptr);
      final int index = chosen - _firstCommand;
      if (index >= 0 && index < _idsByCommand.length) DVTray.dispatch(_idsByCommand[index]);
    } finally {
      calloc.free(at);
    }
  }

  static void _hide() {
    final int? hWnd = _window;
    if (!_shown || hWnd == null) return;
    final Pointer<_NotifyIconData> data = calloc<_NotifyIconData>();
    try {
      data.ref
        ..cbSize = sizeOf<_NotifyIconData>()
        ..hWnd = hWnd
        ..uID = _iconId;
      _shell32!.lookupFunction<
          Int32 Function(Uint32, Pointer<_NotifyIconData>),
          int Function(int, Pointer<_NotifyIconData>)>('Shell_NotifyIconW')(_nimDelete, data);
    } finally {
      calloc.free(data);
    }
    _shown = false;
  }

  static void _unsubclass() {
    final int? hWnd = _window;
    final NativeCallable<_SubclassProcNative>? proc = _proc;
    if (hWnd != null && proc != null) {
      _comctl32?.lookupFunction<_RemoveSubclassN, _RemoveSubclassD>('RemoveWindowSubclass')(hWnd, proc.nativeFunction, _subclassId);
    }
    proc?.close();
    _proc = null;
    _window = null;
  }

  static void unregister() {
    _hide();
    _unsubclass();
    final int? menu = _menu;
    if (menu != null) {
      _user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('DestroyMenu')(menu);
      _menu = null;
    }
    _idsByCommand.clear();
  }
}
