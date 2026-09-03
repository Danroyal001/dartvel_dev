/// System dialogs on Linux: GtkFileChooserDialog and GtkMessageDialog.
///
/// Each dialog is built through g_object_new_with_properties -- the variadic
/// constructors have no FFI shape -- run modally, and destroyed. A test seam,
/// [DVLinuxDialogs.automate], is invoked from GTK's own loop shortly after
/// the dialog opens, so a test can pick a file and press the button the way
/// a person would, and everything but the person is exercised.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _GetTypeN = Uint64 Function();
typedef _GetTypeD = int Function();
typedef _NewWithPropsN = Pointer<Void> Function(Uint64, Uint32, Pointer<Pointer<Utf8>>, Pointer<Void>);
typedef _NewWithPropsD = Pointer<Void> Function(int, int, Pointer<Pointer<Utf8>>, Pointer<Void>);
typedef _ValueInitN = Pointer<Void> Function(Pointer<Void>, Uint64);
typedef _ValueInitD = Pointer<Void> Function(Pointer<Void>, int);
typedef _ValueSetStrN = Void Function(Pointer<Void>, Pointer<Utf8>);
typedef _ValueSetStrD = void Function(Pointer<Void>, Pointer<Utf8>);
typedef _ValueSetIntN = Void Function(Pointer<Void>, Int32);
typedef _ValueSetIntD = void Function(Pointer<Void>, int);
typedef _ValueGetStrN = Pointer<Utf8> Function(Pointer<Void>);
typedef _ValueGetStrD = Pointer<Utf8> Function(Pointer<Void>);
typedef _GetPropN = Void Function(Pointer<Void>, Pointer<Utf8>, Pointer<Void>);
typedef _GetPropD = void Function(Pointer<Void>, Pointer<Utf8>, Pointer<Void>);
typedef _PN = Void Function(Pointer<Void>);
typedef _PD = void Function(Pointer<Void>);
typedef _P_IN = Int32 Function(Pointer<Void>);
typedef _P_ID = int Function(Pointer<Void>);
typedef _P_I_VN = Void Function(Pointer<Void>, Int32);
typedef _P_I_VD = void Function(Pointer<Void>, int);
typedef _P_S_VN = Void Function(Pointer<Void>, Pointer<Utf8>);
typedef _P_S_VD = void Function(Pointer<Void>, Pointer<Utf8>);
typedef _P_S_IN = Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef _P_S_ID = int Function(Pointer<Void>, Pointer<Utf8>);
typedef _P_SN = Pointer<Utf8> Function(Pointer<Void>);
typedef _P_SD = Pointer<Utf8> Function(Pointer<Void>);
typedef _P_PN = Pointer<Void> Function(Pointer<Void>);
typedef _P_PD = Pointer<Void> Function(Pointer<Void>);
typedef _P_P_VN = Void Function(Pointer<Void>, Pointer<Void>);
typedef _P_P_VD = void Function(Pointer<Void>, Pointer<Void>);
typedef _AddButtonN = Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, Int32);
typedef _AddButtonD = Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, int);
typedef _NewN = Pointer<Void> Function();
typedef _NewD = Pointer<Void> Function();
typedef _SListLenN = Uint32 Function(Pointer<Void>);
typedef _SListLenD = int Function(Pointer<Void>);
typedef _SListNthN = Pointer<Void> Function(Pointer<Void>, Uint32);
typedef _SListNthD = Pointer<Void> Function(Pointer<Void>, int);
typedef _TimeoutCbN = Int32 Function(Pointer<Void>);
typedef _TimeoutAddN = Uint32 Function(Uint32, Pointer<NativeFunction<_TimeoutCbN>>, Pointer<Void>);
typedef _TimeoutAddD = int Function(int, Pointer<NativeFunction<_TimeoutCbN>>, Pointer<Void>);
typedef _InitCheckN = Int32 Function(Pointer<Void>, Pointer<Void>);
typedef _InitCheckD = int Function(Pointer<Void>, Pointer<Void>);

const int _responseAccept = -3;
const int _responseOk = -5;
const int _responseCancel = -6;
const int _actionOpen = 0;
const int _actionSave = 1;
const int _actionSelectFolder = 2;
const int _buttonsOk = 1;
const int _gTypeString = 16 << 2;

