/// Real Linux desktop native bindings, over dart:ffi.
///
/// No platform channels: the spec forbids them. These are direct calls into
/// libX11 and libgtk-3, the libraries a Flutter Linux app already links.
library dartvel_flutter.platform.linux.ffi;

import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../../../dartvel_flutter.dart';
import 'linux_device.dart';
import 'linux_dialogs_ffi.dart';
import 'linux_dnd_ffi.dart';
import 'linux_kiosk_ffi.dart';
import 'linux_menus_ffi.dart';
import 'linux_printing_ffi.dart';
import 'linux_serial_ffi.dart';
import 'linux_shortcuts_ffi.dart';
import 'linux_tray_dbus.dart';

// --- libX11 ------------------------------------------------------------------

typedef _VoidPN = Pointer<Void> Function();
typedef _VoidPD = Pointer<Void> Function();
typedef _GetChildN = Pointer<Void> Function(Pointer<Void>);
typedef _GetChildD = Pointer<Void> Function(Pointer<Void>);
typedef _GetXidN = Uint64 Function(Pointer<Void>);
typedef _GetXidD = int Function(Pointer<Void>);
typedef _XGrabPointerN = Int32 Function(Pointer<Void>, Uint64, Int32, Uint32, Int32, Int32, Uint64, Uint64, Uint64);
typedef _XGrabPointerD = int Function(Pointer<Void>, int, int, int, int, int, int, int, int);
typedef _XUngrabPointerN = Int32 Function(Pointer<Void>, Uint64);
typedef _XUngrabPointerD = int Function(Pointer<Void>, int);
typedef _XFlushN = Int32 Function(Pointer<Void>);
typedef _XFlushD = int Function(Pointer<Void>);
typedef _XOpenDisplayNative = Pointer<Void> Function(Pointer<Utf8>);
typedef _XOpenDisplayDart = Pointer<Void> Function(Pointer<Utf8>);
typedef _XDisplayIntNative = Int32 Function(Pointer<Void>, Int32);
typedef _XDisplayIntDart = int Function(Pointer<Void>, int);
typedef _XCloseDisplayNative = Int32 Function(Pointer<Void>);
typedef _XCloseDisplayDart = int Function(Pointer<Void>);
typedef _XDefaultScreenNative = Int32 Function(Pointer<Void>);
typedef _XDefaultScreenDart = int Function(Pointer<Void>);

// --- libgtk-3 / libgdk-3 -----------------------------------------------------

typedef _GtkInitCheckNative = Int32 Function(
  Pointer<Int32>,
  Pointer<Pointer<Pointer<Utf8>>>,
);
typedef _GtkInitCheckDart = int Function(
  Pointer<Int32>,
  Pointer<Pointer<Pointer<Utf8>>>,
);
typedef _GdkAtomInternNative = Uint64 Function(Pointer<Utf8>, Int32);
typedef _GdkAtomInternDart = int Function(Pointer<Utf8>, int);
typedef _GtkClipboardGetNative = Pointer<Void> Function(Uint64);
typedef _GtkClipboardGetDart = Pointer<Void> Function(int);
typedef _GtkClipboardSetTextNative = Void Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Int32,
);
typedef _GtkClipboardSetTextDart = void Function(
  Pointer<Void>,
  Pointer<Utf8>,
  int,
);
typedef _GtkClipboardWaitForTextNative = Pointer<Utf8> Function(Pointer<Void>);
typedef _GtkClipboardWaitForTextDart = Pointer<Utf8> Function(Pointer<Void>);
typedef _GtkClipboardStoreNative = Void Function(Pointer<Void>);
typedef _GtkClipboardStoreDart = void Function(Pointer<Void>);
typedef _GFreeNative = Void Function(Pointer<Void>);
typedef _GFreeDart = void Function(Pointer<Void>);

// --- GTK window control ------------------------------------------------------

