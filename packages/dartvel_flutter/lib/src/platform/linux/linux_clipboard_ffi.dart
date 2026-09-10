/// The X11 clipboard and the PRIMARY selection, over GTK.
///
/// Two things live here that did not live in the binding file this was split
/// out of.
///
/// The first is the reason for the split. On X11 a copy does not hand bytes
/// to the server; it makes this process the *owner* of a selection, and every
/// other application that wants the text sends this process a request and
/// waits for the answer. Answering happens in the GLib main loop. A process
/// that owns a selection and never iterates that loop has not merely failed
/// to share the text -- it has taken the clipboard away from the whole
/// session, because every paste anywhere now hangs until that application
/// gives up. `gtk_clipboard_wait_for_text` hides this completely from the
/// process that copied: GTK answers the owner out of its own cache, so a
/// read-back inside the same process returns the text and proves nothing.
/// That is what happened here -- copy reported success, the suite read the
/// value back, and no other application on the machine could paste it.
///
/// So a write starts a pump: a timer that drains the default GLib main
/// context. Under `flutter run` on Linux the embedder already owns that
/// context on the platform thread, and `g_main_context_iteration` returns
/// immediately without doing anything when the context belongs to another
/// thread, so the pump costs a few instructions per tick and changes nothing.
/// Where nothing else pumps -- a test, a `dartvel` command, a headless tool
/// -- it is the difference between a clipboard and a hang.
///
/// The second is the PRIMARY selection, which is the other half of the
/// specification's "clipboard and selection integration" and had no API at
/// all. On X11 and Wayland, text you highlight goes on PRIMARY and is pasted
/// with the middle mouse button, entirely separately from what Ctrl+C put on
/// CLIPBOARD. An application that reads only CLIPBOARD is invisible to half
/// of how Linux users move text around. It is X11's own idea and neither
/// Windows nor macOS has one, so those two leave these bindings unregistered
/// rather than aliasing them onto the ordinary clipboard: a `writeSelection`
/// that quietly overwrote what the user had copied would be worse than one
/// that says the platform has no such thing.
library dartvel.platform.linux.clipboard;

import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

typedef _GtkInitCheckNative =
    Int32 Function(Pointer<Int32>, Pointer<Pointer<Pointer<Utf8>>>);
typedef _GtkInitCheckDart =
    int Function(Pointer<Int32>, Pointer<Pointer<Pointer<Utf8>>>);
typedef _GdkAtomInternNative = Uint64 Function(Pointer<Utf8>, Int32);
typedef _GdkAtomInternDart = int Function(Pointer<Utf8>, int);
typedef _GtkClipboardGetNative = Pointer<Void> Function(Uint64);
typedef _GtkClipboardGetDart = Pointer<Void> Function(int);
typedef _GtkClipboardSetTextNative =
    Void Function(Pointer<Void>, Pointer<Utf8>, Int32);
typedef _GtkClipboardSetTextDart =
    void Function(Pointer<Void>, Pointer<Utf8>, int);
typedef _GtkClipboardWaitForTextNative = Pointer<Utf8> Function(Pointer<Void>);
typedef _GtkClipboardWaitForTextDart = Pointer<Utf8> Function(Pointer<Void>);
typedef _GtkClipboardStoreNative = Void Function(Pointer<Void>);
typedef _GtkClipboardStoreDart = void Function(Pointer<Void>);
typedef _GtkClipboardClearNative = Void Function(Pointer<Void>);
typedef _GtkClipboardClearDart = void Function(Pointer<Void>);
typedef _GdkSelectionOwnerGetNative = Pointer<Void> Function(Uint64);
typedef _GdkSelectionOwnerGetDart = Pointer<Void> Function(int);
typedef _GMainContextIterationNative = Int32 Function(Pointer<Void>, Int32);
typedef _GMainContextIterationDart = int Function(Pointer<Void>, int);
typedef _GFreeNative = Void Function(Pointer<Void>);
typedef _GFreeDart = void Function(Pointer<Void>);

/// GTK's two selections, by the atom names X11 knows them under.
class DVLinuxClipboard {
  const DVLinuxClipboard._();

