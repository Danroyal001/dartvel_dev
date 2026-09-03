/// System dialogs on Windows: the common dialogs, the folder browser and
/// the message box.
///
/// GetOpenFileNameW and GetSaveFileNameW with a hook, which is what makes
/// the dialog answerable: the hook hears CDN_INITDONE from inside the
/// dialog's own loop, on the thread that opened it, and an automation set
/// by a test answers there the way a person would -- a path typed, OK
/// pressed. SHBrowseForFolderW has the same in its callback, and the
/// message box the same through a CBT hook on this thread. Without
/// automation the dialogs wait for the person, as they should.
library;

import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

// OPENFILENAMEW, as Win32 x64 lays it out.
final class _OpenFileName extends Struct {
  @Uint32()
  external int lStructSize;
  @IntPtr()
  external int hwndOwner;
  @IntPtr()
  external int hInstance;
  external Pointer<Utf16> lpstrFilter;
  external Pointer<Utf16> lpstrCustomFilter;
  @Uint32()
  external int nMaxCustFilter;
  @Uint32()
  external int nFilterIndex;
  external Pointer<Utf16> lpstrFile;
  @Uint32()
  external int nMaxFile;
  external Pointer<Utf16> lpstrFileTitle;
  @Uint32()
  external int nMaxFileTitle;
  external Pointer<Utf16> lpstrInitialDir;
  external Pointer<Utf16> lpstrTitle;
  @Uint32()
  external int flags;
  @Uint16()
  external int nFileOffset;
  @Uint16()
  external int nFileExtension;
  external Pointer<Utf16> lpstrDefExt;
  @IntPtr()
  external int lCustData;
  external Pointer<NativeFunction<_HookProcNative>> lpfnHook;
  external Pointer<Utf16> lpTemplateName;
  external Pointer<Void> pvReserved;
  @Uint32()
  external int dwReserved;
  @Uint32()
  external int flagsEx;
}

final class _BrowseInfo extends Struct {
  @IntPtr()
  external int hwndOwner;
  external Pointer<Void> pidlRoot;
  external Pointer<Utf16> pszDisplayName;
  external Pointer<Utf16> lpszTitle;
  @Uint32()
  external int ulFlags;
  external Pointer<NativeFunction<_BrowseCallbackNative>> lpfn;
  @IntPtr()
  external int lParam;
  @Int32()
  external int iImage;
}

final class _NmHdr extends Struct {
  @IntPtr()
  external int hwndFrom;
  @UintPtr()
  external int idFrom;
  @Uint32()
  external int code;
}

typedef _HookProcNative = UintPtr Function(IntPtr hdlg, Uint32 message, UintPtr wParam, IntPtr lParam);
typedef _BrowseCallbackNative = Int32 Function(IntPtr hwnd, Uint32 message, IntPtr lParam, IntPtr data);
typedef _CbtProcNative = IntPtr Function(Int32 code, UintPtr wParam, IntPtr lParam);
typedef _TimerProcNative = Void Function(IntPtr hWnd, Uint32 message, UintPtr id, Uint32 time);

const int _ofnExplorer = 0x00080000;
const int _ofnEnableHook = 0x00000020;
const int _ofnAllowMultiSelect = 0x00000200;
const int _ofnFileMustExist = 0x00001000;
const int _ofnNoChangeDir = 0x00000008;
const int _wmCommand = 0x0111;
const int _wmNotify = 0x004E;
const int _wmUser = 0x0400;
const int _cdnInitDone = 0xFFFFFDA7; // (UINT)(CDN_FIRST - 0), CDN_FIRST = -601
const int _cdmGetSpec = _wmUser + 101;
const int _cdmGetFolderPath = _wmUser + 102;
const int _cdmSetControlText = _wmUser + 104;
const int _edt1 = 0x0480;
const int _cmb13 = 0x047C;
const int _idOk = 1;
const int _idCancel = 2;
const int _bffmInitialized = 1;
const int _bffmSetSelectionW = _wmUser + 103;
const int _bifReturnOnlyFsDirs = 0x0001;
const int _bifNewDialogStyle = 0x0040;
const int _whCbt = 5;
const int _hcbtActivate = 5;
const int _mbOk = 0x0;
const int _mbIconError = 0x10;
const int _mbIconQuestion = 0x20;
const int _mbIconWarning = 0x30;
const int _mbIconInformation = 0x40;
const int _maxPath = 32768;