typedef _GtkWindowListNative = Pointer<Void> Function();
typedef _GtkWindowListDart = Pointer<Void> Function();
typedef _GListLengthNative = Uint32 Function(Pointer<Void>);
typedef _GListLengthDart = int Function(Pointer<Void>);
typedef _GListNthDataNative = Pointer<Void> Function(Pointer<Void>, Uint32);
typedef _GListNthDataDart = Pointer<Void> Function(Pointer<Void>, int);
typedef _GtkWindowSetTitleNative = Void Function(Pointer<Void>, Pointer<Utf8>);
typedef _GtkWindowSetTitleDart = void Function(Pointer<Void>, Pointer<Utf8>);
typedef _GtkWindowGetTitleNative = Pointer<Utf8> Function(Pointer<Void>);
typedef _GtkWindowGetTitleDart = Pointer<Utf8> Function(Pointer<Void>);
typedef _GtkWindowActionNative = Void Function(Pointer<Void>);
typedef _GtkWindowActionDart = void Function(Pointer<Void>);
typedef _GtkWindowResizeNative = Void Function(Pointer<Void>, Int32, Int32);
typedef _GtkWindowResizeDart = void Function(Pointer<Void>, int, int);

// --- GDBus (desktop notifications) -------------------------------------------

typedef _GBusGetSyncNative = Pointer<Void> Function(
  Int32,
  Pointer<Void>,
  Pointer<Pointer<Void>>,
);
typedef _GBusGetSyncDart = Pointer<Void> Function(
  int,
  Pointer<Void>,
  Pointer<Pointer<Void>>,
);
typedef _GVariantNewParsedNative = Pointer<Void> Function(
  Pointer<Utf8>,
  Pointer<Void>,
);
typedef _GVariantNewParsedDart = Pointer<Void> Function(
  Pointer<Utf8>,
  Pointer<Void>,
);
typedef _GDBusCallSyncNative = Pointer<Void> Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Void>,
  Pointer<Void>,
  Int32,
  Int32,
  Pointer<Void>,
  Pointer<Pointer<Void>>,
);
typedef _GDBusCallSyncDart = Pointer<Void> Function(
  Pointer<Void>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Void>,
  Pointer<Void>,
  int,
  int,
  Pointer<Void>,
  Pointer<Pointer<Void>>,
);
typedef _GVariantUnrefNative = Void Function(Pointer<Void>);
typedef _GVariantUnrefDart = void Function(Pointer<Void>);
typedef _GVariantGetUint32Native = Pointer<Void> Function(
  Pointer<Void>,
  Uint64,
);
typedef _GVariantGetUint32Dart = Pointer<Void> Function(Pointer<Void>, int);
typedef _GVariantGetUint32ValueNative = Uint32 Function(Pointer<Void>);
typedef _GVariantGetUint32ValueDart = int Function(Pointer<Void>);

/// Registers the Linux bindings that are genuinely implemented.
///
/// Deliberately partial. A binding this cannot implement is left
/// unregistered, so calling it still throws `DVNativeBridge`'s "not
/// registered" error rather than returning a plausible lie — an unimplemented
/// API that reports success is worse than one that fails loudly.
///
/// Implemented: `clipboard.copy`/`clipboard.paste` (GTK's CLIPBOARD
/// selection — the one other applications actually read), `screen.geometry`
/// (X11 display dimensions), `notifications.sendLocal` (the freedesktop
/// notification service over GDBus), and `window.setTitle`/`maximize`/
/// `minimize`/`restore` (the app's own GTK toplevel).
class DVLinuxBindings {
  const DVLinuxBindings._();

  static bool _registered = false;

  /// Whether [register] has run and the libraries loaded.
  static bool get isRegistered => _registered;

  /// The binding names this platform implements. Everything else on
  /// `DV.Platform` remains unregistered on Linux.
  static const Set<String> implemented = <String>{
    'clipboard.copy',
    'clipboard.paste',
    'screen.geometry',
    'notifications.sendLocal',
    'window.setTitle',
    'window.maximize',
    'window.minimize',
    'window.restore',
    'window.setSize',
    'shortcuts.register',
    'shortcuts.unregister',
    'menus.setApplicationMenu',
    'kiosk.enforce',
    'kiosk.release',
    'printing.toFile',
    'printing.print',
    'dialogs.openFile',
    'dialogs.saveFile',
    'dialogs.chooseDirectory',
    'dialogs.message',
    'dragDrop.accept',
    'dragDrop.stop',
    // A StatusNotifierItem on the session bus, which is how a modern Linux
    // desktop is told about a tray icon.
    'tray.show',
    'tray.hide',
    'device.capabilityManifest',
    'device.health',
    'device.watchdog.arm',
    'device.watchdog.heartbeat',
    'device.fleet.provision',
    'device.diagnostics.collect',
    'device.serial.ports',
    'device.serial.open',
    'device.serial.write',
    'device.serial.read',
    'device.serial.close',
    'deepLinks.initial',
    'media.pick',
    'permissions.isGranted',
    'permissions.request',
  };