/// What a test sees of an open dialog.
class DVLinuxDialogSeen {
  final String? title;
  final List<String> filterLabels;
  final String? currentFolder;
  final String? currentName;
  final String? messageText;
  final bool multiple;

  const DVLinuxDialogSeen({
    this.title,
    this.filterLabels = const <String>[],
    this.currentFolder,
    this.currentName,
    this.messageText,
    this.multiple = false,
  });
}

/// A dialog that is open, as the automation hook is handed it.
class DVLinuxDialog {
  final Pointer<Void> _dialog;
  final bool _isChooser;

  DVLinuxDialog._(this._dialog, this._isChooser);

  DVLinuxDialogSeen inspect() => DVLinuxDialogs._inspect(_dialog, _isChooser);

  /// Selects [path] in a file chooser, as clicking it would. One at a time:
  /// GTK's select_filename replaces the selection rather than adding to it,
  /// so a multi-selection cannot be built through this seam -- what the
  /// multiple test checks is that the dialog allows it and that every path
  /// GTK reports comes back.
  void selectPath(String path) => DVLinuxDialogs._select(_dialog, path);

  /// What the chooser has selected right now.
  List<String> selectedPaths() => DVLinuxDialogs._selected(_dialog);

  /// Presses the affirmative button.
  void accept() => DVLinuxDialogs._respond(_dialog, _isChooser ? _responseAccept : _responseOk);

  void cancel() => DVLinuxDialogs._respond(_dialog, _responseCancel);
}

typedef DVLinuxDialogAutomation = void Function(DVLinuxDialog dialog);

// The dialog being run, for the timeout callback -- a static function --
// to hand to the automation. One modal dialog at a time.
Pointer<Void>? _current;
bool _currentIsChooser = false;
int _currentAction = -1;
DVLinuxDialogAutomation? _automation;

int _pendingResponse = 0;

int _onRespond(Pointer<Void> _) {
  final Pointer<Void>? dialog = _current;
  if (dialog != null) {
    DVLinuxDialogs._gtk!.lookupFunction<_P_I_VN, _P_I_VD>('gtk_dialog_response')(dialog, _pendingResponse);
  }
  return 0;
}

int _onAutomate(Pointer<Void> _) {
  final Pointer<Void>? dialog = _current;
  final DVLinuxDialogAutomation? run = _automation;
  if (dialog != null && run != null) run(DVLinuxDialog._(dialog, _currentIsChooser));
  return 0; // G_SOURCE_REMOVE
}

class DVLinuxDialogs {
  const DVLinuxDialogs._();

  static const Set<String> implemented = <String>{
    'dialogs.openFile',
    'dialogs.saveFile',
    'dialogs.chooseDirectory',
    'dialogs.message',
    'media.pick',
  };

  /// What the media picker offers, by kind: the open dialog with the
  /// matching filters. A desktop has no gallery; the file chooser is it.
  static const Map<String, List<String>> _mediaExtensions = <String, List<String>>{
    'image': <String>['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg'],
    'video': <String>['mp4', 'webm', 'mkv', 'mov', 'avi'],
    'audio': <String>['mp3', 'wav', 'ogg', 'flac', 'm4a'],
  };

  static DynamicLibrary? _gtk;
  static DynamicLibrary? _glib;
  static DynamicLibrary? _gobject;

  /// For tests: called from GTK's loop shortly after each dialog opens, with
  /// the dialog, to answer it. Null restores the person.
  static void automate(DVLinuxDialogAutomation? automation) => _automation = automation;

