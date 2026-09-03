/// Drag and drop on Linux: the window as a GTK drop target.
///
/// `gtk_drag_dest_set` makes the toplevel take drops, a target list says
/// which kinds, and `drag-data-received` carries what was dropped. The
/// payload is read as bytes and decided by its type rather than through
/// GTK's typed getters, so one path serves a file manager's `text/uri-list`
/// and a browser's text, and the same path is what the tests exercise.
///
/// The uri-list is a format rather than a platform: `file:///tmp/a%20b.txt`
/// is `/tmp/a b.txt`, a line beginning `#` is a comment, and a URI that is
/// not a file is not a path. Handing an `https:` URI on as a path would be
/// a file that does not exist.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../drag_drop.dart';

typedef _DestSetN = Void Function(Pointer<Void>, Int32, Pointer<Void>, Int32, Int32);
typedef _DestSetD = void Function(Pointer<Void>, int, Pointer<Void>, int, int);
typedef _DestUnsetN = Void Function(Pointer<Void>);
typedef _DestUnsetD = void Function(Pointer<Void>);
typedef _SetTargetListN = Void Function(Pointer<Void>, Pointer<Void>);
typedef _SetTargetListD = void Function(Pointer<Void>, Pointer<Void>);
typedef _GetTargetListN = Pointer<Void> Function(Pointer<Void>);
typedef _GetTargetListD = Pointer<Void> Function(Pointer<Void>);
typedef _TargetListNewN = Pointer<Void> Function(Pointer<Void>, Uint32);
typedef _TargetListNewD = Pointer<Void> Function(Pointer<Void>, int);
typedef _TargetListAddN = Void Function(Pointer<Void>, Uint32);
typedef _TargetListAddD = void Function(Pointer<Void>, int);
typedef _TargetListUnrefN = Void Function(Pointer<Void>);
typedef _TargetListUnrefD = void Function(Pointer<Void>);
typedef _TargetListRefN = Pointer<Void> Function(Pointer<Void>);
typedef _TargetListRefD = Pointer<Void> Function(Pointer<Void>);
typedef _TargetListNewFromTableN = Pointer<Void> Function(Pointer<_TargetEntry>, Uint32);
typedef _TargetListNewFromTableD = Pointer<Void> Function(Pointer<_TargetEntry>, int);
typedef _TableFromListN = Pointer<_TargetEntry> Function(Pointer<Void>, Pointer<Int32>);
typedef _TableFromListD = Pointer<_TargetEntry> Function(Pointer<Void>, Pointer<Int32>);
typedef _TableFreeN = Void Function(Pointer<_TargetEntry>, Int32);
typedef _TableFreeD = void Function(Pointer<_TargetEntry>, int);
typedef _AtomInternN = Pointer<Void> Function(Pointer<Utf8>, Int32);
typedef _AtomInternD = Pointer<Void> Function(Pointer<Utf8>, int);
typedef _AtomNameN = Pointer<Utf8> Function(Pointer<Void>);
typedef _AtomNameD = Pointer<Utf8> Function(Pointer<Void>);
typedef _SelDataTypeN = Pointer<Void> Function(Pointer<Void>);
typedef _SelDataTypeD = Pointer<Void> Function(Pointer<Void>);
typedef _SelDataBytesN = Pointer<Uint8> Function(Pointer<Void>, Pointer<Int32>);
typedef _SelDataBytesD = Pointer<Uint8> Function(Pointer<Void>, Pointer<Int32>);
typedef _SelDataTextN = Pointer<Utf8> Function(Pointer<Void>);
typedef _SelDataTextD = Pointer<Utf8> Function(Pointer<Void>);
typedef _SelDataSetN = Void Function(Pointer<Void>, Pointer<Void>, Int32, Pointer<Uint8>, Int32);
typedef _SelDataSetD = void Function(Pointer<Void>, Pointer<Void>, int, Pointer<Uint8>, int);
typedef _SelDataFreeN = Void Function(Pointer<Void>);
typedef _SelDataFreeD = void Function(Pointer<Void>);
typedef _DragFinishN = Void Function(Pointer<Void>, Int32, Int32, Uint32);
typedef _DragFinishD = void Function(Pointer<Void>, int, int, int);
typedef _ConnectN = Uint64 Function(Pointer<Void>, Pointer<Utf8>, Pointer<NativeFunction<_DropCbN>>, Pointer<Void>, Pointer<Void>, Int32);
typedef _ConnectD = int Function(Pointer<Void>, Pointer<Utf8>, Pointer<NativeFunction<_DropCbN>>, Pointer<Void>, Pointer<Void>, int);
typedef _DisconnectN = Void Function(Pointer<Void>, Uint64);
typedef _DisconnectD = void Function(Pointer<Void>, int);
typedef _ListN = Pointer<Void> Function();
typedef _ListD = Pointer<Void> Function();
typedef _ListLenN = Uint32 Function(Pointer<Void>);
typedef _ListLenD = int Function(Pointer<Void>);
typedef _ListNthN = Pointer<Void> Function(Pointer<Void>, Uint32);
typedef _ListNthD = Pointer<Void> Function(Pointer<Void>, int);
typedef _ClipboardGetN = Pointer<Void> Function(Pointer<Void>);
typedef _ClipboardGetD = Pointer<Void> Function(Pointer<Void>);
typedef _ClipboardSetTextN = Void Function(Pointer<Void>, Pointer<Utf8>, Int32);
typedef _ClipboardSetTextD = void Function(Pointer<Void>, Pointer<Utf8>, int);
typedef _ClipboardWaitN = Pointer<Void> Function(Pointer<Void>, Pointer<Void>);
typedef _ClipboardWaitD = Pointer<Void> Function(Pointer<Void>, Pointer<Void>);
typedef _EmitByNameN = Void Function(
    Pointer<Void>,
    Pointer<Utf8>,
    VarArgs<(Pointer<Void>, Int32, Int32, Pointer<Void>, Uint32, Uint32)>);
