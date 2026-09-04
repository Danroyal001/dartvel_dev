/// The application menu on macOS: NSMenu as NSApp's main menu.
///
/// Every item is an NSMenuItem whose target is one Objective-C object this
/// binding defines at runtime -- a class with a single action method whose
/// implementation is an isolate-local callable -- and whose tag is the
/// item's index in the id table. AppKit calls the action on the main thread,
/// which is where Flutter runs the root isolate on macOS, and the id is
/// dispatched from there. A test drives the same path with
/// performActionForItemAtIndex:, which AppKit runs synchronously.
library;

import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../../../dartvel_flutter.dart' show DVMenus;

typedef _GetClassN = Pointer<Void> Function(Pointer<Utf8>);
typedef _GetClassD = Pointer<Void> Function(Pointer<Utf8>);
typedef _SelN = Pointer<Void> Function(Pointer<Utf8>);
typedef _SelD = Pointer<Void> Function(Pointer<Utf8>);
typedef _Send0N = Pointer<Void> Function(Pointer<Void>, Pointer<Void>);
typedef _Send0D = Pointer<Void> Function(Pointer<Void>, Pointer<Void>);
typedef _Send1N = Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<Void>);
typedef _Send1D = Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<Void>);
typedef _SendStrN = Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<Utf8>);
typedef _SendStrD = Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<Utf8>);
typedef _Send2N = Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<Void>, Pointer<Void>);
typedef _Send2D = Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<Void>, Pointer<Void>);
typedef _Send3N = Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<Void>, Pointer<Void>, Pointer<Void>);
typedef _Send3D = Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<Void>, Pointer<Void>, Pointer<Void>);
typedef _SendIntN = Void Function(Pointer<Void>, Pointer<Void>, Int64);
typedef _SendIntD = void Function(Pointer<Void>, Pointer<Void>, int);
typedef _SendBoolN = Void Function(Pointer<Void>, Pointer<Void>, Bool);
typedef _SendBoolD = void Function(Pointer<Void>, Pointer<Void>, bool);
typedef _GetIntN = Int64 Function(Pointer<Void>, Pointer<Void>);
typedef _GetBoolN = Bool Function(Pointer<Void>, Pointer<Void>);
typedef _GetBoolD = bool Function(Pointer<Void>, Pointer<Void>);
typedef _GetIntD = int Function(Pointer<Void>, Pointer<Void>);
typedef _GetAtN = Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Int64);
typedef _GetAtD = Pointer<Void> Function(Pointer<Void>, Pointer<Void>, int);
typedef _GetUtf8N = Pointer<Utf8> Function(Pointer<Void>, Pointer<Void>);
typedef _GetUtf8D = Pointer<Utf8> Function(Pointer<Void>, Pointer<Void>);
typedef _ActionN = Void Function(Pointer<Void> self, Pointer<Void> cmd, Pointer<Void> sender);
typedef _AllocClassN = Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, IntPtr);
typedef _AllocClassD = Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>, int);
typedef _AddMethodN = Bool Function(Pointer<Void>, Pointer<Void>, Pointer<NativeFunction<_ActionN>>, Pointer<Utf8>);
typedef _AddMethodD = bool Function(Pointer<Void>, Pointer<Void>, Pointer<NativeFunction<_ActionN>>, Pointer<Utf8>);
typedef _ReplaceMethodN = Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<NativeFunction<_ActionN>>, Pointer<Utf8>);
typedef _ReplaceMethodD = Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<NativeFunction<_ActionN>>, Pointer<Utf8>);
typedef _RegisterClassN = Void Function(Pointer<Void>);
typedef _RegisterClassD = void Function(Pointer<Void>);

/// objc_msgSend, typed per call shape, over one runtime handle.
class DVMacosObjc {
  const DVMacosObjc(this.objc);
  final DynamicLibrary objc;

  Pointer<Void> cls(String name) {
    final Pointer<Utf8> p = name.toNativeUtf8();
    try {
      return objc.lookupFunction<_GetClassN, _GetClassD>('objc_getClass')(p);
    } finally {
      calloc.free(p);
    }
  }

  Pointer<Void> sel(String name) {
    final Pointer<Utf8> p = name.toNativeUtf8();
    try {
      return objc.lookupFunction<_SelN, _SelD>('sel_registerName')(p);
    } finally {
      calloc.free(p);
    }
  }

  Pointer<Void> nsString(String value) {
    final Pointer<Utf8> p = value.toNativeUtf8();
    try {
      return objc.lookupFunction<_SendStrN, _SendStrD>('objc_msgSend')(cls('NSString'), sel('stringWithUTF8String:'), p);
    } finally {
      calloc.free(p);
    }
  }