  static void register(
    DynamicLibrary gtk,
    DynamicLibrary glib,
    void Function(String, Object? Function(Object?)) bind,
  ) {
    _gtk = gtk;
    _glib = glib;
    _gobject = DynamicLibrary.open('libgobject-2.0.so.0');
    bind('dialogs.openFile', (Object? a) {
      final Map<Object?, Object?> m = a is Map ? a : const <Object?, Object?>{};
      return _chooser(m, action: _actionOpen, multiple: m['multiple'] == true, button: '_Open');
    });
    bind('dialogs.saveFile', (Object? a) {
      final Map<Object?, Object?> m = a is Map ? a : const <Object?, Object?>{};
      final Map<String, Object?> r = _chooser(m, action: _actionSave, multiple: false, button: '_Save');
      final List<Object?> paths = r['paths']! as List<Object?>;
      return <String, Object?>{'path': paths.isEmpty ? null : paths.first};
    });
    bind('dialogs.chooseDirectory', (Object? a) {
      final Map<Object?, Object?> m = a is Map ? a : const <Object?, Object?>{};
      final Map<String, Object?> r = _chooser(m, action: _actionSelectFolder, multiple: false, button: '_Select');
      final List<Object?> paths = r['paths']! as List<Object?>;
      return <String, Object?>{'path': paths.isEmpty ? null : paths.first};
    });
    bind('media.pick', (Object? a) {
      final Map<Object?, Object?> m = a is Map ? a : const <Object?, Object?>{};
      final String type = '${m['type'] ?? 'image'}';
      final List<Map<String, Object?>> filters = <Map<String, Object?>>[
        for (final MapEntry<String, List<String>> e in _mediaExtensions.entries)
          if (type == 'any' || type == e.key)
            <String, Object?>{
              'label': switch (e.key) { 'image' => 'Images', 'video' => 'Videos', _ => 'Audio' },
              'extensions': e.value,
            },
      ];
      final Map<String, Object?> r = _chooser(
        <Object?, Object?>{'title': 'Pick ${type == 'any' ? 'a file' : type == 'image' ? 'an image' : 'a $type'}', 'filters': filters},
        action: _actionOpen,
        multiple: m['multiple'] == true,
        button: '_Open',
      );
      return <Map<String, Object?>>[
        for (final Object? p in r['paths']! as List<Object?>)
          <String, Object?>{
            'path': '$p',
            'name': '$p'.split('/').last,
            'type': _typeOf('$p'),
          },
      ];
    });
    bind('dialogs.message', (Object? a) {
      final Map<Object?, Object?> m = a is Map ? a : const <Object?, Object?>{};
      _message('${m['text'] ?? ''}', title: m['title'] as String?, kind: '${m['kind'] ?? 'info'}');
      return true;
    });
  }

  static void unregister() {
    _automation = null;
    _current = null;
  }

  static String _typeOf(String path) {
    final String ext = path.contains('.') ? path.split('.').last.toLowerCase() : '';
    for (final MapEntry<String, List<String>> e in _mediaExtensions.entries) {
      if (e.value.contains(ext)) return e.key;
    }
    return 'file';
  }

  // --- building ------------------------------------------------------------

  static Pointer<Void> _gvalue(int gtype) {
    final Pointer<Void> v = calloc<Uint8>(24).cast<Void>();
    _gobject!.lookupFunction<_ValueInitN, _ValueInitD>('g_value_init')(v, gtype);
    return v;
  }

  static void _freeValue(Pointer<Void> v) {
    _gobject!.lookupFunction<_PN, _PD>('g_value_unset')(v);
    calloc.free(v);
  }

  /// `g_object_new_with_properties` over [strings] and [enums], the latter
  /// as (property, enum GType getter, value).
  static Pointer<Void> _construct(
    String typeGetter,
    Map<String, String> strings,
    List<(String, String, int)> enums,
  ) {
    final DynamicLibrary gtk = _gtk!;
    final DynamicLibrary gobject = _gobject!;
    // A dialog needs the display connection gtk_init makes; harmless when
    // the embedder has already made it.
    if (gtk.lookupFunction<_InitCheckN, _InitCheckD>('gtk_init_check')(nullptr, nullptr) == 0) {
      throw StateError('GTK could not open a display, so no dialog can be shown.');
    }
    final int type = gtk.lookupFunction<_GetTypeN, _GetTypeD>(typeGetter)();
    final int n = strings.length + enums.length;
    final Pointer<Pointer<Utf8>> names = calloc<Pointer<Utf8>>(n);
    final Pointer<Uint8> values = calloc<Uint8>(24 * n);
    final List<Pointer<Utf8>> owned = <Pointer<Utf8>>[];
    int i = 0;
    for (final MapEntry<String, String> e in strings.entries) {
      names[i] = e.key.toNativeUtf8();
      final Pointer<Void> v = (values + 24 * i).cast<Void>();
      gobject.lookupFunction<_ValueInitN, _ValueInitD>('g_value_init')(v, _gTypeString);
      final Pointer<Utf8> s = e.value.toNativeUtf8();
      owned.add(s);
      gobject.lookupFunction<_ValueSetStrN, _ValueSetStrD>('g_value_set_string')(v, s);
      i++;
    }
    for (final (String name, String enumType, int value) in enums) {
      names[i] = name.toNativeUtf8();
      final Pointer<Void> v = (values + 24 * i).cast<Void>();
      gobject.lookupFunction<_ValueInitN, _ValueInitD>('g_value_init')(
          v, gtk.lookupFunction<_GetTypeN, _GetTypeD>(enumType)());
      gobject.lookupFunction<_ValueSetIntN, _ValueSetIntD>('g_value_set_enum')(v, value);
      i++;
    }
    final Pointer<Void> object = gobject.lookupFunction<_NewWithPropsN, _NewWithPropsD>(
        'g_object_new_with_properties')(type, n, names, values.cast<Void>());
    for (int j = 0; j < n; j++) {
      gobject.lookupFunction<_PN, _PD>('g_value_unset')((values + 24 * j).cast<Void>());
      calloc.free(names[j]);
    }
    for (final Pointer<Utf8> s in owned) {
      calloc.free(s);
    }
    calloc.free(names);
    calloc.free(values);
    return object;
  }