typedef _EmitByNameD = void Function(
    Pointer<Void>, Pointer<Utf8>, Pointer<Void>, int, int, Pointer<Void>, int, int);

/// The GTK signal's own signature: widget, context, x, y, selection data,
/// info, time, user data.
typedef _DropCbN = Void Function(
    Pointer<Void>, Pointer<Void>, Int32, Int32, Pointer<Void>, Uint32, Uint32, Pointer<Void>);

final class _TargetEntry extends Struct {
  external Pointer<Utf8> target;
  @Uint32()
  external int flags;
  @Uint32()
  external int info;
}

/// `GTK_DEST_DEFAULT_ALL`: GTK highlights the window, decides the action and
/// asks for the data, which is every part an application should not repeat.
const int _destDefaultAll = 0x07;

/// `GDK_ACTION_COPY`. A drop copies; moving a file out of a file manager on
/// someone's behalf is not a framework's decision.
const int _actionCopy = 1 << 1;

const String _uriListType = 'text/uri-list';

class DVLinuxDragDrop {
  const DVLinuxDragDrop._();

  static const Set<String> implemented = <String>{'dragDrop.accept', 'dragDrop.stop'};

  static DynamicLibrary? _gtk;
  static DynamicLibrary? _glib;
  static DynamicLibrary? _gdk;
  static DynamicLibrary? _gobject;

  /// The widget the drop target is on, and the handler's id, so stopping
  /// takes back exactly what accepting gave.
  static Pointer<Void>? _widget;
  static int _handler = 0;

  /// The target list the widget already had, kept so stopping puts it back.
  ///
  /// A GtkWindow arrives with one of GTK's own -- replacing it wholesale
  /// takes away drops GTK set up for itself, and an application that had
  /// set its own targets would lose them too.
  static Pointer<Void>? _savedTargets;

  static void register(
    DynamicLibrary gtk,
    DynamicLibrary glib,
    DynamicLibrary gdk,
    void Function(String, FutureOr<Object?> Function(Object?)) bind,
  ) {
    _gtk = gtk;
    _glib = glib;
    _gdk = gdk;
    _gobject = DynamicLibrary.open('libgobject-2.0.so.0');
    bind('dragDrop.accept', (Object? arguments) {
      final Map<Object?, Object?> map = arguments is Map ? arguments : const <Object?, Object?>{};
      final List<Object?> types = (map['types'] as List?) ?? const <Object?>['files', 'text'];
      return _accept(<String>[for (final Object? t in types) '$t']);
    });
    bind('dragDrop.stop', (Object? _) {
      _stop();
      return true;
    });
  }

