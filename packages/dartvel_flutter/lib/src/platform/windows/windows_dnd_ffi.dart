/// Drag and drop on Windows: an OLE drop target on the process's window.
///
/// Windows delivers a drop through COM: the window registers an IDropTarget,
/// and the shell calls DragEnter, DragOver and Drop on it, handing over an
/// IDataObject that holds what is being dragged. So this builds a COM object
/// -- a vtable of seven functions in front of a pointer -- registers it with
/// RegisterDragDrop, and reads CF_HDROP for files and CF_UNICODETEXT for
/// text, which is exactly what Explorer and a browser put there.
///
/// The POINTL each method takes is passed by value, and on x64 an eight-byte
/// structure travels in a register; it is declared as the integer it is and
/// unpacked, rather than as a struct by value in a callback.
library;

import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../drag_drop.dart';

// The COM methods, in vtable order.
typedef _QueryInterfaceN = Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Pointer<Void>>);
typedef _AddRefN = Uint32 Function(Pointer<Void>);
typedef _ReleaseN = Uint32 Function(Pointer<Void>);
typedef _DragEnterN = Int32 Function(Pointer<Void>, Pointer<Void>, Uint32, Int64, Pointer<Uint32>);
typedef _DragOverN = Int32 Function(Pointer<Void>, Uint32, Int64, Pointer<Uint32>);
typedef _DragLeaveN = Int32 Function(Pointer<Void>);
typedef _DropN = Int32 Function(Pointer<Void>, Pointer<Void>, Uint32, Int64, Pointer<Uint32>);

typedef _DropD = int Function(Pointer<Void>, Pointer<Void>, int, int, Pointer<Uint32>);

typedef _OleInitN = Int32 Function(Pointer<Void>);
typedef _OleInitD = int Function(Pointer<Void>);
typedef _RegisterDragDropN = Int32 Function(IntPtr, Pointer<Void>);
typedef _RegisterDragDropD = int Function(int, Pointer<Void>);
typedef _RevokeDragDropN = Int32 Function(IntPtr);
typedef _RevokeDragDropD = int Function(int);
typedef _ReleaseStgMediumN = Void Function(Pointer<_StgMedium>);
typedef _ReleaseStgMediumD = void Function(Pointer<_StgMedium>);
typedef _DragQueryFileN = Uint32 Function(IntPtr, Uint32, Pointer<Utf16>, Uint32);
typedef _DragQueryFileD = int Function(int, int, Pointer<Utf16>, int);
typedef _GlobalLockN = Pointer<Void> Function(IntPtr);
typedef _GlobalLockD = Pointer<Void> Function(int);
typedef _GlobalUnlockN = Int32 Function(IntPtr);
typedef _GlobalUnlockD = int Function(int);
typedef _GetActiveWindowN = IntPtr Function();
typedef _GetActiveWindowD = int Function();

/// The IDataObject method this needs, at its vtable index.
typedef _GetDataN = Int32 Function(Pointer<Void>, Pointer<_FormatEtc>, Pointer<_StgMedium>);
typedef _GetDataD = int Function(Pointer<Void>, Pointer<_FormatEtc>, Pointer<_StgMedium>);

/// FORMATETC, with the padding Win32 lays it out with: the pointer after
/// the two-byte format is eight-aligned, and the trailing four bytes round
/// the structure to a multiple of eight.
final class _FormatEtc extends Struct {
  @Uint16()
  external int cfFormat;
  @Uint16()
  external int padA;
  @Uint32()
  external int padB;
  external Pointer<Void> ptd;
  @Uint32()
  external int dwAspect;
  @Int32()
  external int lindex;
  @Uint32()
  external int tymed;
  @Uint32()
  external int padC;
}

/// STGMEDIUM: the union is a pointer, eight-aligned after the tag.
final class _StgMedium extends Struct {
  @Uint32()
  external int tymed;
  @Uint32()
  external int pad;
  external Pointer<Void> handle;
  external Pointer<Void> pUnkForRelease;
}