  static int _run(Pointer<Void> dialog, {required bool chooser}) {
    final DynamicLibrary gtk = _gtk!;
    final DynamicLibrary glib = _glib!;
    _current = dialog;
    _currentIsChooser = chooser;
    if (_automation != null) {
      // Not idle: the chooser fills its folder asynchronously, and a
      // selection made before that lands on nothing.
      glib.lookupFunction<_TimeoutAddN, _TimeoutAddD>('g_timeout_add')(
          800, Pointer.fromFunction<_TimeoutCbN>(_onAutomate, 0), nullptr);
    }
    try {
      return gtk.lookupFunction<_P_IN, _P_ID>('gtk_dialog_run')(dialog);
    } finally {
      _current = null;
      gtk.lookupFunction<_PN, _PD>('gtk_widget_destroy')(dialog);
    }
  }

  static Map<String, Object?> _chooser(
    Map<Object?, Object?> m, {
    required int action,
    required bool multiple,
    required String button,
  }) {
    final DynamicLibrary gtk = _gtk!;
    final DynamicLibrary glib = _glib!;
    final Pointer<Void> dialog = _construct(
      'gtk_file_chooser_dialog_get_type',
      <String, String>{if (m['title'] is String) 'title': m['title']! as String},
      <(String, String, int)>[('action', 'gtk_file_chooser_action_get_type', action)],
    );
    _withUtf8('_Cancel', (Pointer<Utf8> s) =>
        gtk.lookupFunction<_AddButtonN, _AddButtonD>('gtk_dialog_add_button')(dialog, s, _responseCancel));
    _withUtf8(button, (Pointer<Utf8> s) =>
        gtk.lookupFunction<_AddButtonN, _AddButtonD>('gtk_dialog_add_button')(dialog, s, _responseAccept));
    if (multiple) {
      gtk.lookupFunction<_P_I_VN, _P_I_VD>('gtk_file_chooser_set_select_multiple')(dialog, 1);
    }
    final Object? initial = m['initialDirectory'];
    if (initial is String) {
      _withUtf8(initial, (Pointer<Utf8> s) =>
          gtk.lookupFunction<_P_S_IN, _P_S_ID>('gtk_file_chooser_set_current_folder')(dialog, s));
    }
    final Object? suggested = m['suggestedName'];
    if (suggested is String) {
      _withUtf8(suggested, (Pointer<Utf8> s) =>
          gtk.lookupFunction<_P_S_VN, _P_S_VD>('gtk_file_chooser_set_current_name')(dialog, s));
    }
    for (final Object? f in (m['filters'] is List ? m['filters']! as List : const <Object?>[])) {
      if (f is! Map) continue;
      final Pointer<Void> filter = gtk.lookupFunction<_NewN, _NewD>('gtk_file_filter_new')();
      _withUtf8('${f['label'] ?? ''}', (Pointer<Utf8> s) =>
          gtk.lookupFunction<_P_S_VN, _P_S_VD>('gtk_file_filter_set_name')(filter, s));
      for (final Object? ext in (f['extensions'] is List ? f['extensions']! as List : const <Object?>[])) {
        _withUtf8('*.$ext', (Pointer<Utf8> s) =>
            gtk.lookupFunction<_P_S_VN, _P_S_VD>('gtk_file_filter_add_pattern')(filter, s));
      }
      gtk.lookupFunction<_P_P_VN, _P_P_VD>('gtk_file_chooser_add_filter')(dialog, filter);
    }

    final List<String> paths = <String>[];
    _currentAction = action;
    // Read the selection before destroy: the finally in _run destroys it.
    final int response = _runReading(dialog, () {
      final Pointer<Void> list = gtk.lookupFunction<_P_PN, _P_PD>('gtk_file_chooser_get_filenames')(dialog);
      final int n = glib.lookupFunction<_SListLenN, _SListLenD>('g_slist_length')(list);
      for (int i = 0; i < n; i++) {
        final Pointer<Utf8> s = glib.lookupFunction<_SListNthN, _SListNthD>('g_slist_nth_data')(list, i).cast<Utf8>();
        if (s != nullptr) paths.add(s.toDartString());
      }
      glib.lookupFunction<_P_P_VN, _P_P_VD>('g_slist_free_full')(list, glib.lookup<NativeFunction<Void Function(Pointer<Void>)>>('g_free').cast<Void>());
      if (paths.isEmpty && action == _actionSelectFolder) {
        // Nothing highlighted means the folder being looked at.
        final Pointer<Utf8> folder = gtk.lookupFunction<_P_SN, _P_SD>('gtk_file_chooser_get_current_folder')(dialog);
        if (folder != nullptr) {
          paths.add(folder.toDartString());
          glib.lookupFunction<_PN, _PD>('g_free')(folder.cast<Void>());
        }
      }
    });
    return <String, Object?>{'paths': response == _responseAccept || response == _responseOk ? paths : const <Object?>[]};
  }