  static DynamicLibrary? _x11;
  static DynamicLibrary? _gtk;
  static DynamicLibrary? _gdk;
  static DynamicLibrary? _glib;
  static DynamicLibrary? _gio;
  static bool _gtkReady = false;

  /// Loads the libraries and registers the handlers.
  ///
  /// Returns false when the libraries are unavailable — a headless container
  /// without X11, for instance — leaving every binding unregistered rather
  /// than half-registered.
  static bool register() {
    if (_registered) return true;
    try {
      _x11 = DynamicLibrary.open('libX11.so.6');
      _gtk = DynamicLibrary.open('libgtk-3.so.0');
      _gdk = DynamicLibrary.open('libgdk-3.so.0');
      _glib = DynamicLibrary.open('libglib-2.0.so.0');
      _gio = DynamicLibrary.open('libgio-2.0.so.0');
    } on ArgumentError {
      return false;
    }

    DVNativeBridge.register('clipboard.copy', (Object? arguments) {
      final text = arguments is Map ? '${arguments['text'] ?? ''}' : '';
      return _copy(text);
    });
    DVNativeBridge.register('clipboard.paste', (Object? _) => _paste());
    DVNativeBridge.register('screen.geometry', (Object? _) => _geometry());

    DVNativeBridge.register('notifications.sendLocal', (Object? arguments) {
      // Not while a kiosk holds the screen: the in-app inbox continues, the
      // desktop banner does not.
      if (DVLinuxKiosk.suppressNotification()) return null;
      final map = arguments is Map ? arguments : const <Object?, Object?>{};
      return _notify('${map['title'] ?? ''}', '${map['body'] ?? ''}');
    });

    DVNativeBridge.register('window.setTitle', (Object? arguments) {
      final map = arguments is Map ? arguments : const <Object?, Object?>{};
      return _setWindowTitle('${map['title'] ?? ''}');
    });
    DVNativeBridge.register(
      'window.setSize',
      (Object? arguments) {
        final map = arguments is Map ? arguments : const <Object?, Object?>{};
        final width = map['width'];
        final height = map['height'];
        // Refused rather than coerced. A resize to a nonsensical size is a
        // caller mistake, and silently clamping it hides the mistake behind a
        // window that is the wrong size for reasons nobody can see.
        if (width is! int || height is! int || width <= 0 || height <= 0) {
          throw ArgumentError(
            'window.setSize needs positive integer width and height, '
            'got width=$width height=$height.',
          );
        }
        return _resize(width, height);
      },
    );
    DVNativeBridge.register(
      'window.maximize',
      (Object? _) => _windowAction('gtk_window_maximize'),
    );
    DVNativeBridge.register(
      'window.minimize',
      (Object? _) => _windowAction('gtk_window_iconify'),
    );
    DVNativeBridge.register(
      'window.restore',
      (Object? _) => _windowAction('gtk_window_unmaximize'),
    );

    // Global shortcuts: a second X connection on a pump isolate, started on
    // the first grab rather than here, so an application that never registers
    // one never opens it.
    DVLinuxShortcuts.register(DVNativeBridge.register);
    // Kiosk enforcement rides the same grabs; fullscreen is the GTK window's.
    DVLinuxKiosk.register(
      DVNativeBridge.register,
      fullscreen: () async => _windowAction('gtk_window_fullscreen'),
      confinePointer: _confinePointer,
      releasePointer: _releasePointer,
    );
    // The application menu, built into the real GTK window.
    DVLinuxMenus.register(_gtk!, _glib!, DVNativeBridge.register);
    DVLinuxPrinting.register(_gtk!, _glib!, DVNativeBridge.register);
    DVLinuxDialogs.register(_gtk!, _glib!, DVNativeBridge.register);
    DVLinuxDragDrop.register(_gtk!, _glib!, _gdk!, DVNativeBridge.register);
    // Needs a session bus rather than X11, and says so when there is none:
    // an item nothing can watch is not a failure of the other bindings.
    DVLinuxTray.register(DVNativeBridge.register);
    DVLinuxDevice.register(DVNativeBridge.register);
    DVLinuxSerial.register(DVNativeBridge.register);
    // A desktop deep link arrives as a launch argument; the launch keeps
    // the first one. The stream is fed by the launch as well.
    DVNativeBridge.register('deepLinks.initial', (Object? _) => DVAppLaunch.initialLink);
    DVNativeBridge.register('permissions.isGranted', DVDesktopPermissions.answer);
    DVNativeBridge.register('permissions.request', DVDesktopPermissions.answer);
    // A restart loop the watchdog finds goes to whatever kiosk host is on
    // screen, unless the app wired its own.
    DVLinuxDevice.onRestartLoop ??= DVKioskHost.reportRestartLoop;

    _registered = true;
    return true;
  }