  /// Ctrl+C and Ctrl+V.
  static const String clipboardAtom = 'CLIPBOARD';

  /// Highlight and middle-click.
  static const String primaryAtom = 'PRIMARY';

  static DynamicLibrary? _gtk;
  static DynamicLibrary? _gdk;
  static DynamicLibrary? _glib;
  static bool _gtkReady = false;
  static Timer? _pump;

  /// Whether a selection this process owns is being served.
  ///
  /// Read by the tests, which need to know the pump is the thing under test
  /// rather than a coincidence of timing.
  static bool get isPumping => _pump != null;

  /// Opens the GTK libraries. False when they are not installed, which is the
  /// headless eLinux case and not an error.
  static bool open() {
    if (_gtk != null) return true;
    try {
      _gtk = DynamicLibrary.open('libgtk-3.so.0');
      _gdk = DynamicLibrary.open('libgdk-3.so.0');
      _glib = DynamicLibrary.open('libglib-2.0.so.0');
      return true;
    } on ArgumentError {
      _gtk = null;
      _gdk = null;
      _glib = null;
      return false;
    }
  }

  /// Stops serving and forgets the libraries.
  ///
  /// Ownership goes back before the pump stops, and the order is the whole
  /// of it. Cancelling the timer while this process still owns a selection
  /// puts it straight back into the state this file exists to get out of:
  /// the display records the owner, the owner has stopped answering, and
  /// every paste anywhere on the desktop waits for a reply that is not
  /// coming. That is not a hypothetical -- it is how the two suites sharing
  /// a display found each other, one copying and unregistering while the
  /// other tried to read.
  ///
  /// The pump has to stop too. A timer left running past `unregister` keeps
  /// iterating a main context for a process that has said it is done with
  /// GTK, and in a test suite that is a timer outliving the test that made
  /// it.
  static void close() {
    if (_gtkReady && _gtk != null) {
      final _GtkClipboardClearDart clear =
          _gtk!.lookupFunction<_GtkClipboardClearNative,
              _GtkClipboardClearDart>('gtk_clipboard_clear');
      for (final String atom in <String>[clipboardAtom, primaryAtom]) {
        final Pointer<Void>? selection = _selection(atom);
        // A no-op unless this process is the owner, which is what makes it
        // safe to call for a selection somebody else holds.
        if (selection != null) clear(selection);
      }
      // The release is an X request, and it has to go out before the loop
      // that would have carried it stops. Bounded: this runs on the way out.
      final _GMainContextIterationDart iterate = _glib!.lookupFunction<
          _GMainContextIterationNative,
          _GMainContextIterationDart>('g_main_context_iteration');
      for (int i = 0; i < 64 && iterate(nullptr, 0) != 0; i++) {}
    }
    _pump?.cancel();
    _pump = null;
    _gtk = null;
    _gdk = null;
    _glib = null;
    _gtkReady = false;
  }

  /// `gtk_init_check` rather than `gtk_init`: it reports failure instead of
  /// aborting the process when there is no display.
  static bool _ensureGtk() {
    if (_gtkReady) return true;
    if (!open()) return false;
    _gtkReady =
        _gtk!.lookupFunction<_GtkInitCheckNative, _GtkInitCheckDart>(
          'gtk_init_check',
        )(nullptr, nullptr) !=
        0;
    return _gtkReady;
  }

  static int _atom(String name) {
    final Pointer<Utf8> text = name.toNativeUtf8();
    try {
      return _gdk!.lookupFunction<_GdkAtomInternNative, _GdkAtomInternDart>(
        'gdk_atom_intern',
      )(text, 0);
    } finally {
      calloc.free(text);
    }
  }

  static Pointer<Void>? _selection(String atomName) {
    if (!_ensureGtk()) return null;
    final Pointer<Void> selection = _gtk!
        .lookupFunction<_GtkClipboardGetNative, _GtkClipboardGetDart>(
          'gtk_clipboard_get',
        )(_atom(atomName));
    return selection == nullptr ? null : selection;
  }