  /// Runs, and if accepted, reads before the dialog is destroyed.
  static int _runReading(Pointer<Void> dialog, void Function() read) {
    final DynamicLibrary gtk = _gtk!;
    final DynamicLibrary glib = _glib!;
    _current = dialog;
    _currentIsChooser = true;
    if (_automation != null) {
      glib.lookupFunction<_TimeoutAddN, _TimeoutAddD>('g_timeout_add')(
          800, Pointer.fromFunction<_TimeoutCbN>(_onAutomate, 0), nullptr);
    }
    try {
      final int response = gtk.lookupFunction<_P_IN, _P_ID>('gtk_dialog_run')(dialog);
      if (response == _responseAccept || response == _responseOk) read();
      return response;
    } finally {
      _current = null;
      gtk.lookupFunction<_PN, _PD>('gtk_widget_destroy')(dialog);
    }
  }

  static void _message(String text, {String? title, required String kind}) {
    final int type = switch (kind) {
      'warning' => 1,
      'question' => 2,
      'error' => 3,
      _ => 0,
    };
    final Pointer<Void> dialog = _construct(
      'gtk_message_dialog_get_type',
      <String, String>{'text': text, if (title != null) 'title': title},
      <(String, String, int)>[
        ('message-type', 'gtk_message_type_get_type', type),
        ('buttons', 'gtk_buttons_type_get_type', _buttonsOk),
      ],
    );
    _run(dialog, chooser: false);
  }

  // --- the automation's view -----------------------------------------------

