/// Drag and drop on macOS: the window's view as a dragging destination.
///
/// AppKit delivers a drop to the view under the pointer: a view that has
/// registered for the dragged types is asked `draggingEntered:` and then
/// `performDragOperation:`, and reads what was dragged off the dragging
/// pasteboard. So this registers the window's content view for file URLs
/// and text, adds those two methods to the view's class at runtime -- the
/// view belongs to the engine, and a class is where a method can be added
/// to an instance nobody here created -- and reads the pasteboard.
///
/// Reading the pasteboard is the part with the bugs in it: a file manager
/// sends a list of paths, a browser sends text, and taking the first of one
/// as the other is how a drop of three files becomes one wrong path.
library;

import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../drag_drop.dart';
import 'macos_menus_ffi.dart';

typedef _ActionN = Bool Function(Pointer<Void> self, Pointer<Void> cmd, Pointer<Void> sender);
typedef _EnterN = UintPtr Function(Pointer<Void> self, Pointer<Void> cmd, Pointer<Void> sender);
typedef _AddMethodBoolN = Bool Function(Pointer<Void>, Pointer<Void>, Pointer<NativeFunction<_ActionN>>, Pointer<Utf8>);
typedef _AddMethodBoolD = bool Function(Pointer<Void>, Pointer<Void>, Pointer<NativeFunction<_ActionN>>, Pointer<Utf8>);
typedef _ReplaceMethodBoolN = Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<NativeFunction<_ActionN>>, Pointer<Utf8>);
typedef _ReplaceMethodBoolD = Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<NativeFunction<_ActionN>>, Pointer<Utf8>);
typedef _AddMethodEnterN = Bool Function(Pointer<Void>, Pointer<Void>, Pointer<NativeFunction<_EnterN>>, Pointer<Utf8>);
typedef _AddMethodEnterD = bool Function(Pointer<Void>, Pointer<Void>, Pointer<NativeFunction<_EnterN>>, Pointer<Utf8>);
typedef _ReplaceMethodEnterN = Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<NativeFunction<_EnterN>>, Pointer<Utf8>);
typedef _ReplaceMethodEnterD = Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<NativeFunction<_EnterN>>, Pointer<Utf8>);
typedef _ObjectClassN = Pointer<Void> Function(Pointer<Void>);
typedef _ObjectClassD = Pointer<Void> Function(Pointer<Void>);
typedef _GetUtf8N = Pointer<Utf8> Function(Pointer<Void>, Pointer<Void>);
typedef _GetUtf8D = Pointer<Utf8> Function(Pointer<Void>, Pointer<Void>);

/// `NSDragOperationCopy`.
const int _dragOperationCopy = 1;
const int _dragOperationNone = 0;

/// The legacy file-list type, which every file manager still writes and
/// which carries every path rather than only the first.
const String _filenamesType = 'NSFilenamesPboardType';
const String _stringType = 'public.utf8-plain-text';
const String _fileUrlType = 'public.file-url';

class DVMacosDragDrop {
  const DVMacosDragDrop._();

  static const Set<String> implemented = <String>{'dragDrop.accept', 'dragDrop.stop'};

  static DynamicLibrary? _objc;
  static NativeCallable<_ActionN>? _perform;
  static NativeCallable<_EnterN>? _entered;
  static Pointer<Void>? _view;
  static bool _wantsFiles = true;
  static bool _wantsText = true;

  /// Why the last accept did not register a dragging destination.
  static String? lastError;

  /// Whether a view is registered for drops.
  static bool get accepting => _view != null;

  static DVMacosObjc get _o => DVMacosObjc(_objc!);