  static void unregister() => _stop();

  /// The toplevel window, or null when there is none yet -- a headless
  /// start, or a test with no window.
  static Pointer<Void>? _toplevel() {
    final Pointer<Void> list = _gtk!.lookupFunction<_ListN, _ListD>('gtk_window_list_toplevels')();
    final int count = _glib!.lookupFunction<_ListLenN, _ListLenD>('g_list_length')(list);
    if (count == 0) return null;
    return _glib!.lookupFunction<_ListNthN, _ListNthD>('g_list_nth_data')(list, 0);
  }

  static Pointer<Void> _atom(String name) {
    final Pointer<Utf8> text = name.toNativeUtf8();
    try {
      return _gdk!.lookupFunction<_AtomInternN, _AtomInternD>('gdk_atom_intern')(text, 0);
    } finally {
      calloc.free(text);
    }
  }

  /// Takes drops of [types]. False when there is no window to take them,
  /// said rather than a target set on nothing.
  static bool _accept(List<String> types) {
    final Pointer<Void>? widget = _toplevel();
    if (widget == null) return false;
    _stop();

    final DynamicLibrary gtk = _gtk!;

    // What the widget already takes, kept and carried into the new list.
    final Pointer<Void> existing =
        gtk.lookupFunction<_GetTargetListN, _GetTargetListD>('gtk_drag_dest_get_target_list')(widget);
    _savedTargets = existing == nullptr
        ? null
        : gtk.lookupFunction<_TargetListRefN, _TargetListRefD>('gtk_target_list_ref')(existing);

    gtk.lookupFunction<_DestSetN, _DestSetD>('gtk_drag_dest_set')(
        widget, _destDefaultAll, nullptr, 0, _actionCopy);

    final Pointer<Void> list = _copyOf(existing);
    if (types.contains('files')) {
      gtk.lookupFunction<_TargetListAddN, _TargetListAddD>('gtk_target_list_add_uri_targets')(list, 0);
    }
    if (types.contains('text')) {
      gtk.lookupFunction<_TargetListAddN, _TargetListAddD>('gtk_target_list_add_text_targets')(list, 1);
    }
    gtk.lookupFunction<_SetTargetListN, _SetTargetListD>('gtk_drag_dest_set_target_list')(widget, list);
    gtk.lookupFunction<_TargetListUnrefN, _TargetListUnrefD>('gtk_target_list_unref')(list);

    final Pointer<Utf8> signal = 'drag-data-received'.toNativeUtf8();
    try {
      _handler = _gobject!.lookupFunction<_ConnectN, _ConnectD>('g_signal_connect_data')(
        widget,
        signal,
        Pointer.fromFunction<_DropCbN>(_onDropped),
        nullptr,
        nullptr,
        0,
      );
    } finally {
      calloc.free(signal);
    }
    _widget = widget;
    return true;
  }

  /// A new target list holding whatever [list] holds, or an empty one when
  /// there is none. GtkTargetList has no copy; its table is how it is read.
  static Pointer<Void> _copyOf(Pointer<Void> list) {
    final DynamicLibrary gtk = _gtk!;
    if (list == nullptr) {
      return gtk.lookupFunction<_TargetListNewN, _TargetListNewD>('gtk_target_list_new')(nullptr, 0);
    }
    final Pointer<Int32> count = calloc<Int32>();
    try {
      final Pointer<_TargetEntry> table =
          gtk.lookupFunction<_TableFromListN, _TableFromListD>('gtk_target_table_new_from_list')(list, count);
      if (table == nullptr) {
        return gtk.lookupFunction<_TargetListNewN, _TargetListNewD>('gtk_target_list_new')(nullptr, 0);
      }
      final Pointer<Void> copy = gtk
          .lookupFunction<_TargetListNewFromTableN, _TargetListNewFromTableD>('gtk_target_list_new')(
              table, count.value);
      gtk.lookupFunction<_TableFreeN, _TableFreeD>('gtk_target_table_free')(table, count.value);
      return copy;
    } finally {
      calloc.free(count);
    }
  }