const int _sOk = 0;
const int _eNoInterface = 0x80004002;
const int _cfUnicodeText = 13;
const int _cfHdrop = 15;
const int _dvAspectContent = 1;
const int _tymedHGlobal = 1;
const int _dropEffectNone = 0;
const int _dropEffectCopy = 1;

/// `IDataObject::GetData` is the fourth entry: QueryInterface, AddRef,
/// Release, then GetData.
const int _getDataIndex = 3;

class DVWindowsDragDrop {
  const DVWindowsDragDrop._();

  static const Set<String> implemented = <String>{'dragDrop.accept', 'dragDrop.stop'};

  static late DynamicLibrary _ole32;
  static late DynamicLibrary _shell32;
  static late DynamicLibrary _user32;
  static late DynamicLibrary _kernel32;

  /// The COM object handed to OLE: a pointer to a vtable, and the vtable.
  static Pointer<Pointer<Void>>? _target;
  static Pointer<Pointer<Void>>? _vtable;
  static int _window = 0;
  static bool _wantsFiles = true;
  static bool _wantsText = true;

  /// What closes the callables the vtable points at, so stopping takes back
  /// exactly what accepting made.
  static final List<void Function()> _closers = <void Function()>[];

  /// Why the last accept did not register a drop target.
  static String? lastError;

  /// Whether a drop target is registered.
  static bool get accepting => _window != 0;

  /// The COM object, for a test that calls it the way OLE does.
  static Pointer<Pointer<Void>>? get debugTarget => _target;

  static void register(
    void Function(String, FutureOr<Object?> Function(Object?)) bind, {
    required DynamicLibrary user32,
    required DynamicLibrary kernel32,
  }) {
    _user32 = user32;
    _kernel32 = kernel32;
    _ole32 = DynamicLibrary.open('ole32.dll');
    _shell32 = DynamicLibrary.open('shell32.dll');
    bind('dragDrop.accept', (Object? arguments) {
      final Map<Object?, Object?> map = arguments is Map ? arguments : const <Object?, Object?>{};
      final List<Object?> types = (map['types'] as List?) ?? const <Object?>['files', 'text'];
      _wantsFiles = types.contains('files');
      _wantsText = types.contains('text');
      return _accept();
    });
    bind('dragDrop.stop', (Object? _) {
      _stop();
      return true;
    });
  }

  static bool _accept() {
    final int hWnd = _user32.lookupFunction<_GetActiveWindowN, _GetActiveWindowD>('GetActiveWindow')();
    if (hWnd == 0) {
      lastError = 'no window to take drops';
      return false;
    }
    _stop();
    // Already initialised in a Flutter application; S_FALSE says so and is
    // not a failure.
    _ole32.lookupFunction<_OleInitN, _OleInitD>('OleInitialize')(nullptr);
    _build();
    final int hr = _ole32
        .lookupFunction<_RegisterDragDropN, _RegisterDragDropD>('RegisterDragDrop')(hWnd, _target!.cast());
    if (hr != _sOk) {
      lastError = 'RegisterDragDrop refused (HRESULT 0x${hr.toRadixString(16)})';
      return false;
    }
    _window = hWnd;
    lastError = null;
    return true;
  }

  static void _stop() {
    if (_window != 0) {
      _ole32.lookupFunction<_RevokeDragDropN, _RevokeDragDropD>('RevokeDragDrop')(_window);
      _window = 0;
    }
    _free();
  }