  static void register(void Function(String, FutureOr<Object?> Function(Object?)) bind, {required DynamicLibrary objc}) {
    _objc = objc;
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

  /// The window's content view, or null when the application has no window
  /// yet -- a headless start, or a test with no run loop.
  static Pointer<Void>? _contentView() {
    final DVMacosObjc o = _o;
    final Pointer<Void> app = o.send0(o.cls('NSApplication'), 'sharedApplication');
    if (app == nullptr) return null;
    Pointer<Void> window = o.send0(app, 'mainWindow');
    if (window == nullptr) {
      final Pointer<Void> windows = o.send0(app, 'windows');
      if (windows == nullptr || o.getInt(windows, 'count') == 0) return null;
      window = o.getAt(windows, 'objectAtIndex:', 0);
    }
    final Pointer<Void> view = o.send0(window, 'contentView');
    return view == nullptr ? null : view;
  }

  static bool _accept() {
    final Pointer<Void>? view = _contentView();
    if (view == null) {
      lastError = 'no window to take drops';
      return false;
    }
    _install(view);
    final DVMacosObjc o = _o;
    final Pointer<Void> types = o.send0(o.cls('NSMutableArray'), 'array');
    if (_wantsFiles) {
      o.send1(types, 'addObject:', o.nsString(_filenamesType));
      o.send1(types, 'addObject:', o.nsString(_fileUrlType));
    }
    if (_wantsText) o.send1(types, 'addObject:', o.nsString(_stringType));
    o.send1(view, 'registerForDraggedTypes:', types);
    _view = view;
    lastError = null;
    return true;
  }

  static void _stop() {
    final Pointer<Void>? view = _view;
    if (view == null) return;
    _o.send0(view, 'unregisterDraggedTypes');
    _view = null;
  }

  /// Adds the two dragging-destination methods to [view]'s class.
  ///
  /// The view is the engine's, so the methods go on its class: that is
  /// where a method can be added to an instance this code did not create.
  static void _install(Pointer<Void> view) {
    if (_perform != null) return;
    final DVMacosObjc o = _o;

    int onEntered(Pointer<Void> self, Pointer<Void> cmd, Pointer<Void> sender) {
      // What the drag is carrying decides whether the window will take it,
      // which is what turns the cursor into a copy cursor.
      return eventFrom(o.send0(sender, 'draggingPasteboard')).isEmpty
          ? _dragOperationNone
          : _dragOperationCopy;
    }

    bool onPerform(Pointer<Void> self, Pointer<Void> cmd, Pointer<Void> sender) {
      final DVDropEvent event = eventFrom(o.send0(sender, 'draggingPasteboard'));
      if (event.isEmpty) return false;
      DVDragDrop.dispatch(event);
      return true;
    }

    final NativeCallable<_EnterN> entered = NativeCallable<_EnterN>.isolateLocal(onEntered, exceptionalReturn: 0);
    final NativeCallable<_ActionN> perform = NativeCallable<_ActionN>.isolateLocal(onPerform, exceptionalReturn: false);
    final Pointer<Void> cls =
        _objc!.lookupFunction<_ObjectClassN, _ObjectClassD>('object_getClass')(view);
    // `Q@:@` and `B@:@`: an unsigned drag operation and a boolean, each
    // taking the sender.
    final Pointer<Utf8> enterTypes = 'Q@:@'.toNativeUtf8();
    final Pointer<Utf8> performTypes = 'B@:@'.toNativeUtf8();
    try {
      if (!_objc!.lookupFunction<_AddMethodEnterN, _AddMethodEnterD>('class_addMethod')(
          cls, o.sel('draggingEntered:'), entered.nativeFunction, enterTypes)) {
        _objc!.lookupFunction<_ReplaceMethodEnterN, _ReplaceMethodEnterD>('class_replaceMethod')(
            cls, o.sel('draggingEntered:'), entered.nativeFunction, enterTypes);
      }
      if (!_objc!.lookupFunction<_AddMethodBoolN, _AddMethodBoolD>('class_addMethod')(
          cls, o.sel('performDragOperation:'), perform.nativeFunction, performTypes)) {
        _objc!.lookupFunction<_ReplaceMethodBoolN, _ReplaceMethodBoolD>('class_replaceMethod')(
            cls, o.sel('performDragOperation:'), perform.nativeFunction, performTypes);
      }
    } finally {
      calloc.free(enterTypes);
      calloc.free(performTypes);
    }
    _entered = entered;
    _perform = perform;
  }

  /// What [pasteboard] is carrying: the files a file manager wrote, else
  /// the text a browser or an editor wrote.
  static DVDropEvent eventFrom(Pointer<Void> pasteboard, {double x = 0, double y = 0}) {
    if (pasteboard == nullptr) return DVDropEvent(x: x, y: y);
    final DVMacosObjc o = _o;
    if (_wantsFiles) {
      // The whole list, not the first: a drop of three files that came back
      // as one path is the bug this type exists to avoid.
      final Pointer<Void> list = o.send1(pasteboard, 'propertyListForType:', o.nsString(_filenamesType));
      if (list != nullptr) {
        final int count = o.getInt(list, 'count');
        final List<String> paths = <String>[
          for (var i = 0; i < count; i++) _string(o.getAt(list, 'objectAtIndex:', i)) ?? '',
        ]..removeWhere((String p) => p.isEmpty);
        if (paths.isNotEmpty) return DVDropEvent(paths: paths, x: x, y: y);
      }
      final String? single = _string(o.send1(pasteboard, 'stringForType:', o.nsString(_fileUrlType)));
      if (single != null && single.isNotEmpty) {
        final Uri? url = Uri.tryParse(single);
        if (url != null && url.scheme == 'file') {
          return DVDropEvent(paths: <String>[Uri.decodeComponent(url.path)], x: x, y: y);
        }
      }
    }
    if (_wantsText) {
      final String? text = _string(o.send1(pasteboard, 'stringForType:', o.nsString(_stringType)));
      if (text != null && text.isNotEmpty) return DVDropEvent(text: text, x: x, y: y);
    }
    return DVDropEvent(x: x, y: y);
  }

  static String? _string(Pointer<Void> value) {
    if (value == nullptr) return null;
    final Pointer<Utf8> utf8 =
        _objc!.lookupFunction<_GetUtf8N, _GetUtf8D>('objc_msgSend')(value, _o.sel('UTF8String'));
    return utf8 == nullptr ? null : utf8.toDartString();
  }

  static void unregister() {
    _stop();
    _perform?.close();
    _entered?.close();
    _perform = null;
    _entered = null;
  }
}
