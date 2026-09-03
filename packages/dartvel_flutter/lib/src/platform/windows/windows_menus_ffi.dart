/// The application menu on Windows: a Win32 menu bar on the process's window.
///
/// CreateMenu and AppendMenuW build it, SetMenu puts it on the window, and
/// the window is subclassed so WM_COMMAND -- what Win32 sends when an item
/// is chosen -- reaches Dart and is dispatched by the item's id. The
/// subclass procedure is an isolate-local callable; Flutter's Windows
/// embedder runs the root isolate on the thread that owns the window, which
/// is the thread that dispatches WM_COMMAND. No window, no menu: a headless
/// start is told false rather than given a bar that went nowhere.
library;

import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../../../dartvel_flutter.dart' show DVMenus;

typedef _SubclassProcNative = IntPtr Function(
    IntPtr hWnd, Uint32 message, IntPtr wParam, IntPtr lParam, UintPtr subclassId, UintPtr refData);
typedef _SetSubclassN = Int32 Function(IntPtr, Pointer<NativeFunction<_SubclassProcNative>>, UintPtr, UintPtr);
typedef _SetSubclassD = int Function(int, Pointer<NativeFunction<_SubclassProcNative>>, int, int);
typedef _RemoveSubclassN = Int32 Function(IntPtr, Pointer<NativeFunction<_SubclassProcNative>>, UintPtr);
typedef _RemoveSubclassD = int Function(int, Pointer<NativeFunction<_SubclassProcNative>>, int);
typedef _DefSubclassN = IntPtr Function(IntPtr, Uint32, IntPtr, IntPtr);
typedef _DefSubclassD = int Function(int, int, int, int);

const int _wmCommand = 0x0111;
const int _mfString = 0x0000;
const int _mfPopup = 0x0010;
const int _mfGrayed = 0x0001;
const int _subclassId = 0x4456; // 'DV'

class DVWindowsMenus {
  const DVWindowsMenus._();

  static const Set<String> implemented = <String>{'menus.setApplicationMenu'};

  static late DynamicLibrary _user32;
  static DynamicLibrary? _comctl32;
  static NativeCallable<_SubclassProcNative>? _proc;
  static int? _subclassed;
  static int? _bar;
  static final List<String> _idsByCommand = <String>[];

  /// The window the bar was put on, for a test that reads it back.
  static int? get debugWindow => _subclassed;

  static void register(void Function(String, FutureOr<Object?> Function(Object?)) bind, {required DynamicLibrary user32}) {
    _user32 = user32;
    bind('menus.setApplicationMenu', (Object? arguments) {
      final Map<Object?, Object?> map = arguments is Map ? arguments : const <Object?, Object?>{};
      final Object? items = map['items'];
      return _install(items is List ? items : const <Object?>[]);
    });
  }

  static int _ownWindow() =>
      _user32.lookupFunction<IntPtr Function(), int Function()>('GetActiveWindow')();

  static bool _install(List<Object?> items) {
    final int hWnd = _ownWindow();
    if (hWnd == 0) return false;
    final DynamicLibrary comctl32 = _comctl32 ??= DynamicLibrary.open('comctl32.dll');

    _idsByCommand.clear();
    final int bar = _user32.lookupFunction<IntPtr Function(), int Function()>('CreateMenu')();
    for (final Object? raw in items) {
      if (raw is Map) _append(bar, raw);
    }

    final int previous = _bar ?? 0;
    _user32.lookupFunction<Int32 Function(IntPtr, IntPtr), int Function(int, int)>('SetMenu')(hWnd, bar);
    _user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('DrawMenuBar')(hWnd);
    if (previous != 0) {
      _user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('DestroyMenu')(previous);
    }
    _bar = bar;

    if (_subclassed != hWnd) {
      _unsubclass();
      final NativeCallable<_SubclassProcNative> proc =
          NativeCallable<_SubclassProcNative>.isolateLocal(_onMessage, exceptionalReturn: 0);
      if (comctl32.lookupFunction<_SetSubclassN, _SetSubclassD>('SetWindowSubclass')(
              hWnd, proc.nativeFunction, _subclassId, 0) ==
          0) {
        proc.close();
        return false;
      }
      _proc = proc;
      _subclassed = hWnd;
    }
    return true;
  }

  static void _append(int menu, Map<Object?, Object?> item) {
    final String label = '${item['label'] ?? ''}';
    final Object? children = item['children'];
    final bool leaf = children is! List || children.isEmpty;
    final appendMenu = _user32.lookupFunction<
        Int32 Function(IntPtr, Uint32, UintPtr, Pointer<Utf16>),
        int Function(int, int, int, Pointer<Utf16>)>('AppendMenuW');
    final Pointer<Utf16> text = label.toNativeUtf16();
    try {
      _idsByCommand.add('${item['id'] ?? ''}');
      final int command = _idsByCommand.length; // 1-based: 0 is "no command"
      final int flags = (leaf ? _mfString : _mfPopup) | (item['enabled'] == false ? _mfGrayed : 0);
      if (leaf) {
        appendMenu(menu, flags, command, text);
      } else {
        final int popup = _user32.lookupFunction<IntPtr Function(), int Function()>('CreatePopupMenu')();
        for (final Object? child in children) {
          if (child is Map) _append(popup, child);
        }
        appendMenu(menu, flags, popup, text);
      }
    } finally {
      calloc.free(text);
    }
  }

  static int _onMessage(int hWnd, int message, int wParam, int lParam, int subclassId, int refData) {
    if (message == _wmCommand && (wParam >> 16) & 0xFFFF == 0) {
      final int command = wParam & 0xFFFF;
      if (command >= 1 && command <= _idsByCommand.length) {
        DVMenus.dispatch(_idsByCommand[command - 1]);
        return 0;
      }
    }
    return _comctl32!.lookupFunction<_DefSubclassN, _DefSubclassD>('DefSubclassProc')(hWnd, message, wParam, lParam);
  }

  static void _unsubclass() {
    final int? hWnd = _subclassed;
    final NativeCallable<_SubclassProcNative>? proc = _proc;
    if (hWnd != null && proc != null) {
      _comctl32?.lookupFunction<_RemoveSubclassN, _RemoveSubclassD>('RemoveWindowSubclass')(
          hWnd, proc.nativeFunction, _subclassId);
    }
    proc?.close();
    _proc = null;
    _subclassed = null;
  }

  /// The bar's top-level titles as Win32 has them, for a test.
  static List<String> menuTitles(int hWnd) {
    final int bar = _user32.lookupFunction<IntPtr Function(IntPtr), int Function(int)>('GetMenu')(hWnd);
    if (bar == 0) return const <String>[];
    final int count = _user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('GetMenuItemCount')(bar);
    final getString = _user32.lookupFunction<
        Int32 Function(IntPtr, Uint32, Pointer<Utf16>, Int32, Uint32),
        int Function(int, int, Pointer<Utf16>, int, int)>('GetMenuStringW');
    final Pointer<Utf16> buffer = calloc<Uint16>(256).cast<Utf16>();
    try {
      return <String>[
        for (var i = 0; i < count; i++)
          if (getString(bar, i, buffer, 256, 0x0400 /* MF_BYPOSITION */) > 0) buffer.toDartString() else '',
      ];
    } finally {
      calloc.free(buffer);
    }
  }

  static void unregister() {
    _unsubclass();
    _idsByCommand.clear();
    _bar = null;
  }
}