  /// Stops taking drops, putting back what the widget took before.
  static void _stop() {
    final Pointer<Void>? widget = _widget;
    if (widget == null) return;
    final DynamicLibrary gtk = _gtk!;
    if (_handler != 0) {
      _gobject!.lookupFunction<_DisconnectN, _DisconnectD>('g_signal_handler_disconnect')(widget, _handler);
      _handler = 0;
    }
    final Pointer<Void>? saved = _savedTargets;
    if (saved != null) {
      gtk.lookupFunction<_SetTargetListN, _SetTargetListD>('gtk_drag_dest_set_target_list')(widget, saved);
      gtk.lookupFunction<_TargetListUnrefN, _TargetListUnrefD>('gtk_target_list_unref')(saved);
      _savedTargets = null;
    } else {
      gtk.lookupFunction<_DestUnsetN, _DestUnsetD>('gtk_drag_dest_unset')(widget);
    }
    _widget = null;
  }

  /// What GTK delivers when something is dropped.
  static void _onDropped(
    Pointer<Void> widget,
    Pointer<Void> context,
    int x,
    int y,
    Pointer<Void> selection,
    int info,
    int time,
    Pointer<Void> userData,
  ) {
    final DVDropEvent event = eventFrom(selection, x: x.toDouble(), y: y.toDouble());
    // The source is told the drop was taken, and told before anything the
    // application does can throw: a source left waiting shows the drag
    // still in flight over every other window.
    if (context != nullptr) {
      _gtk!.lookupFunction<_DragFinishN, _DragFinishD>('gtk_drag_finish')(
          context, event.isEmpty ? 0 : 1, 0, time);
    }
    DVDragDrop.dispatch(event);
  }

  /// The drop [selection] carries, by its type: a uri-list is files, and
  /// anything else GTK can read as text is text.
  static DVDropEvent eventFrom(Pointer<Void> selection, {double x = 0, double y = 0}) {
    if (selection == nullptr) return DVDropEvent(x: x, y: y);
    final DynamicLibrary gtk = _gtk!;
    final Pointer<Void> type =
        gtk.lookupFunction<_SelDataTypeN, _SelDataTypeD>('gtk_selection_data_get_data_type')(selection);
    final Pointer<Utf8> name =
        _gdk!.lookupFunction<_AtomNameN, _AtomNameD>('gdk_atom_name')(type);
    final String typeName = name == nullptr ? '' : name.toDartString();
    if (name != nullptr) _glib!.lookupFunction<_SelDataFreeN, _SelDataFreeD>('g_free')(name.cast());

    if (typeName == _uriListType) {
      final Pointer<Int32> length = calloc<Int32>();
      try {
        final Pointer<Uint8> bytes = gtk.lookupFunction<_SelDataBytesN, _SelDataBytesD>(
            'gtk_selection_data_get_data_with_length')(selection, length);
        if (bytes == nullptr || length.value <= 0) return DVDropEvent(x: x, y: y);
        final String uriList = utf8.decode(bytes.asTypedList(length.value), allowMalformed: true);
        return DVDropEvent(paths: pathsFromUriList(uriList), x: x, y: y);
      } finally {
        calloc.free(length);
      }
    }

    // Text, in whichever of the text encodings the source sent: GTK
    // converts them all to UTF-8 here.
    final Pointer<Utf8> text =
        gtk.lookupFunction<_SelDataTextN, _SelDataTextD>('gtk_selection_data_get_text')(selection);
    if (text == nullptr) return DVDropEvent(x: x, y: y);
    final String value = text.toDartString();
    _glib!.lookupFunction<_SelDataFreeN, _SelDataFreeD>('g_free')(text.cast());
    return DVDropEvent(text: value, x: x, y: y);
  }

  /// The file paths in a `text/uri-list` (RFC 2483).
  ///
  /// Lines are CRLF-separated, a line beginning `#` is a comment, and only
  /// `file:` URIs are paths -- a drag from a browser sends `https:` URIs,
  /// which handed on as paths would be files that do not exist. Percent
  /// escapes are decoded, so `a%20b.txt` is the file called `a b.txt`.
  static List<String> pathsFromUriList(String uriList) {
    final List<String> paths = <String>[];
    for (final String line in uriList.split(RegExp(r'\r\n|\n|\r'))) {
      final String uri = line.trim();
      if (uri.isEmpty || uri.startsWith('#')) continue;
      final Uri? parsed = Uri.tryParse(uri);
      if (parsed == null || parsed.scheme != 'file') continue;
      // A host of `localhost` is the local machine, which is where the path
      // already is; any other host is a file this machine cannot open.
      if (parsed.host.isNotEmpty && parsed.host != 'localhost') continue;
      final String path = Uri.decodeComponent(parsed.path);
      if (path.isNotEmpty) paths.add(path);
    }
    return paths;
  }

