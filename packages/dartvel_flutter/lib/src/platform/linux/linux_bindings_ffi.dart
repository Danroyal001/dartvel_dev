/// Real Linux desktop native bindings, over dart:ffi.
///
/// No platform channels: the spec forbids them. These are direct calls into
/// libX11 and libgtk-3, the libraries a Flutter Linux app already links.
library dartvel_flutter.platform.linux.ffi;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../../../dartvel_flutter.dart';

// --- libX11 ------------------------------------------------------------------

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

/// Registers the Linux bindings that are genuinely implemented.
///
/// Deliberately partial. A binding this cannot implement is left
/// unregistered, so calling it still throws `DVNativeBridge`'s "not
/// registered" error rather than returning a plausible lie — an unimplemented
/// API that reports success is worse than one that fails loudly.
///
/// Implemented: `clipboard.copy`, `clipboard.paste` (GTK's CLIPBOARD
/// selection — the one other applications actually read), and
/// `screen.geometry` (X11 display dimensions).
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
  };

  static DynamicLibrary? _x11;
  static DynamicLibrary? _gtk;
  static DynamicLibrary? _gdk;
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
    } on ArgumentError {
      return false;
    }

    DVNativeBridge.register('clipboard.copy', (Object? arguments) {
      final text = arguments is Map ? '${arguments['text'] ?? ''}' : '';
      return _copy(text);
    });
    DVNativeBridge.register('clipboard.paste', (Object? _) => _paste());
    DVNativeBridge.register('screen.geometry', (Object? _) => _geometry());

    _registered = true;
    return true;
  }

  /// Unregisters everything this class registered. Intended for tests.
  static void unregister() {
    for (final name in implemented) {
      DVNativeBridge.unregister(name);
    }
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
}