  /// Unregisters everything this class registered. Intended for tests.
  static void unregister() {
    for (final name in implemented) {
      DVNativeBridge.unregister(name);
    }
    // Releases every grab. A grab left behind eats the keys for every other
    // application on the desktop until the process dies.
    unawaited(DVLinuxKiosk.unregister());
    // And takes the tray item off the bus, so a shell is not left drawing
    // an icon for a process that has gone.
    unawaited(DVLinuxTray.unregister());
    unawaited(DVLinuxShortcuts.unregister());
    DVLinuxMenus.unregister();
    DVLinuxDialogs.unregister();
    DVLinuxDevice.unregister();
    _registered = false;
  }

  /// GTK must be initialised before any clipboard call. `gtk_init_check`
  /// rather than `gtk_init`: it reports failure instead of aborting the
  /// process when there is no display.
  static bool _ensureGtk() {
    if (_gtkReady) return true;
    final initCheck = _gtk!.lookupFunction<_GtkInitCheckNative,
        _GtkInitCheckDart>('gtk_init_check');
    _gtkReady = initCheck(nullptr, nullptr) != 0;
    return _gtkReady;
  }

  static Pointer<Void>? _clipboard() {
    if (!_ensureGtk()) return null;
    final atomIntern = _gdk!
        .lookupFunction<_GdkAtomInternNative, _GdkAtomInternDart>(
      'gdk_atom_intern',
    );
    final clipboardGet = _gtk!
        .lookupFunction<_GtkClipboardGetNative, _GtkClipboardGetDart>(
      'gtk_clipboard_get',
    );
    final name = 'CLIPBOARD'.toNativeUtf8();
    try {
      final clipboard = clipboardGet(atomIntern(name, 0));
      return clipboard == nullptr ? null : clipboard;
    } finally {
      calloc.free(name);
    }
  }

  static bool _copy(String text) {
    final clipboard = _clipboard();
    if (clipboard == null) return false;
    final setText = _gtk!
        .lookupFunction<_GtkClipboardSetTextNative, _GtkClipboardSetTextDart>(
      'gtk_clipboard_set_text',
    );
    final store = _gtk!
        .lookupFunction<_GtkClipboardStoreNative, _GtkClipboardStoreDart>(
      'gtk_clipboard_store',
    );
    final value = text.toNativeUtf8();
    try {
      setText(clipboard, value, -1);
      // Hands ownership to the clipboard manager, so the value survives this
      // process exiting — otherwise a copy vanishes when the app closes.
      store(clipboard);
      return true;
    } finally {
      calloc.free(value);
    }
  }

  static String? _paste() {
    final clipboard = _clipboard();
    if (clipboard == null) return null;
    final waitForText = _gtk!.lookupFunction<_GtkClipboardWaitForTextNative,
        _GtkClipboardWaitForTextDart>('gtk_clipboard_wait_for_text');
    final result = waitForText(clipboard);
    if (result == nullptr) return null;
    try {
      return result.toDartString();
    } finally {
      // The string is GTK-allocated; freeing it with g_free is the contract.
      _gtk!.lookupFunction<_GFreeNative, _GFreeDart>('g_free')(result.cast());
    }
  }