  /// The COM object: seven function pointers, and a pointer to them.
  static void _build() {
    if (_target != null) return;
    final NativeCallable<_QueryInterfaceN> queryInterface =
        NativeCallable<_QueryInterfaceN>.isolateLocal(_queryInterface, exceptionalReturn: _eNoInterface);
    final NativeCallable<_AddRefN> addRef =
        NativeCallable<_AddRefN>.isolateLocal(_addRef, exceptionalReturn: 1);
    final NativeCallable<_ReleaseN> release =
        NativeCallable<_ReleaseN>.isolateLocal(_release, exceptionalReturn: 1);
    final NativeCallable<_DragEnterN> dragEnter =
        NativeCallable<_DragEnterN>.isolateLocal(_dragEnter, exceptionalReturn: _sOk);
    final NativeCallable<_DragOverN> dragOver =
        NativeCallable<_DragOverN>.isolateLocal(_dragOver, exceptionalReturn: _sOk);
    final NativeCallable<_DragLeaveN> dragLeave =
        NativeCallable<_DragLeaveN>.isolateLocal(_dragLeave, exceptionalReturn: _sOk);
    final NativeCallable<_DropN> drop =
        NativeCallable<_DropN>.isolateLocal(_drop, exceptionalReturn: _sOk);
    _closers
      ..add(queryInterface.close)
      ..add(addRef.close)
      ..add(release.close)
      ..add(dragEnter.close)
      ..add(dragOver.close)
      ..add(dragLeave.close)
      ..add(drop.close);

    final Pointer<Pointer<Void>> vtable = calloc<Pointer<Void>>(7);
    vtable[0] = queryInterface.nativeFunction.cast();
    vtable[1] = addRef.nativeFunction.cast();
    vtable[2] = release.nativeFunction.cast();
    vtable[3] = dragEnter.nativeFunction.cast();
    vtable[4] = dragOver.nativeFunction.cast();
    vtable[5] = dragLeave.nativeFunction.cast();
    vtable[6] = drop.nativeFunction.cast();

    final Pointer<Pointer<Void>> object = calloc<Pointer<Void>>();
    object.value = vtable.cast();
    _vtable = vtable;
    _target = object;
  }

  static void _free() {
    for (final void Function() close in _closers) {
      close();
    }
    _closers.clear();
    if (_vtable != null) calloc.free(_vtable!);
    if (_target != null) calloc.free(_target!);
    _vtable = null;
    _target = null;
  }

  // -- the COM methods --------------------------------------------------

  /// Answers for IUnknown and IDropTarget, whose GUIDs differ only in the
  /// first field; anything else is refused rather than handed this object.
  static int _queryInterface(Pointer<Void> self, Pointer<Uint8> riid, Pointer<Pointer<Void>> out) {
    final int data1 = riid.cast<Uint32>().value;
    // IID_IUnknown {00000000-...}, IID_IDropTarget {00000122-...}.
    if (data1 == 0x00000000 || data1 == 0x00000122) {
      out.value = self;
      return _sOk;
    }
    out.value = nullptr;
    return _eNoInterface;
  }

  /// The object lives as long as the binding holds it, so the counts are
  /// nominal: OLE is told it is alive, and Release never frees it.
  static int _addRef(Pointer<Void> self) => 1;
  static int _release(Pointer<Void> self) => 1;

  static int _dragEnter(Pointer<Void> self, Pointer<Void> data, int keys, int point, Pointer<Uint32> effect) {
    effect.value = _hasSomethingToTake(data) ? _dropEffectCopy : _dropEffectNone;
    return _sOk;
  }

  static int _dragOver(Pointer<Void> self, int keys, int point, Pointer<Uint32> effect) {
    // Whatever DragEnter decided still holds: the pointer moving over the
    // window does not change what is being dragged.
    return _sOk;
  }

  static int _dragLeave(Pointer<Void> self) => _sOk;

  static int _drop(Pointer<Void> self, Pointer<Void> data, int keys, int point, Pointer<Uint32> effect) {
    final DVDropEvent event = eventFrom(data, x: pointX(point).toDouble(), y: pointY(point).toDouble());
    effect.value = event.isEmpty ? _dropEffectNone : _dropEffectCopy;
    DVDragDrop.dispatch(event);
    return _sOk;
  }

  /// A POINTL travels as eight bytes: x in the low half, y in the high.
  static int pointX(int point) => point & 0xFFFFFFFF | 0;
  static int pointY(int point) => point >> 32;

  static bool _hasSomethingToTake(Pointer<Void> data) {
    if (data == nullptr) return false;
    final DVDropEvent event = eventFrom(data);
    return !event.isEmpty;
  }