  static DVLinuxDialogSeen _inspect(Pointer<Void> dialog, bool chooser) {
    final DynamicLibrary gtk = _gtk!;
    final DynamicLibrary glib = _glib!;
    final Pointer<Utf8> title = gtk.lookupFunction<_P_SN, _P_SD>('gtk_window_get_title')(dialog);
    if (!chooser) {
      final Pointer<Void> v = _gvalue(_gTypeString);
      _withUtf8('text', (Pointer<Utf8> s) =>
          _gobject!.lookupFunction<_GetPropN, _GetPropD>('g_object_get_property')(dialog, s, v));
      final Pointer<Utf8> text = _gobject!.lookupFunction<_ValueGetStrN, _ValueGetStrD>('g_value_get_string')(v);
      final DVLinuxDialogSeen seen = DVLinuxDialogSeen(
        title: title == nullptr ? null : title.toDartString(),
        messageText: text == nullptr ? null : text.toDartString(),
      );
      _freeValue(v);
      return seen;
    }
    final List<String> labels = <String>[];
    final Pointer<Void> filters = gtk.lookupFunction<_P_PN, _P_PD>('gtk_file_chooser_list_filters')(dialog);
    final int n = glib.lookupFunction<_SListLenN, _SListLenD>('g_slist_length')(filters);
    for (int i = 0; i < n; i++) {
      final Pointer<Void> f = glib.lookupFunction<_SListNthN, _SListNthD>('g_slist_nth_data')(filters, i);
      final Pointer<Utf8> name = gtk.lookupFunction<_P_SN, _P_SD>('gtk_file_filter_get_name')(f);
      if (name != nullptr) labels.add(name.toDartString());
    }
    glib.lookupFunction<_PN, _PD>('g_slist_free')(filters);
    final Pointer<Utf8> folder = gtk.lookupFunction<_P_SN, _P_SD>('gtk_file_chooser_get_current_folder')(dialog);
    // The typed-in name exists only on a save dialog; GTK asserts otherwise.
    final Pointer<Utf8> name = _currentAction == _actionSave
        ? gtk.lookupFunction<_P_SN, _P_SD>('gtk_file_chooser_get_current_name')(dialog)
        : nullptr;
    final DVLinuxDialogSeen seen = DVLinuxDialogSeen(
      title: title == nullptr ? null : title.toDartString(),
      multiple: gtk.lookupFunction<_P_IN, _P_ID>('gtk_file_chooser_get_select_multiple')(dialog) != 0,
      filterLabels: labels,
      currentFolder: folder == nullptr ? null : folder.toDartString(),
      currentName: name == nullptr ? null : name.toDartString(),
    );
    if (folder != nullptr) glib.lookupFunction<_PN, _PD>('g_free')(folder.cast<Void>());
    if (name != nullptr) glib.lookupFunction<_PN, _PD>('g_free')(name.cast<Void>());
    return seen;
  }

  static List<String> _selected(Pointer<Void> dialog) {
    final DynamicLibrary gtk = _gtk!;
    final DynamicLibrary glib = _glib!;
    final List<String> paths = <String>[];
    final Pointer<Void> list = gtk.lookupFunction<_P_PN, _P_PD>('gtk_file_chooser_get_filenames')(dialog);
    final int n = glib.lookupFunction<_SListLenN, _SListLenD>('g_slist_length')(list);
    for (int i = 0; i < n; i++) {
      final Pointer<Utf8> s = glib.lookupFunction<_SListNthN, _SListNthD>('g_slist_nth_data')(list, i).cast<Utf8>();
      if (s != nullptr) paths.add(s.toDartString());
    }
    glib.lookupFunction<_P_P_VN, _P_P_VD>('g_slist_free_full')(list, glib.lookup<NativeFunction<Void Function(Pointer<Void>)>>('g_free').cast<Void>());
    return paths;
  }

  static void _select(Pointer<Void> dialog, String path) {
    // A directory is entered, as double-clicking it would; a file is
    // selected in the folder it is in.
    final String fn = Directory(path).existsSync()
        ? 'gtk_file_chooser_set_current_folder'
        : 'gtk_file_chooser_select_filename';
    _withUtf8(path, (Pointer<Utf8> s) =>
        _gtk!.lookupFunction<_P_S_IN, _P_S_ID>(fn)(dialog, s));
  }

  /// Presses a button a moment later rather than now: a selection or a
  /// folder change the automation just made is applied by the chooser
  /// asynchronously, and a person's finger is never that fast.
  static void _respond(Pointer<Void> dialog, int response) {
    _pendingResponse = response;
    _glib!.lookupFunction<_TimeoutAddN, _TimeoutAddD>('g_timeout_add')(
        400, Pointer.fromFunction<_TimeoutCbN>(_onRespond, 0), nullptr);
  }

  static void _withUtf8(String text, void Function(Pointer<Utf8>) body) {
    final Pointer<Utf8> s = text.toNativeUtf8();
    try {
      body(s);
    } finally {
      calloc.free(s);
    }
  }
}