  static Map<String, Object?>? _geometry() {
    final openDisplay = _x11!
        .lookupFunction<_XOpenDisplayNative, _XOpenDisplayDart>(
      'XOpenDisplay',
    );
    final display = openDisplay(nullptr);
    if (display == nullptr) return null;

    final defaultScreen = _x11!
        .lookupFunction<_XDefaultScreenNative, _XDefaultScreenDart>(
      'XDefaultScreen',
    );
    final width = _x11!
        .lookupFunction<_XDisplayIntNative, _XDisplayIntDart>(
      'XDisplayWidth',
    );
    final height = _x11!
        .lookupFunction<_XDisplayIntNative, _XDisplayIntDart>(
      'XDisplayHeight',
    );
    final closeDisplay = _x11!
        .lookupFunction<_XCloseDisplayNative, _XCloseDisplayDart>(
      'XCloseDisplay',
    );

    try {
      final screen = defaultScreen(display);
      return <String, Object?>{
        'width': width(display, screen),
        'height': height(display, screen),
        'screen': screen,
      };
    } finally {
      closeDisplay(display);
    }
  }

  /// The application's own GTK window.
  ///
  /// A Flutter Linux app has exactly one toplevel; taking the first is how
  /// the embedder's own code finds it. Null outside a GTK app, which is why
  /// the window bindings report failure rather than crashing in a headless
  /// process.
  static Pointer<Void>? _toplevel() {
    if (!_ensureGtk()) return null;
    final list = _gtk!
        .lookupFunction<_GtkWindowListNative, _GtkWindowListDart>(
      'gtk_window_list_toplevels',
    )();
    if (list == nullptr) return null;
    final length = _glib!
        .lookupFunction<_GListLengthNative, _GListLengthDart>(
      'g_list_length',
    )(list);
    if (length == 0) return null;
    final window = _glib!
        .lookupFunction<_GListNthDataNative, _GListNthDataDart>(
      'g_list_nth_data',
    )(list, 0);
    return window == nullptr ? null : window;
  }

  static bool _setWindowTitle(String title) {
    final window = _toplevel();
    if (window == null) return false;
    final value = title.toNativeUtf8();
    try {
      _gtk!.lookupFunction<_GtkWindowSetTitleNative, _GtkWindowSetTitleDart>(
        'gtk_window_set_title',
      )(window, value);
      return true;
    } finally {
      calloc.free(value);
    }
  }

  /// The window title GTK currently reports. Used by tests to confirm the
  /// call landed rather than trusting its return value.
  static String? currentWindowTitle() {
    final window = _toplevel();
    if (window == null) return null;
    final title = _gtk!
        .lookupFunction<_GtkWindowGetTitleNative, _GtkWindowGetTitleDart>(
      'gtk_window_get_title',
    )(window);
    // GTK owns this string; it must not be freed here.
    return title == nullptr ? null : title.toDartString();
  }

  /// Resizes the toplevel.
  ///
  /// `gtk_window_resize` sets the size the window *requests*; a tiling window
  /// manager may refuse it, and GTK reports nothing either way. So this
  /// returns whether the call was made, not whether the window ended up that
  /// size — a distinction the caller cannot learn from GTK and should not be
  /// told a guess about.
  static bool _resize(int width, int height) {
    final window = _toplevel();
    if (window == null) return false;
    _gtk!.lookupFunction<_GtkWindowResizeNative, _GtkWindowResizeDart>(
      'gtk_window_resize',
    )(window, width, height);
    return true;
  }

  /// Holds the pointer inside the toplevel: a grab on the application's own
  /// X connection with the window as the confine-to, so the application
  /// keeps receiving its events (it is the grabbing client) and the pointer
  /// cannot leave. Returns why it could not, or null.
  static String? _confinePointer() {
    final Pointer<Void>? window = _toplevel();
    if (window == null) return 'no window to confine the pointer to';
    final Pointer<Void> gdkWindow = _gtk!
        .lookupFunction<_GetChildN, _GetChildD>('gtk_widget_get_window')(window);
    if (gdkWindow == nullptr) return 'the window is not realized yet';
    final Pointer<Void> gdkDisplay =
        _gdk!.lookupFunction<_VoidPN, _VoidPD>('gdk_display_get_default')();
    final Pointer<Void> xDisplay = _gdk!
        .lookupFunction<_GetChildN, _GetChildD>('gdk_x11_display_get_xdisplay')(gdkDisplay);
    final int xid =
        _gdk!.lookupFunction<_GetXidN, _GetXidD>('gdk_x11_window_get_xid')(gdkWindow);
    // ButtonPress | ButtonRelease | PointerMotion; async modes; confine to
    // the window itself; no cursor; now.
    const int mask = 0x4 | 0x8 | 0x40;
    final int status = _x11!.lookupFunction<_XGrabPointerN, _XGrabPointerD>('XGrabPointer')(
        xDisplay, xid, 1, mask, 1, 1, xid, 0, 0);
    _x11!.lookupFunction<_XFlushN, _XFlushD>('XFlush')(xDisplay);
    return switch (status) {
      0 => null,
      1 => 'another client already holds the pointer',
      2 => 'the grab time was invalid',
      3 => 'the window is not viewable',
      4 => 'the pointer is frozen by another grab',
      _ => 'XGrabPointer returned $status',
    };
  }

