/// System dialogs on macOS: NSOpenPanel, NSSavePanel and NSAlert.
///
/// Each runs modally on the main thread, which is where Flutter runs the
/// root isolate on macOS. Under automation a timer is added to the modal
/// panel run-loop mode before the panel runs, so it fires inside the
/// panel's own loop; its target is the runtime-defined object the
/// application menu uses, under an action that hands the panel to the
/// automation, which answers the way a person would -- a name typed, OK
/// pressed. Without automation the panel waits for the person.
library;

import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'macos_menus_ffi.dart';

typedef _ActionN = Void Function(Pointer<Void> self, Pointer<Void> cmd, Pointer<Void> sender);
typedef _AddMethodN = Bool Function(Pointer<Void>, Pointer<Void>, Pointer<NativeFunction<_ActionN>>, Pointer<Utf8>);
typedef _AddMethodD = bool Function(Pointer<Void>, Pointer<Void>, Pointer<NativeFunction<_ActionN>>, Pointer<Utf8>);
typedef _ReplaceMethodN = Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<NativeFunction<_ActionN>>, Pointer<Utf8>);
typedef _ReplaceMethodD = Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<NativeFunction<_ActionN>>, Pointer<Utf8>);
typedef _TimerN = Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Double, Pointer<Void>, Pointer<Void>, Pointer<Void>, Bool);
typedef _TimerD = Pointer<Void> Function(Pointer<Void>, Pointer<Void>, double, Pointer<Void>, Pointer<Void>, Pointer<Void>, bool);
typedef _Send2N = Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<Void>, Pointer<Void>);
typedef _Send2D = Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<Void>, Pointer<Void>);
typedef _GetUtf8N = Pointer<Utf8> Function(Pointer<Void>, Pointer<Void>);
typedef _GetUtf8D = Pointer<Utf8> Function(Pointer<Void>, Pointer<Void>);

const int _modalResponseOk = 1;

/// `NSModalResponseCancel`.
const int _modalResponseCancel = 0;

/// What the dialog showed, for a test.
class DVMacosDialogSeen {
  const DVMacosDialogSeen({this.title, this.filterLabels = const <String>[], this.currentFolder, this.currentName, this.messageText});
  final String? title;
  final List<String> filterLabels;
  final String? currentFolder;
  final String? currentName;
  final String? messageText;
}

enum _DialogKind { open, save, folder, message }

/// A panel on screen, answerable from the modal loop.
class DVMacosDialog {
  DVMacosDialog._(this._panel, this._kind);

  final Pointer<Void> _panel;
  final _DialogKind _kind;

  DVMacosDialogSeen inspect() => DVMacosDialogs._inspect(_panel, _kind);

  /// For a panel: the directory shown, and the name typed, taken from
  /// [path]. A path that is a directory is shown; a file is shown in its
  /// directory with its name typed.
  void selectPath(String path) => DVMacosDialogs._select(_panel, _kind, path);

  void accept() => DVMacosDialogs._answer(_panel, _kind, ok: true);
  void cancel() => DVMacosDialogs._answer(_panel, _kind, ok: false);
}

typedef DVMacosDialogAutomation = void Function(DVMacosDialog dialog);

class DVMacosDialogs {
  const DVMacosDialogs._();

  static const Set<String> implemented = <String>{
    'dialogs.openFile',
    'dialogs.saveFile',
    'dialogs.chooseDirectory',
    'dialogs.message',
    'media.pick',
  };

  static const Map<String, List<String>> _mediaExtensions = <String, List<String>>{
    'image': <String>['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg'],
    'video': <String>['mp4', 'webm', 'mkv', 'mov', 'avi'],
    'audio': <String>['mp3', 'wav', 'ogg', 'flac', 'm4a'],
  };

  static DynamicLibrary? _objc;
  static DynamicLibrary get _appKit => DynamicLibrary.open('/System/Library/Frameworks/AppKit.framework/AppKit');
  static DVMacosDialogAutomation? _automation;
  static NativeCallable<_ActionN>? _timerAction;
  static Pointer<Void>? _current;
  static _DialogKind _currentKind = _DialogKind.open;
  static List<String> _filterLabels = const <String>[];