  // -- for the test -----------------------------------------------------

  /// The drop targets [widget] takes, by name.
  static List<String> targetsOf(Pointer<Void> widget) {
    final DynamicLibrary gtk = _gtk ??= DynamicLibrary.open('libgtk-3.so.0');
    final Pointer<Void> list =
        gtk.lookupFunction<_GetTargetListN, _GetTargetListD>('gtk_drag_dest_get_target_list')(widget);
    if (list == nullptr) return const <String>[];
    final Pointer<Int32> count = calloc<Int32>();
    try {
      final Pointer<_TargetEntry> table =
          gtk.lookupFunction<_TableFromListN, _TableFromListD>('gtk_target_table_new_from_list')(list, count);
      if (table == nullptr) return const <String>[];
      final List<String> names = <String>[
        for (var i = 0; i < count.value; i++) table[i].target.toDartString(),
      ];
      gtk.lookupFunction<_TableFreeN, _TableFreeD>('gtk_target_table_free')(table, count.value);
      return names;
    } finally {
      calloc.free(count);
    }
  }

  /// Emits `drag-data-received` on [widget] with a real GtkSelectionData,
  /// the way GTK emits one for a drop.
  ///
  /// The selection data comes from the clipboard because GtkSelectionData
  /// is opaque in GTK 3 and has no constructor: what is put on the
  /// clipboard comes back as one, and `gtk_selection_data_set` then gives
  /// it the type and bytes a drop would carry. Building the struct by hand
  /// instead would depend on a private layout.
  static void emitDropForTest(Pointer<Void> widget, {String? uriList, String? text, int x = 0, int y = 0}) {
    final DynamicLibrary gtk = _gtk ??= DynamicLibrary.open('libgtk-3.so.0');
    _gdk ??= DynamicLibrary.open('libgdk-3.so.0');
    _glib ??= DynamicLibrary.open('libglib-2.0.so.0');
    _gobject ??= DynamicLibrary.open('libgobject-2.0.so.0');

    final Pointer<Void> clipboard = gtk.lookupFunction<_ClipboardGetN, _ClipboardGetD>('gtk_clipboard_get')(
        _atom('CLIPBOARD'));
    final Pointer<Utf8> seed = 'dartvel'.toNativeUtf8();
    gtk.lookupFunction<_ClipboardSetTextN, _ClipboardSetTextD>('gtk_clipboard_set_text')(clipboard, seed, -1);
    calloc.free(seed);
    final Pointer<Void> selection = gtk.lookupFunction<_ClipboardWaitN, _ClipboardWaitD>(
        'gtk_clipboard_wait_for_contents')(clipboard, _atom('UTF8_STRING'));
    if (selection == nullptr) {
      throw StateError('the clipboard gave back no selection data to build the drop from');
    }

    final String payload = uriList ?? text ?? '';
    final List<int> bytes = utf8.encode(payload);
    final Pointer<Uint8> data = calloc<Uint8>(bytes.length + 1);
    try {
      data.asTypedList(bytes.length).setAll(0, bytes);
      gtk.lookupFunction<_SelDataSetN, _SelDataSetD>('gtk_selection_data_set')(
        selection,
        _atom(uriList != null ? _uriListType : 'UTF8_STRING'),
        8,
        data,
        bytes.length,
      );
      final Pointer<Utf8> signal = 'drag-data-received'.toNativeUtf8();
      try {
        _gobject!.lookupFunction<_EmitByNameN, _EmitByNameD>('g_signal_emit_by_name')(
            widget, signal, nullptr, x, y, selection, 0, 0);
      } finally {
        calloc.free(signal);
      }
    } finally {
      gtk.lookupFunction<_SelDataFreeN, _SelDataFreeD>('gtk_selection_data_free')(selection);
      calloc.free(data);
    }
  }
}