  /// What [data] is carrying: files where it offers CF_HDROP, else text.
  static DVDropEvent eventFrom(Pointer<Void> data, {double x = 0, double y = 0}) {
    if (data == nullptr) return DVDropEvent(x: x, y: y);
    if (_wantsFiles) {
      final List<String> paths = _files(data);
      if (paths.isNotEmpty) return DVDropEvent(paths: paths, x: x, y: y);
    }
    if (_wantsText) {
      final String? text = _text(data);
      if (text != null && text.isNotEmpty) return DVDropEvent(text: text, x: x, y: y);
    }
    return DVDropEvent(x: x, y: y);
  }

  /// Asks [data] for [format] on an HGLOBAL, or null when it has none.
  static Pointer<_StgMedium>? _medium(Pointer<Void> data, int format) {
    final Pointer<_FormatEtc> request = calloc<_FormatEtc>();
    final Pointer<_StgMedium> medium = calloc<_StgMedium>();
    request.ref
      ..cfFormat = format
      ..ptd = nullptr
      ..dwAspect = _dvAspectContent
      ..lindex = -1
      ..tymed = _tymedHGlobal;
    final Pointer<Void> vtable = data.cast<Pointer<Void>>().value;
    final Pointer<NativeFunction<_GetDataN>> getData =
        (vtable.cast<Pointer<Void>>() + _getDataIndex).value.cast();
    final int hr = getData.asFunction<_GetDataD>()(data, request, medium);
    calloc.free(request);
    if (hr != _sOk) {
      calloc.free(medium);
      return null;
    }
    return medium;
  }

  static void _releaseMedium(Pointer<_StgMedium> medium) {
    _ole32.lookupFunction<_ReleaseStgMediumN, _ReleaseStgMediumD>('ReleaseStgMedium')(medium);
    calloc.free(medium);
  }

  static List<String> _files(Pointer<Void> data) {
    final Pointer<_StgMedium>? medium = _medium(data, _cfHdrop);
    if (medium == null) return const <String>[];
    try {
      final int hDrop = medium.ref.handle.address;
      final _DragQueryFileD query =
          _shell32.lookupFunction<_DragQueryFileN, _DragQueryFileD>('DragQueryFileW');
      final int count = query(hDrop, 0xFFFFFFFF, nullptr, 0);
      final List<String> paths = <String>[];
      final Pointer<Uint16> buffer = calloc<Uint16>(32768);
      try {
        for (var i = 0; i < count; i++) {
          final int length = query(hDrop, i, buffer.cast(), 32768);
          if (length > 0) paths.add(buffer.cast<Utf16>().toDartString());
        }
      } finally {
        calloc.free(buffer);
      }
      return paths;
    } finally {
      _releaseMedium(medium);
    }
  }

  static String? _text(Pointer<Void> data) {
    final Pointer<_StgMedium>? medium = _medium(data, _cfUnicodeText);
    if (medium == null) return null;
    try {
      final int handle = medium.ref.handle.address;
      final Pointer<Void> locked =
          _kernel32.lookupFunction<_GlobalLockN, _GlobalLockD>('GlobalLock')(handle);
      if (locked == nullptr) return null;
      final String text = locked.cast<Utf16>().toDartString();
      _kernel32.lookupFunction<_GlobalUnlockN, _GlobalUnlockD>('GlobalUnlock')(handle);
      return text;
    } finally {
      _releaseMedium(medium);
    }
  }

  /// Calls the registered target's Drop the way OLE does, for a test.
  static void debugDrop(Pointer<Void> data, {int x = 0, int y = 0}) {
    final Pointer<Pointer<Void>>? object = _target;
    if (object == null) return;
    final Pointer<Void> vtable = object.value;
    final Pointer<NativeFunction<_DropN>> drop =
        (vtable.cast<Pointer<Void>>() + 6).value.cast();
    final Pointer<Uint32> effect = calloc<Uint32>();
    try {
      drop.asFunction<_DropD>()(object.cast(), data, 0, (y << 32) | (x & 0xFFFFFFFF), effect);
    } finally {
      calloc.free(effect);
    }
  }

  static void unregister() => _stop();
}