  /// Whether this process is what the display records as the owner of
  /// [atomName].
  ///
  /// `gdk_selection_owner_get` answers with a window when the owner is one of
  /// ours and with nothing when it is anybody else's, which is the question
  /// worth asking on the way out: a process that has stopped answering and
  /// still owns the selection is the bug this file is about.
  static bool ownsSelection(String atomName) {
    if (!_ensureGtk()) return false;
    return _gdk!.lookupFunction<_GdkSelectionOwnerGetNative,
            _GdkSelectionOwnerGetDart>('gdk_selection_owner_get')(
          _atom(atomName),
        ) !=
        nullptr;
  }

  /// Starts draining the default GLib main context.
  ///
  /// Twenty milliseconds is chosen against a person waiting: a paste in
  /// another application costs at most one tick, which nobody perceives,
  /// while a tighter loop would burn a wakeup on every one of them for a
  /// clipboard that is used a handful of times an hour.
  ///
  /// The inner drain is bounded. `g_main_context_iteration` with `may_block`
  /// false returns true whenever it did any work, and a busy context could
  /// otherwise keep this loop going long enough to stall the isolate that is
  /// running the application.
  static void _startPump() {
    if (_pump != null) return;
    if (!_ensureGtk()) return;
    final _GMainContextIterationDart iterate = _glib!
        .lookupFunction<
          _GMainContextIterationNative,
          _GMainContextIterationDart
        >('g_main_context_iteration');
    _pump = Timer.periodic(const Duration(milliseconds: 20), (Timer _) {
      int drained = 0;
      while (drained < 32 && iterate(nullptr, 0) != 0) {
        drained++;
      }
    });
  }

  /// Puts [text] on the CLIPBOARD selection. False when there is no display.
  static bool copy(String text) {
    final Pointer<Void>? selection = _selection(clipboardAtom);
    if (selection == null) return false;
    final Pointer<Utf8> value = text.toNativeUtf8();
    try {
      _gtk!
          .lookupFunction<_GtkClipboardSetTextNative, _GtkClipboardSetTextDart>(
            'gtk_clipboard_set_text',
          )(selection, value, -1);
      // Before the store, not after. `gtk_clipboard_store` is a conversation
      // with the session's clipboard manager, and a conversation needs the
      // loop running to be answered.
      _startPump();
      // Hands ownership to the clipboard manager, so the value survives this
      // process exiting -- otherwise a copy vanishes when the app closes.
      _gtk!.lookupFunction<_GtkClipboardStoreNative, _GtkClipboardStoreDart>(
        'gtk_clipboard_store',
      )(selection);
      return true;
    } finally {
      calloc.free(value);
    }
  }

  /// What is on the CLIPBOARD selection, or null when it is empty.
  static String? paste() => _read(clipboardAtom);

  /// Puts [text] on the PRIMARY selection.
  ///
  /// No `gtk_clipboard_store`. PRIMARY is by definition the text currently
  /// highlighted somewhere, so it dies with the process that owns it; asking
  /// a clipboard manager to keep it would leave a stale middle-click paste
  /// pointing at a window that is gone.
  static bool writeSelection(String text) {
    final Pointer<Void>? selection = _selection(primaryAtom);
    if (selection == null) return false;
    final Pointer<Utf8> value = text.toNativeUtf8();
    try {
      _gtk!
          .lookupFunction<_GtkClipboardSetTextNative, _GtkClipboardSetTextDart>(
            'gtk_clipboard_set_text',
          )(selection, value, -1);
      _startPump();
      return true;
    } finally {
      calloc.free(value);
    }
  }

  /// What is on the PRIMARY selection, or null when nothing is highlighted
  /// anywhere on the desktop.
  static String? readSelection() => _read(primaryAtom);

  static String? _read(String atomName) {
    final Pointer<Void>? selection = _selection(atomName);
    if (selection == null) return null;
    final Pointer<Utf8> result = _gtk!
        .lookupFunction<
          _GtkClipboardWaitForTextNative,
          _GtkClipboardWaitForTextDart
        >('gtk_clipboard_wait_for_text')(selection);
    if (result == nullptr) return null;
    try {
      return result.toDartString();
    } finally {
      // The string is GTK-allocated; freeing it with g_free is the contract.
      _gtk!.lookupFunction<_GFreeNative, _GFreeDart>('g_free')(result.cast());
    }
  }
}