/// What the dialog showed, for a test.
class DVWindowsDialogSeen {
  const DVWindowsDialogSeen({this.title, this.filterLabels = const <String>[], this.currentFolder, this.currentName, this.messageText});
  final String? title;
  final List<String> filterLabels;
  final String? currentFolder;
  final String? currentName;
  final String? messageText;
}

/// A dialog on screen, answerable from its own hook.
class DVWindowsDialog {
  DVWindowsDialog._(this._hwnd, this._kind);

  final int _hwnd;
  final _DialogKind _kind;

  DVWindowsDialogSeen inspect() => DVWindowsDialogs._inspect(_hwnd, _kind);
  void selectPath(String path) => DVWindowsDialogs._select(_hwnd, _kind, path);
  void accept() => DVWindowsDialogs._post(_hwnd, _idOk);
  void cancel() => DVWindowsDialogs._post(_hwnd, _idCancel);
}

typedef DVWindowsDialogAutomation = void Function(DVWindowsDialog dialog);

enum _DialogKind { file, folder, message }

class DVWindowsDialogs {
  const DVWindowsDialogs._();

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

  static late DynamicLibrary _user32;
  static DynamicLibrary? _comdlg32;
  static DynamicLibrary? _shell32;
  static DynamicLibrary? _ole32;
  static DVWindowsDialogAutomation? _automation;
  static List<String> _filterLabels = const <String>[];
  static bool _answered = false;

  /// The dialog on screen, once its hook has seen it.
  static int _dialogWindow = 0;

  /// Why the last dialog ended without an answer, for the operator and the
  /// test.
  static String? lastError;

  /// Under automation, how long a dialog may stay unanswered before it is
  /// cancelled: an automation that never answers must fail the test, not
  /// hang the process.
  static Duration automationTimeout = const Duration(seconds: 8);

  static NativeCallable<_TimerProcNative>? _watchdogProc;
  static int _watchdog = 0;

  /// Arms the watchdog for the dialog about to run. A thread timer: the
  /// dialog's own loop dispatches WM_TIMER, so the procedure runs inside it.
  static void _armWatchdog() {
    _dialogWindow = 0;
    lastError = null;
    if (_automation == null) return;
    final NativeCallable<_TimerProcNative> proc = NativeCallable<_TimerProcNative>.isolateLocal(_onWatchdog);
    _watchdogProc = proc;
    _watchdog = _user32.lookupFunction<
        UintPtr Function(IntPtr, UintPtr, Uint32, Pointer<NativeFunction<_TimerProcNative>>),
        int Function(int, int, int, Pointer<NativeFunction<_TimerProcNative>>)>('SetTimer')(
      0, 0, automationTimeout.inMilliseconds, proc.nativeFunction);
  }

  static void _disarmWatchdog() {
    if (_watchdog != 0) {
      _user32.lookupFunction<Int32 Function(IntPtr, UintPtr), int Function(int, int)>('KillTimer')(0, _watchdog);
      _watchdog = 0;
    }
    _watchdogProc?.close();
    _watchdogProc = null;
  }

  static void _onWatchdog(int hWnd, int message, int id, int time) {
    if (_answered && _dialogWindow != 0) return;
    final int target = _dialogWindow != 0 ? _dialogWindow : _user32.lookupFunction<IntPtr Function(), int Function()>('GetActiveWindow')();
    lastError = _dialogWindow == 0
        ? 'the dialog was never seen by its hook within ${automationTimeout.inSeconds}s'
        : 'the automation did not answer the dialog within ${automationTimeout.inSeconds}s';
    if (target != 0) _post(target, _idCancel);
  }