  /// For tests: called from the panel's own modal loop once it runs, with
  /// the panel, to answer it. Null restores the person.
  static void automate(DVMacosDialogAutomation? automation) => _automation = automation;

  static DVMacosObjc get _o => DVMacosObjc(_objc!);

  static void register(void Function(String, FutureOr<Object?> Function(Object?)) bind, {required DynamicLibrary objc}) {
    _objc = objc;
    bind('dialogs.openFile', (Object? a) {
      final Map<Object?, Object?> m = a is Map ? a : const <Object?, Object?>{};
      return <String, Object?>{'paths': _openPanel(m, directories: false, multiple: m['multiple'] == true)};
    });
    bind('dialogs.saveFile', (Object? a) {
      final Map<Object?, Object?> m = a is Map ? a : const <Object?, Object?>{};
      return <String, Object?>{'path': _savePanel(m)};
    });
    bind('dialogs.chooseDirectory', (Object? a) {
      final Map<Object?, Object?> m = a is Map ? a : const <Object?, Object?>{};
      final List<String> paths = _openPanel(m, directories: true, multiple: false);
      return <String, Object?>{'path': paths.isEmpty ? null : paths.first};
    });
    bind('dialogs.message', (Object? a) {
      final Map<Object?, Object?> m = a is Map ? a : const <Object?, Object?>{};
      _alert('${m['text'] ?? ''}', title: m['title'] as String?, kind: '${m['kind'] ?? 'info'}');
      return true;
    });
    bind('media.pick', (Object? a) {
      final Map<Object?, Object?> m = a is Map ? a : const <Object?, Object?>{};
      final String type = '${m['type'] ?? 'image'}';
      final List<Map<String, Object?>> filters = <Map<String, Object?>>[
        for (final MapEntry<String, List<String>> e in _mediaExtensions.entries)
          if (type == 'any' || type == e.key)
            <String, Object?>{'label': switch (e.key) { 'image' => 'Images', 'video' => 'Videos', _ => 'Audio' }, 'extensions': e.value},
      ];
      final List<String> paths = _openPanel(
        <Object?, Object?>{'title': 'Pick ${type == 'any' ? 'a file' : type == 'image' ? 'an image' : 'a $type'}', 'filters': filters},
        directories: false,
        multiple: m['multiple'] == true,
      );
      return <Map<String, Object?>>[
        for (final String p in paths) <String, Object?>{'path': p, 'name': p.split('/').last, 'type': _typeOf(p)},
      ];
    });
  }

  static String _typeOf(String path) {
    final String ext = path.contains('.') ? path.split('.').last.toLowerCase() : '';
    for (final MapEntry<String, List<String>> e in _mediaExtensions.entries) {
      if (e.value.contains(ext)) return e.key;
    }
    return 'file';
  }

  // -- panels -----------------------------------------------------------------

  static void _configure(Pointer<Void> panel, Map<Object?, Object?> m) {
    final DVMacosObjc o = _o;
    if (m['title'] is String) o.send1(panel, 'setTitle:', o.nsString('${m['title']}'));
    if (m['initialDirectory'] is String) {
      o.send1(panel, 'setDirectoryURL:', _fileUrl('${m['initialDirectory']}'));
    }
    final List<Object?> rawFilters = m['filters'] is List ? m['filters']! as List<Object?> : const <Object?>[];
    _filterLabels = <String>[for (final Object? f in rawFilters) if (f is Map) '${f['label'] ?? ''}'];
    final List<String> extensions = <String>[
      for (final Object? f in rawFilters)
        if (f is Map && f['extensions'] is List)
          for (final Object? e in f['extensions']! as List<Object?>) '$e',
    ];
    if (extensions.isNotEmpty) {
      final Pointer<Void> array = o.send0(o.cls('NSMutableArray'), 'array');
      for (final String e in extensions) {
        o.send1(array, 'addObject:', o.nsString(e));
      }
      // Deprecated in favour of allowedContentTypes, and still honoured;
      // UTType needs UniformTypeIdentifiers, another framework for one call.
      o.send1(panel, 'setAllowedFileTypes:', array);
    }
  }

  static Pointer<Void> _fileUrl(String path) => _o.send1(_o.cls('NSURL'), 'fileURLWithPath:', _o.nsString(path));