  Pointer<Void> send0(Pointer<Void> r, String s) => objc.lookupFunction<_Send0N, _Send0D>('objc_msgSend')(r, sel(s));
  Pointer<Void> send1(Pointer<Void> r, String s, Pointer<Void> a) =>
      objc.lookupFunction<_Send1N, _Send1D>('objc_msgSend')(r, sel(s), a);
  Pointer<Void> send2(Pointer<Void> r, String s, Pointer<Void> a, Pointer<Void> b) =>
      objc.lookupFunction<_Send2N, _Send2D>('objc_msgSend')(r, sel(s), a, b);
  Pointer<Void> send3(Pointer<Void> r, String s, Pointer<Void> a, Pointer<Void> b, Pointer<Void> c) =>
      objc.lookupFunction<_Send3N, _Send3D>('objc_msgSend')(r, sel(s), a, b, c);
  void sendInt(Pointer<Void> r, String s, int a) => objc.lookupFunction<_SendIntN, _SendIntD>('objc_msgSend')(r, sel(s), a);
  void sendBool(Pointer<Void> r, String s, bool a) => objc.lookupFunction<_SendBoolN, _SendBoolD>('objc_msgSend')(r, sel(s), a);
  int getInt(Pointer<Void> r, String s) => objc.lookupFunction<_GetIntN, _GetIntD>('objc_msgSend')(r, sel(s));

  /// A BOOL-returning message. Read as a byte, because that is what the
  /// runtime returns and reading it as an int picks up whatever is in the
  /// rest of the register.
  bool getBool(Pointer<Void> r, String s) =>
      objc.lookupFunction<_GetBoolN, _GetBoolD>('objc_msgSend')(r, sel(s));
  Pointer<Void> getAt(Pointer<Void> r, String s, int i) => objc.lookupFunction<_GetAtN, _GetAtD>('objc_msgSend')(r, sel(s), i);

  /// The titles of [menu]'s items.
  List<String> titlesOf(Pointer<Void> menu) {
    if (menu == nullptr) return const <String>[];
    final int count = getInt(menu, 'numberOfItems');
    return <String>[
      for (var i = 0; i < count; i++)
        objc.lookupFunction<_GetUtf8N, _GetUtf8D>('objc_msgSend')(send0(getAt(menu, 'itemAtIndex:', i), 'title'), sel('UTF8String')).toDartString(),
    ];
  }
}

class DVMacosMenus {
  const DVMacosMenus._();

  static const Set<String> implemented = <String>{'menus.setApplicationMenu'};

  static DynamicLibrary? _objc;
  static NativeCallable<_ActionN>? _action;
  static Pointer<Void>? _target;
  static final List<String> _idsByTag = <String>[];

  static void register(void Function(String, FutureOr<Object?> Function(Object?)) bind, {required DynamicLibrary objc}) {
    _objc = objc;
    bind('menus.setApplicationMenu', (Object? arguments) {
      final Map<Object?, Object?> map = arguments is Map ? arguments : const <Object?, Object?>{};
      final Object? items = map['items'];
      return _install(items is List ? items : const <Object?>[]);
    });
  }

  static Pointer<Void> _class(String name) {
    final Pointer<Utf8> p = name.toNativeUtf8();
    try {
      return _objc!.lookupFunction<_GetClassN, _GetClassD>('objc_getClass')(p);
    } finally {
      calloc.free(p);
    }
  }

  static Pointer<Void> _sel(String name) {
    final Pointer<Utf8> p = name.toNativeUtf8();
    try {
      return _objc!.lookupFunction<_SelN, _SelD>('sel_registerName')(p);
    } finally {
      calloc.free(p);
    }
  }

  static Pointer<Void> _nsString(String value) {
    final Pointer<Utf8> p = value.toNativeUtf8();
    try {
      return _objc!.lookupFunction<_SendStrN, _SendStrD>('objc_msgSend')(
          _class('NSString'), _sel('stringWithUTF8String:'), p);
    } finally {
      calloc.free(p);
    }
  }

  static Pointer<Void> _send0(Pointer<Void> r, String sel) =>
      _objc!.lookupFunction<_Send0N, _Send0D>('objc_msgSend')(r, _sel(sel));
  static Pointer<Void> _send1(Pointer<Void> r, String sel, Pointer<Void> a) =>
      _objc!.lookupFunction<_Send1N, _Send1D>('objc_msgSend')(r, _sel(sel), a);
  static void _sendInt(Pointer<Void> r, String sel, int a) =>
      _objc!.lookupFunction<_SendIntN, _SendIntD>('objc_msgSend')(r, _sel(sel), a);
  static void _sendBool(Pointer<Void> r, String sel, bool a) =>
      _objc!.lookupFunction<_SendBoolN, _SendBoolD>('objc_msgSend')(r, _sel(sel), a);
  static int _getInt(Pointer<Void> r, String sel) =>
      _objc!.lookupFunction<_GetIntN, _GetIntD>('objc_msgSend')(r, _sel(sel));
  static Pointer<Void> _getAt(Pointer<Void> r, String sel, int i) =>
      _objc!.lookupFunction<_GetAtN, _GetAtD>('objc_msgSend')(r, _sel(sel), i);

  static Pointer<Void> get _app => _send0(_class('NSApplication'), 'sharedApplication');