  /// For tests: called from the dialog's own hook once it is up, with the
  /// dialog, to answer it. Null restores the person.
  static void automate(DVWindowsDialogAutomation? automation) => _automation = automation;

  static void register(void Function(String, FutureOr<Object?> Function(Object?)) bind, {required DynamicLibrary user32}) {
    _user32 = user32;
    bind('dialogs.openFile', (Object? a) {
      final Map<Object?, Object?> m = a is Map ? a : const <Object?, Object?>{};
      return <String, Object?>{'paths': _file(m, save: false, multiple: m['multiple'] == true)};
    });
    bind('dialogs.saveFile', (Object? a) {
      final Map<Object?, Object?> m = a is Map ? a : const <Object?, Object?>{};
      final List<String> paths = _file(m, save: true, multiple: false);
      return <String, Object?>{'path': paths.isEmpty ? null : paths.first};
    });
    bind('dialogs.chooseDirectory', (Object? a) {
      final Map<Object?, Object?> m = a is Map ? a : const <Object?, Object?>{};
      return <String, Object?>{'path': _folder(m['title'] as String?)};
    });
    bind('dialogs.message', (Object? a) {
      final Map<Object?, Object?> m = a is Map ? a : const <Object?, Object?>{};
      _message('${m['text'] ?? ''}', title: m['title'] as String?, kind: '${m['kind'] ?? 'info'}');
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
      final List<String> paths = _file(
        <Object?, Object?>{'title': 'Pick ${type == 'any' ? 'a file' : type == 'image' ? 'an image' : 'a $type'}', 'filters': filters},
        save: false,
        multiple: m['multiple'] == true,
      );
      return <Map<String, Object?>>[
        for (final String p in paths) <String, Object?>{'path': p, 'name': p.split(RegExp(r'[\\/]')).last, 'type': _typeOf(p)},
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

  // -- the common file dialogs ----------------------------------------------

  static List<String> _file(Map<Object?, Object?> m, {required bool save, required bool multiple}) {
    final DynamicLibrary comdlg32 = _comdlg32 ??= DynamicLibrary.open('comdlg32.dll');
    final get = comdlg32.lookupFunction<Int32 Function(Pointer<_OpenFileName>), int Function(Pointer<_OpenFileName>)>(
        save ? 'GetSaveFileNameW' : 'GetOpenFileNameW');

    final List<Object?> rawFilters = m['filters'] is List ? m['filters']! as List<Object?> : const <Object?>[];
    _filterLabels = <String>[for (final Object? f in rawFilters) if (f is Map) '${f['label'] ?? ''}'];
    final StringBuffer filter = StringBuffer();
    for (final Object? f in rawFilters) {
      if (f is! Map) continue;
      final List<Object?> exts = f['extensions'] is List ? f['extensions']! as List<Object?> : const <Object?>[];
      filter
        ..write('${f['label'] ?? ''}')
        ..writeCharCode(0)
        ..write(exts.isEmpty ? '*.*' : exts.map((Object? e) => '*.$e').join(';'))
        ..writeCharCode(0);
    }
    final Pointer<Utf16> filterText = filter.isEmpty ? nullptr : '$filter'.toNativeUtf16();
    final Pointer<Utf16> title = m['title'] is String ? '${m['title']}'.toNativeUtf16() : nullptr;
    final Pointer<Utf16> initialDir = m['initialDirectory'] is String ? '${m['initialDirectory']}'.toNativeUtf16() : nullptr;
    final Pointer<Uint16> file = calloc<Uint16>(_maxPath);
    final String suggested = '${m['suggestedName'] ?? ''}';
    for (var i = 0; i < suggested.length && i < _maxPath - 1; i++) {
      file[i] = suggested.codeUnitAt(i);
    }
    final Pointer<_OpenFileName> ofn = calloc<_OpenFileName>();
    final NativeCallable<_HookProcNative> hook = NativeCallable<_HookProcNative>.isolateLocal(_fileHook, exceptionalReturn: 0);
    _answered = false;
    _armWatchdog();
    try {
      ofn.ref
        ..lStructSize = sizeOf<_OpenFileName>()
        ..lpstrFilter = filterText
        ..nFilterIndex = 1
        ..lpstrFile = file.cast()
        ..nMaxFile = _maxPath
        ..lpstrInitialDir = initialDir
        ..lpstrTitle = title
        ..flags = _ofnExplorer | _ofnEnableHook | _ofnNoChangeDir | (save ? 0 : _ofnFileMustExist) | (multiple ? _ofnAllowMultiSelect : 0)
        ..lpfnHook = hook.nativeFunction;
      if (get(ofn) == 0) return const <String>[];
      return _pathsFrom(file, multiple: multiple, fileOffset: ofn.ref.nFileOffset);
    } finally {
      _disarmWatchdog();
      hook.close();
      calloc.free(ofn);
      calloc.free(file);
      if (filterText != nullptr) calloc.free(filterText);
      if (title != nullptr) calloc.free(title);
      if (initialDir != nullptr) calloc.free(initialDir);
    }
  }

  /// lpstrFile after OK: one path, or with several allowed the directory
  /// then each name, each ended by a NUL, the list by two.
  static List<String> _pathsFrom(Pointer<Uint16> buffer, {required bool multiple, required int fileOffset}) {
    final List<String> parts = <String>[];
    var start = 0;
    for (var i = 0; i < _maxPath; i++) {
      if (buffer[i] == 0) {
        if (i == start) break;
        parts.add(String.fromCharCodes(<int>[for (var j = start; j < i; j++) buffer[j]]));
        start = i + 1;
      }
    }
    if (parts.isEmpty) return const <String>[];
    if (!multiple || parts.length == 1) return <String>[parts.first];
    final String dir = parts.first.endsWith('\\') ? parts.first : '${parts.first}\\';
    return <String>[for (final String name in parts.skip(1)) '$dir$name'];
  }

  static int _fileHook(int hdlg, int message, int wParam, int lParam) {
    if (message == _wmNotify && !_answered) {
      final _NmHdr header = Pointer<_NmHdr>.fromAddress(lParam).ref;
      if (header.code == _cdnInitDone) {
        _answered = true;
        final int parent = _user32.lookupFunction<IntPtr Function(IntPtr), int Function(int)>('GetParent')(hdlg);
        _dialogWindow = parent;
        final DVWindowsDialogAutomation? run = _automation;
        if (run != null) run(DVWindowsDialog._(parent, _DialogKind.file));
      }
    }
    return 0;
  }

  // -- the folder browser ---------------------------------------------------

  static String? _folder(String? title) {
    final DynamicLibrary shell32 = _shell32 ??= DynamicLibrary.open('shell32.dll');
    final DynamicLibrary ole32 = _ole32 ??= DynamicLibrary.open('ole32.dll');
    // The new-style browser wants COM up on this thread; a second call says
    // so harmlessly.
    ole32.lookupFunction<Int32 Function(Pointer<Void>, Uint32), int Function(Pointer<Void>, int)>('CoInitializeEx')(nullptr, 2);

    final Pointer<Utf16> titleText = (title ?? 'Choose a folder').toNativeUtf16();
    final Pointer<Uint16> display = calloc<Uint16>(_maxPath);
    final Pointer<_BrowseInfo> info = calloc<_BrowseInfo>();
    final NativeCallable<_BrowseCallbackNative> callback = NativeCallable<_BrowseCallbackNative>.isolateLocal(_browseCallback, exceptionalReturn: 0);
    _answered = false;
    _armWatchdog();
    try {
      info.ref
        ..pszDisplayName = display.cast()
        ..lpszTitle = titleText
        ..ulFlags = _bifReturnOnlyFsDirs | _bifNewDialogStyle
        ..lpfn = callback.nativeFunction;
      final Pointer<Void> pidl = shell32.lookupFunction<Pointer<Void> Function(Pointer<_BrowseInfo>), Pointer<Void> Function(Pointer<_BrowseInfo>)>('SHBrowseForFolderW')(info);
      if (pidl == nullptr) return null;
      final Pointer<Uint16> path = calloc<Uint16>(_maxPath);
      try {
        final int ok = shell32.lookupFunction<Int32 Function(Pointer<Void>, Pointer<Utf16>), int Function(Pointer<Void>, Pointer<Utf16>)>('SHGetPathFromIDListW')(pidl, path.cast());
        return ok == 0 ? null : path.cast<Utf16>().toDartString();
      } finally {
        ole32.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('CoTaskMemFree')(pidl);
        calloc.free(path);
      }
    } finally {
      _disarmWatchdog();
      callback.close();
      calloc.free(info);
      calloc.free(display);
      calloc.free(titleText);
    }
  }

  static int _browseCallback(int hwnd, int message, int lParam, int data) {
    if (message == _bffmInitialized && !_answered) {
      _answered = true;
      _dialogWindow = hwnd;
      final DVWindowsDialogAutomation? run = _automation;
      if (run != null) run(DVWindowsDialog._(hwnd, _DialogKind.folder));
    }
    return 0;
  }

  // -- the message box ------------------------------------------------------

  static int _cbtHook = 0;
  static NativeCallable<_CbtProcNative>? _cbtProc;

  static void _message(String text, {String? title, required String kind}) {
    final int icon = switch (kind) {
      'error' => _mbIconError,
      'warning' => _mbIconWarning,
      'question' => _mbIconQuestion,
      _ => _mbIconInformation,
    };
    final Pointer<Utf16> textPtr = text.toNativeUtf16();
    final Pointer<Utf16> titlePtr = (title ?? 'Dartvel').toNativeUtf16();
    final DVWindowsDialogAutomation? run = _automation;
    if (run != null) {
      // Answered from a CBT hook on this thread: the box is activated before
      // its loop waits, and the hook sees that.
      final NativeCallable<_CbtProcNative> proc = NativeCallable<_CbtProcNative>.isolateLocal(_onCbt, exceptionalReturn: 0);
      _cbtProc = proc;
      _answered = false;
      _armWatchdog();
      final int thread = DynamicLibrary.open('kernel32.dll').lookupFunction<Uint32 Function(), int Function()>('GetCurrentThreadId')();
      _cbtHook = _user32.lookupFunction<
          IntPtr Function(Int32, Pointer<NativeFunction<_CbtProcNative>>, IntPtr, Uint32),
          int Function(int, Pointer<NativeFunction<_CbtProcNative>>, int, int)>('SetWindowsHookExW')(_whCbt, proc.nativeFunction, 0, thread);
    }
    try {
      _user32.lookupFunction<
          Int32 Function(IntPtr, Pointer<Utf16>, Pointer<Utf16>, Uint32),
          int Function(int, Pointer<Utf16>, Pointer<Utf16>, int)>('MessageBoxW')(0, textPtr, titlePtr, _mbOk | icon);
    } finally {
      _disarmWatchdog();
      if (_cbtHook != 0) {
        _user32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('UnhookWindowsHookEx')(_cbtHook);
        _cbtHook = 0;
      }
      _cbtProc?.close();
      _cbtProc = null;
      calloc.free(textPtr);
      calloc.free(titlePtr);
    }
  }

  static int _onCbt(int code, int wParam, int lParam) {
    if (code == _hcbtActivate && !_answered) {
      _answered = true;
      _dialogWindow = wParam;
      final DVWindowsDialogAutomation? run = _automation;
      if (run != null) run(DVWindowsDialog._(wParam, _DialogKind.message));
    }
    return _user32.lookupFunction<
        IntPtr Function(IntPtr, Int32, UintPtr, IntPtr),
        int Function(int, int, int, int)>('CallNextHookEx')(0, code, wParam, lParam);
  }

  // -- what the handle does ---------------------------------------------------

  static String _windowText(int hwnd) {
    final Pointer<Uint16> buffer = calloc<Uint16>(1024);
    try {
      _user32.lookupFunction<Int32 Function(IntPtr, Pointer<Utf16>, Int32), int Function(int, Pointer<Utf16>, int)>('GetWindowTextW')(hwnd, buffer.cast(), 1024);
      return buffer.cast<Utf16>().toDartString();
    } finally {
      calloc.free(buffer);
    }
  }

  static int _send(int hwnd, int message, int wParam, int lParam) => _user32.lookupFunction<
      IntPtr Function(IntPtr, Uint32, IntPtr, IntPtr),
      int Function(int, int, int, int)>('SendMessageW')(hwnd, message, wParam, lParam);

  static String _commDlgText(int hwnd, int message) {
    final Pointer<Uint16> buffer = calloc<Uint16>(_maxPath);
    try {
      _send(hwnd, message, _maxPath, buffer.address);
      return buffer.cast<Utf16>().toDartString();
    } finally {
      calloc.free(buffer);
    }
  }

  static DVWindowsDialogSeen _inspect(int hwnd, _DialogKind kind) => switch (kind) {
        _DialogKind.file => DVWindowsDialogSeen(
            title: _windowText(hwnd),
            filterLabels: _filterLabels,
            currentFolder: _commDlgText(hwnd, _cdmGetFolderPath),
            currentName: _commDlgText(hwnd, _cdmGetSpec),
          ),
        _DialogKind.folder => DVWindowsDialogSeen(title: _windowText(hwnd)),
        _DialogKind.message => DVWindowsDialogSeen(title: _windowText(hwnd), messageText: _messageText(hwnd)),
      };

  /// The message box's text lives in its static control, id 0xFFFF.
  static String _messageText(int hwnd) {
    final Pointer<Uint16> buffer = calloc<Uint16>(4096);
    try {
      _user32.lookupFunction<
          Uint32 Function(IntPtr, Int32, Pointer<Utf16>, Int32),
          int Function(int, int, Pointer<Utf16>, int)>('GetDlgItemTextW')(hwnd, 0xFFFF, buffer.cast(), 4096);
      return buffer.cast<Utf16>().toDartString();
    } finally {
      calloc.free(buffer);
    }
  }

  static void _select(int hwnd, _DialogKind kind, String path) {
    final Pointer<Utf16> text = path.toNativeUtf16();
    try {
      switch (kind) {
        case _DialogKind.file:
          // The file name lives in a combo on the explorer-style dialog and
          // in an edit on the older one; the dialog takes the text for
          // whichever it has.
          _send(hwnd, _cdmSetControlText, _cmb13, text.address);
          _send(hwnd, _cdmSetControlText, _edt1, text.address);
        case _DialogKind.folder:
          _send(hwnd, _bffmSetSelectionW, 1, text.address);
        case _DialogKind.message:
          break;
      }
    } finally {
      calloc.free(text);
    }
  }

  /// Posted rather than sent: the dialog's own loop handles it after the
  /// hook returns, as a click would arrive.
  static void _post(int hwnd, int command) => _user32.lookupFunction<
      Int32 Function(IntPtr, Uint32, IntPtr, IntPtr),
      int Function(int, int, int, int)>('PostMessageW')(hwnd, _wmCommand, command, 0);

  static void unregister() {
    _automation = null;
  }
}
