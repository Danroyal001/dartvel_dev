/// The tray icon on Windows: Shell_NotifyIcon on the process's window.
///
/// The icon is the file the application named -- an .ico, or a PNG made
/// into an icon with CreateIconFromResourceEx -- else the application's
/// own; the tooltip is the notification area's; the menu is a popup of
/// separators, grayed headers, check and radio marks and submenus, shown on
/// a right-click (and on a left-click unless the application handles that
/// click itself), and the item chosen is dispatched by its number. Showing
/// again while shown is NIM_MODIFY: the same icon, changed in place. No
/// window, or no notification area to put the icon in -- a session without
/// a shell -- is refusal, said rather than an icon that went nowhere.
library;

import 'dart:async';
import 'dart:ffi';

import 'dart:io';

import 'package:ffi/ffi.dart';

import '../../../dartvel_flutter.dart' show DVTray;
import '../tray_menu.dart';
import 'windows_window_ffi.dart';

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

// MENUITEMINFOW, for the one field AppendMenu cannot set: a radio mark.
final class _MenuItemInfo extends Struct {
  @Uint32()
  external int cbSize;
  @Uint32()
  external int fMask;
  @Uint32()
  external int fType;
  @Uint32()
  external int fState;
  @Uint32()
  external int wID;
  @IntPtr()
  external int hSubMenu;
  @IntPtr()
  external int hbmpChecked;
  @IntPtr()
  external int hbmpUnchecked;
  @UintPtr()
  external int dwItemData;
  external Pointer<Utf16> dwTypeData;
  @Uint32()
  external int cch;
  @IntPtr()
  external int hbmpItem;
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
const int _mfChecked = 0x0008;
const int _mfPopup = 0x0010;
const int _mfSeparator = 0x0800;
const int _miimFType = 0x0100;
const int _mftRadioCheck = 0x0200;
const int _wmNull = 0x0000;
const int _smCxSmIcon = 49;
const int _smCySmIcon = 50;
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
  static bool _activates = false;
  static Map<int, DVTrayNode> _byNumber = const <int, DVTrayNode>{};

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
        activates: map['activate'] == true,
      );
    });
    bind('tray.hide', (Object? _) {
      _hide();
      return true;
    });
  }

  static bool _show({required String icon, required String tooltip, required List<Object?> menu, bool activates = false}) {
    // The main window even while hidden or not yet shown, which
    // GetActiveWindow cannot find: a tray-resident application shows its
    // icon with no window on screen.
    final int hWnd = _window ?? DVWindowsWindow.find(_user32);
    if (hWnd == 0) {
      lastError = 'no window to own the icon';
      return false;
    }
    final DynamicLibrary shell32 = _shell32 ??= DynamicLibrary.open('shell32.dll');
    final DynamicLibrary comctl32 = _comctl32 ??= DynamicLibrary.open('comctl32.dll');

    _buildMenu(menu);
    _activates = activates;

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
      // NIM_MODIFY when shown: the same icon, changed in place.
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

  /// The named icon file, else the application's own icon. An .ico is
  /// loaded as one; a PNG is handed to CreateIconFromResourceEx, which takes
  /// PNG data as an icon resource since Vista. A file that is neither is not
  /// worth refusing the tray for; the icon is the application's then, and
  /// the app still has a presence.
  static int _icon(String path) {
    final int? previous = _loadedIcon;
    _loadedIcon = null;
    final int loaded = _load(dvTrayIconFile(path));
    if (previous != null) {
      // Destroyed after the new one is made, so the notification area is
      // never pointed at a freed icon between the two.
      _user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('DestroyIcon')(previous);
    }
    if (loaded != 0) return _loadedIcon = loaded;
    return _user32.lookupFunction<IntPtr Function(IntPtr, IntPtr), int Function(int, int)>('LoadIconW')(0, _idiApplication);
  }

  static int _load(String? file) {
    if (file == null) return 0;
    int metric(int index) =>
        _user32.lookupFunction<Int32 Function(Int32), int Function(int)>('GetSystemMetrics')(index);
    if (file.toLowerCase().endsWith('.ico')) {
      final Pointer<Utf16> name = file.toNativeUtf16();
      try {
        return _user32.lookupFunction<
            IntPtr Function(IntPtr, Pointer<Utf16>, Uint32, Int32, Int32, Uint32),
            int Function(int, Pointer<Utf16>, int, int, int, int)>('LoadImageW')(
          0, name, _imageIcon, metric(_smCxSmIcon), metric(_smCySmIcon), _lrLoadFromFile);
      } finally {
        calloc.free(name);
      }
    }
    final List<int> bytes;
    try {
      bytes = File(file).readAsBytesSync();
    } on FileSystemException {
      return 0;
    }
    final Pointer<Uint8> buffer = calloc<Uint8>(bytes.length);
    try {
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      return _user32.lookupFunction<
          IntPtr Function(Pointer<Uint8>, Uint32, Int32, Uint32, Int32, Int32, Uint32),
          int Function(Pointer<Uint8>, int, int, int, int, int, int)>('CreateIconFromResourceEx')(
        buffer, bytes.length, 1, 0x00030000, metric(_smCxSmIcon), metric(_smCySmIcon), 0);
    } finally {
      calloc.free(buffer);
    }
  }

  static void _buildMenu(List<Object?> items) {
    final int? previous = _menu;
    if (previous != null) {
      // Destroys the submenus with it.
      _user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('DestroyMenu')(previous);
    }
    final List<DVTrayNode> nodes = DVTrayNode.parse(items);
    _byNumber = DVTrayNode.index(nodes);
    _menu = _popupOf(nodes);
  }

  /// A popup menu of [nodes]. Each leaf's command is its number above the
  /// application menu's block, so the two subclasses on one window cannot
  /// mistake each other's WM_COMMAND.
  static int _popupOf(List<DVTrayNode> nodes) {
    final int popup = _user32.lookupFunction<IntPtr Function(), int Function()>('CreatePopupMenu')();
    final appendMenu = _user32.lookupFunction<
        Int32 Function(IntPtr, Uint32, UintPtr, Pointer<Utf16>),
        int Function(int, int, int, Pointer<Utf16>)>('AppendMenuW');
    for (final DVTrayNode node in nodes) {
      if (node.kind == .separator) {
        appendMenu(popup, _mfSeparator, 0, nullptr);
        continue;
      }
      final Pointer<Utf16> text = node.label.toNativeUtf16();
      try {
        if (node.kind == .submenu) {
          appendMenu(popup, _mfPopup | _mfString, _popupOf(node.children), text);
          continue;
        }
        final int command = _firstCommand + node.number;
        appendMenu(
          popup,
          _mfString | (node.enabled ? 0 : _mfGrayed) | (node.checked == true ? _mfChecked : 0),
          command,
          text,
        );
        if (node.radio && node.checked != null) _radio(popup, command);
      } finally {
        calloc.free(text);
      }
    }
    return popup;
  }

  /// Draws [command]'s check mark as a radio dot.
  static void _radio(int popup, int command) {
    final Pointer<_MenuItemInfo> info = calloc<_MenuItemInfo>();
    try {
      info.ref
        ..cbSize = sizeOf<_MenuItemInfo>()
        ..fMask = _miimFType
        ..fType = _mftRadioCheck;
      _user32.lookupFunction<
          Int32 Function(IntPtr, Uint32, Int32, Pointer<_MenuItemInfo>),
          int Function(int, int, int, Pointer<_MenuItemInfo>)>('SetMenuItemInfoW')(popup, command, 0, info);
    } finally {
      calloc.free(info);
    }
  }

  /// The command id [id] is under, for a test that chooses it as Win32 would.
  static int? debugCommandFor(String id) {
    for (final DVTrayNode node in _byNumber.values) {
      if (node.id == id && node.kind == .item) return _firstCommand + node.number;
    }
    return null;
  }

  static bool _choose(int command) {
    final DVTrayNode? node = _byNumber[command - _firstCommand];
    if (node == null) return false;
    if (node.choosable) DVTray.dispatch(node.id);
    return true;
  }

  static int _onMessage(int hWnd, int message, int wParam, int lParam, int subclassId, int refData) {
    if (message == _wmTrayCallback) {
      if (lParam == _wmLButtonUp && _activates) {
        DVTray.activate();
        return 0;
      }
      if (lParam == _wmRButtonUp || lParam == _wmLButtonUp) {
        _popup(hWnd);
        return 0;
      }
    }
    if (message == _wmCommand && (wParam >> 16) & 0xFFFF == 0 && _choose(wParam & 0xFFFF)) {
      return 0;
    }
    return _comctl32!.lookupFunction<_DefSubclassN, _DefSubclassD>('DefSubclassProc')(hWnd, message, wParam, lParam);
  }

  /// The menu at the pointer. SetForegroundWindow first, as the notification
  /// area requires, or the menu would not go away when the user clicks off
  /// it; WM_NULL after, as the documentation for TrackPopupMenu asks.
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
      _user32.lookupFunction<Int32 Function(IntPtr, Uint32, IntPtr, IntPtr), int Function(int, int, int, int)>('PostMessageW')(
          hWnd, _wmNull, 0, 0);
      if (chosen != 0) _choose(chosen);
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
    _byNumber = const <int, DVTrayNode>{};
  }
}