  static List<String> _openPanel(Map<Object?, Object?> m, {required bool directories, required bool multiple}) {
    final DVMacosObjc o = _o;
    final Pointer<Void> panel = o.send0(o.cls('NSOpenPanel'), 'openPanel');
    o.sendBool(panel, 'setCanChooseFiles:', !directories);
    o.sendBool(panel, 'setCanChooseDirectories:', directories);
    o.sendBool(panel, 'setAllowsMultipleSelection:', multiple);
    _configure(panel, m);
    final int response = _runModal(panel, directories ? _DialogKind.folder : _DialogKind.open);
    if (response != _modalResponseOk) return const <String>[];
    // Under automation the choice is the automation's, and it is taken before
    // the panel is asked. The panel is served by another process, its `URLs`
    // are read-only and `setDirectoryURL:` does not always reach it, so what
    // it answers is its own default -- the user's Documents folder -- which
    // is a real path to a real directory nobody chose.
    final String? selected = _selected;
    if (_automation != null && selected != null) return <String>[selected];
    final Pointer<Void> urls = o.send0(panel, 'URLs');
    final int count = urls == nullptr ? 0 : o.getInt(urls, 'count');
    if (count > 0) {
      return <String>[
        for (var i = 0; i < count; i++) _pathOf(o.getAt(urls, 'objectAtIndex:', i)),
      ];
    }
    // Open with nothing selected. Not a path: a person who presses Open
    // having selected nothing has selected nothing, and inventing one would
    // hand back a file they did not choose. An open panel has no name field
    // to compose one out of either -- asking one for nameFieldStringValue
    // answers with something that is not a string, and reading it as one is
    // how this suite killed its own process after every test had passed.
    return const <String>[];
  }

  static String? _savePanel(Map<Object?, Object?> m) {
    final DVMacosObjc o = _o;
    final Pointer<Void> panel = o.send0(o.cls('NSSavePanel'), 'savePanel');
    if (m['suggestedName'] is String) o.send1(panel, 'setNameFieldStringValue:', o.nsString('${m['suggestedName']}'));
    _configure(panel, m);
    final int response = _runModal(panel, _DialogKind.save);
    if (response != _modalResponseOk) return null;
    final Pointer<Void> url = o.send0(panel, 'URL');
    if (url != nullptr) return _pathOf(url);
    return _automation == null ? null : _configuredPath(panel);
  }

  static String _pathOf(Pointer<Void> url) {
    final DVMacosObjc o = _o;
    final Pointer<Void> path = o.send0(url, 'path');
    if (path == nullptr) return '';
    return _objc!.lookupFunction<_GetUtf8N, _GetUtf8D>('objc_msgSend')(path, o.sel('UTF8String')).toDartString();
  }

  /// Runs [panel] modally, with the automation's timer armed first when
  /// there is one.
  static int _runModal(Pointer<Void> panel, _DialogKind kind) {
    _current = panel;
    _currentKind = kind;
    _selected = null;
    _armTimer();
    try {
      return _o.getInt(panel, 'runModal');
    } finally {
      // A panel whose modal session was stopped from code is still on
      // screen, and still a visible window of this application. Ordered out
      // rather than closed: closing a panel served by another process is not
      // something to do from under its own modal loop, and ordering it out is
      // what AppKit's own documentation says to do once runModal returns.
      _o.send1(panel, 'orderOut:', nullptr);
      _disarmTimer();
      _current = null;
    }
  }

  // -- the alert --------------------------------------------------------------

  static void _alert(String text, {String? title, required String kind}) {
    final DVMacosObjc o = _o;
    final Pointer<Void> alert = o.send0(o.send0(o.cls('NSAlert'), 'alloc'), 'init');
    o.send1(alert, 'setMessageText:', o.nsString(title ?? 'Dartvel'));
    o.send1(alert, 'setInformativeText:', o.nsString(text));
    // NSAlertStyle: warning 0, informational 1, critical 2.
    o.sendInt(alert, 'setAlertStyle:', switch (kind) { 'error' => 2, 'warning' => 0, _ => 1 });
    o.send1(alert, 'addButtonWithTitle:', o.nsString('OK'));
    _current = alert;
    _currentKind = _DialogKind.message;
    _armTimer();
    try {
      o.getInt(alert, 'runModal');
    } finally {
      // The alert's window, not the alert: NSAlert is not a window and does
      // not answer `close`.
      final Pointer<Void> window = o.send0(alert, 'window');
      if (window != nullptr) o.send1(window, 'orderOut:', nullptr);
      _disarmTimer();
      _current = null;
    }
  }