  static void _releasePointer() {
    final Pointer<Void> gdkDisplay =
        _gdk!.lookupFunction<_VoidPN, _VoidPD>('gdk_display_get_default')();
    final Pointer<Void> xDisplay = _gdk!
        .lookupFunction<_GetChildN, _GetChildD>('gdk_x11_display_get_xdisplay')(gdkDisplay);
    _x11!.lookupFunction<_XUngrabPointerN, _XUngrabPointerD>('XUngrabPointer')(xDisplay, 0);
    _x11!.lookupFunction<_XFlushN, _XFlushD>('XFlush')(xDisplay);
  }

  static bool _windowAction(String symbol) {
    final window = _toplevel();
    if (window == null) return false;
    _gtk!.lookupFunction<_GtkWindowActionNative, _GtkWindowActionDart>(
      symbol,
    )(window);
    return true;
  }

  /// Sends a desktop notification through the freedesktop service.
  ///
  /// Returns the daemon's notification id, or null when no notification
  /// service is running — a headless container has none, and reporting
  /// success there would be a lie.
  static int? _notify(String title, String body) {
    final error = calloc<Pointer<Void>>();
    try {
      // G_BUS_TYPE_SESSION == 2. The system bus (1) is the wrong bus and is
      // usually absent in a desktop session.
      final bus = _gio!
          .lookupFunction<_GBusGetSyncNative, _GBusGetSyncDart>(
        'g_bus_get_sync',
      )(2, nullptr, error);
      if (bus == nullptr) return null;

      // g_variant_new_parsed avoids constructing the (susssasa{sv}i)
      // signature by hand through varargs, which dart:ffi cannot express.
      final parameters = _glib!
          .lookupFunction<_GVariantNewParsedNative, _GVariantNewParsedDart>(
        'g_variant_new_parsed',
      )(
        "('${_escapeVariant(_appName)}', uint32 0, '', "
                "'${_escapeVariant(title)}', '${_escapeVariant(body)}', "
                '@as [], @a{sv} {}, 5000)'
            .toNativeUtf8(),
        nullptr,
      );
      if (parameters == nullptr) return null;

      final reply = _gio!
          .lookupFunction<_GDBusCallSyncNative, _GDBusCallSyncDart>(
        'g_dbus_connection_call_sync',
      )(
        bus,
        _notificationsName,
        _notificationsPath,
        _notificationsName,
        _notifyMethod,
        parameters,
        nullptr,
        0,
        5000,
        nullptr,
        error,
      );
      if (reply == nullptr) return null;

      // The reply is (u); read the id back so callers can dismiss it.
      final id = _gio!
          .lookupFunction<_GVariantGetUint32Native, _GVariantGetUint32Dart>(
        'g_variant_get_child_value',
      )(reply, 0);
      final value = id == nullptr
          ? null
          : _glib!.lookupFunction<_GVariantGetUint32ValueNative,
              _GVariantGetUint32ValueDart>('g_variant_get_uint32')(id);
      _glib!.lookupFunction<_GVariantUnrefNative, _GVariantUnrefDart>(
        'g_variant_unref',
      )(reply);
      return value;
    } finally {
      calloc.free(error);
    }
  }

  /// Notification content is interpolated into a GVariant text literal, so a
  /// quote or backslash in it would otherwise change the parse.
  static String _escapeVariant(String value) =>
      value.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

  static const String _appName = 'Dartvel';
  static final Pointer<Utf8> _notificationsName =
      'org.freedesktop.Notifications'.toNativeUtf8();
  static final Pointer<Utf8> _notificationsPath =
      '/org/freedesktop/Notifications'.toNativeUtf8();
  static final Pointer<Utf8> _notifyMethod = 'Notify'.toNativeUtf8();
}