  /// The one target every item points at, its class defined on first use.
  /// The tray's items share it, under an action of their own.
  static Pointer<Void> ensureTarget() {
    final Pointer<Void>? existing = _target;
    if (existing != null) return existing;

    void onAction(Pointer<Void> self, Pointer<Void> cmd, Pointer<Void> sender) {
      final int tag = _getInt(sender, 'tag');
      if (tag >= 0 && tag < _idsByTag.length) DVMenus.dispatch(_idsByTag[tag]);
    }

    final NativeCallable<_ActionN> action = NativeCallable<_ActionN>.isolateLocal(onAction);
    final Pointer<Utf8> name = 'DVMenuTarget'.toNativeUtf8();
    final Pointer<Utf8> types = 'v@:@'.toNativeUtf8();
    try {
      Pointer<Void> cls = _class('DVMenuTarget');
      if (cls == nullptr) {
        cls = _objc!.lookupFunction<_AllocClassN, _AllocClassD>('objc_allocateClassPair')(_class('NSObject'), name, 0);
        _objc!.lookupFunction<_AddMethodN, _AddMethodD>('class_addMethod')(
            cls, _sel('dartvelMenuItemSelected:'), action.nativeFunction, types);
        _objc!.lookupFunction<_RegisterClassN, _RegisterClassD>('objc_registerClassPair')(cls);
      } else {
        // The class outlives a registration; the callable does not. Point
        // the method at this one.
        _objc!.lookupFunction<_ReplaceMethodN, _ReplaceMethodD>('class_replaceMethod')(
            cls, _sel('dartvelMenuItemSelected:'), action.nativeFunction, types);
      }
      final Pointer<Void> instance = _send0(_send0(cls, 'alloc'), 'init');
      _action = action;
      _target = instance;
      return instance;
    } finally {
      calloc.free(name);
      calloc.free(types);
    }
  }

  static bool _install(List<Object?> items) {
    final Pointer<Void> app = _app;
    if (app == nullptr) return false;
    _idsByTag.clear();
    final Pointer<Void> target = ensureTarget();
    final Pointer<Void> main = _send1(_send0(_class('NSMenu'), 'alloc'), 'initWithTitle:', _nsString('MainMenu'));
    for (final Object? raw in items) {
      if (raw is! Map) continue;
      _send1(main, 'addItem:', _buildItem(raw, target));
    }
    _send1(app, 'setMainMenu:', main);
    return true;
  }

  static Pointer<Void> _buildItem(Map<Object?, Object?> item, Pointer<Void> target) {
    final String label = '${item['label'] ?? ''}';
    final Object? children = item['children'];
    final bool leaf = children is! List || children.isEmpty;
    final Pointer<Void> menuItem = _objc!.lookupFunction<_Send3N, _Send3D>('objc_msgSend')(
      _send0(_class('NSMenuItem'), 'alloc'),
      _sel('initWithTitle:action:keyEquivalent:'),
      _nsString(label),
      leaf ? _sel('dartvelMenuItemSelected:') : nullptr,
      _nsString(''),
    );
    _idsByTag.add('${item['id'] ?? ''}');
    _sendInt(menuItem, 'setTag:', _idsByTag.length - 1);
    if (leaf) _send1(menuItem, 'setTarget:', target);
    if (item['enabled'] == false) _sendBool(menuItem, 'setEnabled:', false);
    if (!leaf) {
      final Pointer<Void> submenu = _send1(_send0(_class('NSMenu'), 'alloc'), 'initWithTitle:', _nsString(label));
      for (final Object? child in children) {
        if (child is Map) _send1(submenu, 'addItem:', _buildItem(child, target));
      }
      _send1(menuItem, 'setSubmenu:', submenu);
    }
    return menuItem;
  }

  // -- read-back, for the test -------------------------------------------

  /// The titles of the main menu's items, as AppKit has them.
  static List<String> mainMenuTitles() {
    final Pointer<Void> menu = _send0(_app, 'mainMenu');
    if (menu == nullptr) return const <String>[];
    final int count = _getInt(menu, 'numberOfItems');
    return <String>[
      for (var i = 0; i < count; i++)
        _objc!.lookupFunction<_GetUtf8N, _GetUtf8D>('objc_msgSend')(
                _send0(_getAt(menu, 'itemAtIndex:', i), 'title'), _sel('UTF8String'))
            .toDartString(),
    ];
  }

  /// Activates child [childIndex] of top-level item [topIndex] the way a
  /// click would, through AppKit.
  static void performAction(int topIndex, int childIndex) {
    final Pointer<Void> menu = _send0(_app, 'mainMenu');
    final Pointer<Void> submenu = _send0(_getAt(menu, 'itemAtIndex:', topIndex), 'submenu');
    _sendInt(submenu, 'performActionForItemAtIndex:', childIndex);
  }

  /// Forgets the items and closes the callable. The menu AppKit shows is
  /// left as it is; an item clicked after this reaches nobody rather than a
  /// closed callable, because the target is dropped first.
  static void unregister() {
    _idsByTag.clear();
    _target = null;
    _action?.close();
    _action = null;
  }
}
