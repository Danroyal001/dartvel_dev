/// The main window of a tray-resident application on Linux: hidden and
/// shown from the tray, and hidden rather than closed when the user closes
/// it under `exitPolicy: explicit`.
///
/// The Flutter Linux runner quits when its GtkWindow is destroyed, and GTK
/// destroys a window on delete-event unless a handler returns TRUE. So the
/// hook is a delete-event handler on the toplevel that asks
/// `DVWindowManager.closeHidesWindow`: under `explicit` it hides the window
/// and stops the event, and under every other policy it lets GTK close it
/// as before. The handler runs on the platform thread, which is the thread
/// Dart runs on in a Flutter Linux application, so it is a plain static
/// callback like the menu's.
library;

import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../../../dartvel_flutter.dart' show DVWindowManager;

typedef _DeleteCbN = Int32 Function(Pointer<Void> widget, Pointer<Void> event, Pointer<Void> data);
typedef _ConnectN = Uint64 Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<NativeFunction<_DeleteCbN>>, Pointer<Void>, Pointer<Void>, Int32);
typedef _ConnectD = int Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<NativeFunction<_DeleteCbN>>, Pointer<Void>, Pointer<Void>, int);
typedef _WidgetN = Void Function(Pointer<Void>);
typedef _WidgetD = void Function(Pointer<Void>);
typedef _WidgetIntN = Int32 Function(Pointer<Void>);
typedef _WidgetIntD = int Function(Pointer<Void>);
typedef _ListN = Pointer<Void> Function();
typedef _ListD = Pointer<Void> Function();
typedef _ListLengthN = Uint32 Function(Pointer<Void>);
typedef _ListLengthD = int Function(Pointer<Void>);
typedef _ListNthN = Pointer<Void> Function(Pointer<Void>, Uint32);
typedef _ListNthD = Pointer<Void> Function(Pointer<Void>, int);
typedef _ListFreeN = Void Function(Pointer<Void>);
typedef _ListFreeD = void Function(Pointer<Void>);

class DVLinuxWindow {
  const DVLinuxWindow._();

  static const Set<String> implemented = <String>{'window.hide', 'window.show'};

  static DynamicLibrary? _gtk;
  static DynamicLibrary? _glib;

  /// The toplevel the close hook is on, so it is connected once.
  static int _hooked = 0;

  /// Why the last call did nothing, for the operator and the test.
  static String? lastError;

  static void register(
    DynamicLibrary gtk,
    DynamicLibrary glib,
    void Function(String, FutureOr<Object?> Function(Object?)) bind,
  ) {
    _gtk = gtk;
    _glib = glib;
    bind('window.hide', (Object? _) => _call('gtk_widget_hide'));
    bind('window.show', (Object? _) {
      if (!_call('gtk_widget_show')) return false;
      // present raises it, deiconifies it and asks the window manager to
      // give it focus, which is what "Show" in a tray menu means.
      return _call('gtk_window_present');
    });
    // The runner made its window before Dart started, so it is there to
    // hook now; a test that opens its window later calls this itself.
    ensureCloseHook();
  }

  /// Connects the delete-event hook to the application's window, once.
  /// False when there is no window yet.
  static bool ensureCloseHook() {
    final Pointer<Void>? window = mainWindow();
    if (window == null) {
      lastError = 'no GTK window to hook';
      return false;
    }
    if (_hooked == window.address) return true;
    final Pointer<Utf8> signal = 'delete-event'.toNativeUtf8();
    try {
      _gtk!.lookupFunction<_ConnectN, _ConnectD>('g_signal_connect_data')(
        window,
        signal,
        Pointer.fromFunction<_DeleteCbN>(_onDelete, 0),
        nullptr,
        nullptr,
        0,
      );
    } finally {
      calloc.free(signal);
    }
    _hooked = window.address;
    return true;
  }

  static int _onDelete(Pointer<Void> widget, Pointer<Void> event, Pointer<Void> data) {
    if (!DVWindowManager.closeHidesWindow) return 0;
    _gtk!.lookupFunction<_WidgetN, _WidgetD>('gtk_widget_hide')(widget);
    // TRUE: the event is handled, so GTK does not destroy the window and
    // the runner does not quit.
    return 1;
  }

  /// The application's own window: the first GTK_WINDOW_TOPLEVEL, which
  /// skips the popup windows a menu bar's submenus are drawn in.
  static Pointer<Void>? mainWindow() {
    final DynamicLibrary? gtk = _gtk;
    final DynamicLibrary? glib = _glib;
    if (gtk == null || glib == null) return null;
    final Pointer<Void> list = gtk.lookupFunction<_ListN, _ListD>('gtk_window_list_toplevels')();
    if (list == nullptr) return null;
    try {
      final int length = glib.lookupFunction<_ListLengthN, _ListLengthD>('g_list_length')(list);
      final _ListNthD nth = glib.lookupFunction<_ListNthN, _ListNthD>('g_list_nth_data');
      final _WidgetIntD type = gtk.lookupFunction<_WidgetIntN, _WidgetIntD>('gtk_window_get_window_type');
      for (var i = 0; i < length; i++) {
        final Pointer<Void> window = nth(list, i);
        // GTK_WINDOW_TOPLEVEL is 0; GTK_WINDOW_POPUP is 1.
        if (window != nullptr && type(window) == 0) return window;
      }
      return null;
    } finally {
      glib.lookupFunction<_ListFreeN, _ListFreeD>('g_list_free')(list);
    }
  }

  /// Whether the main window is on screen, for a test.
  static bool get isVisible {
    final Pointer<Void>? window = mainWindow();
    return window != null && _gtk!.lookupFunction<_WidgetIntN, _WidgetIntD>('gtk_widget_get_visible')(window) != 0;
  }

  static bool _call(String symbol) {
    final Pointer<Void>? window = mainWindow();
    if (window == null) {
      lastError = 'no GTK window';
      return false;
    }
    ensureCloseHook();
    _gtk!.lookupFunction<_WidgetN, _WidgetD>(symbol)(window);
    return true;
  }

  static void unregister() {
    // The handler stays connected: disconnecting needs the handler id and
    // the window may be gone, and an unregistered binding leaves the
    // decision to closeHidesWindow, which reads false after reset.
    _hooked = 0;
  }
}