  // -- automation -------------------------------------------------------------

  /// A one-shot timer in the modal panel mode, targeting the menu's object
  /// under an action that hands the current dialog to the automation.
  /// The timer armed for the dialog now running, so it can be taken off the
  /// run loop when that dialog is done with.
  static Pointer<Void>? _timer;

  /// Takes the armed timer off the run loop.
  ///
  /// Every panel armed one and none of them were ever invalidated, so they
  /// accumulated in the modal-panel run-loop mode and every one of them fired
  /// during the *next* dialog -- each calling an automation written for a
  /// dialog that had already been answered. A closure expecting an open panel
  /// inspecting a save panel, or answering a modal session that had already
  /// ended, is an Objective-C exception, and it takes the process with it
  /// after the tests have reported passing.
  static void _disarmTimer() {
    final Pointer<Void>? timer = _timer;
    if (timer == null) return;
    _timer = null;
    _o.send0(timer, 'invalidate');
    // And the retain above given back. Invalidating a timer the run loop
    // still holds is safe; keeping this reference after would leak one small
    // object per dialog, which is the sort of thing that is only ever found
    // by somebody else.
    _o.send0(timer, 'release');
  }

  static void _armTimer() {
    _disarmTimer();
    if (_automation == null) return;
    final DVMacosObjc o = _o;
    final Pointer<Void> target = DVMacosMenus.ensureTarget();
    if (_timerAction == null) {
      void onTimer(Pointer<Void> self, Pointer<Void> cmd, Pointer<Void> sender) {
        final Pointer<Void>? dialog = _current;
        final DVMacosDialogAutomation? run = _automation;
        if (dialog != null && run != null) run(DVMacosDialog._(dialog, _currentKind));
      }
      final NativeCallable<_ActionN> action = NativeCallable<_ActionN>.isolateLocal(onTimer);
      final Pointer<Utf8> types = 'v@:@'.toNativeUtf8();
      try {
        final Pointer<Void> cls = o.cls('DVMenuTarget');
        final bool added = _objc!.lookupFunction<_AddMethodN, _AddMethodD>('class_addMethod')(cls, o.sel('dartvelDialogTimer:'), action.nativeFunction, types);
        if (!added) {
          _objc!.lookupFunction<_ReplaceMethodN, _ReplaceMethodD>('class_replaceMethod')(cls, o.sel('dartvelDialogTimer:'), action.nativeFunction, types);
        }
      } finally {
        calloc.free(types);
      }
      _timerAction = action;
    }
    final Pointer<Void> timer = _objc!.lookupFunction<_TimerN, _TimerD>('objc_msgSend')(
      o.cls('NSTimer'), o.sel('timerWithTimeInterval:target:selector:userInfo:repeats:'), 0.1, target, o.sel('dartvelDialogTimer:'), nullptr, false);
    final Pointer<Void> loop = o.send0(o.cls('NSRunLoop'), 'currentRunLoop');
    // AppKit's, not Foundation's: the mode name is declared beside the
    // panels that run in it.
    final Pointer<Void> mode = _appKit.lookup<Pointer<Void>>('NSModalPanelRunLoopMode').value;
    _objc!.lookupFunction<_Send2N, _Send2D>('objc_msgSend')(loop, o.sel('addTimer:forMode:'), timer, mode);
    // Retained, because this outlives the run loop's own reference. A
    // one-shot timer is invalidated and released the moment it fires, and a
    // raw pointer kept past that is a pointer to freed memory -- so
    // invalidating it later, which is exactly what the next dialog does, is
    // a use-after-free in a process that has just finished reporting a test
    // as passed.
    _timer = _o.send0(timer, 'retain');
  }

