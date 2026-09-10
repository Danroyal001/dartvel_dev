// Reads an X selection the way another application reads it: a second
// process, its own connection to the display, nothing shared with the process
// that put the text there.
//
// This exists because reading the clipboard back inside the process that
// wrote it proves nothing. GTK answers `gtk_clipboard_wait_for_text` from a
// cache when the calling process is the selection owner, so a clipboard that
// no other application can read passes that check and fails in front of a
// user. Only a second X client finds out.
//
// Run as `dart test/fixtures/clipboard_reader.dart CLIPBOARD` — the imports
// are `dart:` only so it needs no package resolution and no build hooks,
// which is what keeps the child process fast enough to be inside a test.
// Prints `TEXT:<value>`, `EMPTY` when the selection has no owner, or
// `NO-DISPLAY`. Hangs when the owner never answers, which is the failure the
// caller is looking for and why the caller runs it with a timeout.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

typedef _GtkInitCheckNative = Int32 Function(Pointer<Void>, Pointer<Void>);
typedef _GtkInitCheckDart = int Function(Pointer<Void>, Pointer<Void>);
typedef _GMallocNative = Pointer<Uint8> Function(Uint64);
typedef _GMallocDart = Pointer<Uint8> Function(int);
typedef _GFreeNative = Void Function(Pointer<Void>);
typedef _GFreeDart = void Function(Pointer<Void>);
typedef _GdkAtomInternNative = Uint64 Function(Pointer<Uint8>, Int32);
typedef _GdkAtomInternDart = int Function(Pointer<Uint8>, int);
typedef _GtkClipboardGetNative = Pointer<Void> Function(Uint64);
typedef _GtkClipboardGetDart = Pointer<Void> Function(int);
typedef _GtkClipboardWaitForTextNative = Pointer<Uint8> Function(Pointer<Void>);
typedef _GtkClipboardWaitForTextDart = Pointer<Uint8> Function(Pointer<Void>);

late final DynamicLibrary _gtk = DynamicLibrary.open('libgtk-3.so.0');
late final DynamicLibrary _gdk = DynamicLibrary.open('libgdk-3.so.0');
late final DynamicLibrary _glib = DynamicLibrary.open('libglib-2.0.so.0');

/// glib's allocator rather than `package:ffi`, so this file imports nothing
/// outside `dart:`.
Pointer<Uint8> _toUtf8(String value) {
  final List<int> bytes = utf8.encode(value);
  final Pointer<Uint8> buffer = _glib
      .lookupFunction<_GMallocNative, _GMallocDart>(
        'g_malloc0',
      )(bytes.length + 1);
  for (int i = 0; i < bytes.length; i++) {
    buffer[i] = bytes[i];
  }
  return buffer;
}

String _fromUtf8(Pointer<Uint8> value) {
  int length = 0;
  while (value[length] != 0) {
    length++;
  }
  return utf8.decode(List<int>.generate(length, (int i) => value[i]));
}

void main(List<String> arguments) {
  final String selection = arguments.isEmpty ? 'CLIPBOARD' : arguments.first;
  final int started = _gtk
      .lookupFunction<_GtkInitCheckNative, _GtkInitCheckDart>(
        'gtk_init_check',
      )(nullptr, nullptr);
  if (started == 0) {
    stdout.writeln('NO-DISPLAY');
    return;
  }
  final Pointer<Uint8> name = _toUtf8(selection);
  final int atom = _gdk
      .lookupFunction<_GdkAtomInternNative, _GdkAtomInternDart>(
        'gdk_atom_intern',
      )(name, 0);
  _glib.lookupFunction<_GFreeNative, _GFreeDart>('g_free')(name.cast());
  final Pointer<Void> clipboard = _gtk
      .lookupFunction<_GtkClipboardGetNative, _GtkClipboardGetDart>(
        'gtk_clipboard_get',
      )(atom);
  final Pointer<Uint8> text = _gtk
      .lookupFunction<
        _GtkClipboardWaitForTextNative,
        _GtkClipboardWaitForTextDart
      >('gtk_clipboard_wait_for_text')(clipboard);
  if (text == nullptr) {
    stdout.writeln('EMPTY');
    return;
  }
  stdout.writeln('TEXT:${_fromUtf8(text)}');
  _glib.lookupFunction<_GFreeNative, _GFreeDart>('g_free')(text.cast());
}