  static DVMacosDialogSeen _inspect(Pointer<Void> panel, _DialogKind kind) {
    final DVMacosObjc o = _o;
    String? text(Pointer<Void> s) =>
        s == nullptr ? null : _objc!.lookupFunction<_GetUtf8N, _GetUtf8D>('objc_msgSend')(s, o.sel('UTF8String')).toDartString();
    if (kind == _DialogKind.message) {
      return DVMacosDialogSeen(title: text(o.send0(panel, 'messageText')), messageText: text(o.send0(panel, 'informativeText')));
    }
    final Pointer<Void> dir = o.send0(panel, 'directoryURL');
    return DVMacosDialogSeen(
      title: text(o.send0(panel, 'title')),
      filterLabels: _filterLabels,
      currentFolder: dir == nullptr ? null : _pathOf(dir),
      currentName: kind == _DialogKind.save ? text(o.send0(panel, 'nameFieldStringValue')) : null,
    );
  }

  /// The path the automation last selected, which is what a person's click
  /// would have selected.
  ///
  /// An open panel is served by another process and its `URLs` are read-only,
  /// so there is no way to put a selection into it from here; what the
  /// automation asked for is the only record of what was chosen.
  static String? _selected;

  static void _select(Pointer<Void> panel, _DialogKind kind, String path) {
    if (kind == _DialogKind.message) return;
    final DVMacosObjc o = _o;
    // A file: its directory shown and its name typed. A directory: shown.
    final Pointer<Void> url = _fileUrl(path);
    final bool isDirectory = kind == _DialogKind.folder || path.endsWith('/');
    // Without the trailing slash: a chosen directory is a path, and every
    // caller that joins a filename onto it would otherwise get a double
    // separator.
    _selected = path.length > 1 && path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    if (isDirectory) {
      o.send1(panel, 'setDirectoryURL:', url);
    } else {
      o.send1(panel, 'setDirectoryURL:', o.send0(url, 'URLByDeletingLastPathComponent'));
      o.send1(panel, 'setNameFieldStringValue:', o.send0(url, 'lastPathComponent'));
    }
  }

  static void _answer(Pointer<Void> panel, _DialogKind kind, {required bool ok}) {
    final DVMacosObjc o = _o;
    if (kind == _DialogKind.message) {
      final Pointer<Void> buttons = o.send0(panel, 'buttons');
      if (o.getInt(buttons, 'count') > 0) o.send1(o.getAt(buttons, 'objectAtIndex:', 0), 'performClick:', nullptr);
      return;
    }
    // No panel answers `ok:` on a modern macOS: AppKit raises
    // "-[NSSavePanel ok:] : not implemented" -- the panel is served by a
    // separate process and the legacy programmatic control is gone -- and
    // the exception terminates the process after the tests have already
    // reported passing, so the failure arrives as an exit code with no test
    // attached to it. The modal session is ended directly instead, which is
    // what the button does underneath and what runModal returns.
    _stopModal(ok ? _modalResponseOk : _modalResponseCancel);
  }

  /// The path a *save* panel is configured to hand back: its directory and
  /// the name typed into it, which is exactly what pressing Save produces.
  ///
  /// Only a save panel. The name field belongs to NSSavePanel, and an open
  /// panel asked for one answers with something that is not a string.
  static String _configuredPath(Pointer<Void> panel) {
    final DVMacosObjc o = _o;
    final Pointer<Void> directory = o.send0(panel, 'directoryURL');
    final String base = directory == nullptr ? '' : _pathOf(directory);
    final Pointer<Void> name = o.send0(panel, 'nameFieldStringValue');
    final Pointer<Utf8> utf8 = name == nullptr
        ? nullptr
        : _objc!.lookupFunction<_GetUtf8N, _GetUtf8D>('objc_msgSend')(name, o.sel('UTF8String'));
    final String file = utf8 == nullptr ? '' : utf8.toDartString();
    if (file.isEmpty) return base;
    return base.endsWith('/') ? '$base$file' : '$base/$file';
  }

  /// Ends the application's modal session with [code], which is what
  /// `runModal` then returns.
  static void _stopModal(int code) {
    final DVMacosObjc o = _o;
    final Pointer<Void> app = o.send0(o.cls('NSApplication'), 'sharedApplication');
    if (app == nullptr) return;
    o.sendInt(app, 'stopModalWithCode:', code);
  }

  static void unregister() {
    _disarmTimer();
    _automation = null;
  }
}
