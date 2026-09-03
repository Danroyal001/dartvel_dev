/// The tray icon on macOS: a status item in the system status bar.
///
/// NSStatusBar's item of variable length, its button titled with the
/// tooltip's first word where no image loads and imaged from the file named
/// where one does, and an NSMenu of the items asked for, each targeting the
/// same runtime-defined object the application menu uses under a second
/// action that dispatches to the tray. Hide removes the item; a menu chosen
/// after that reaches nobody.
library;

import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../../../dartvel_flutter.dart' show DVTray;
import 'macos_menus_ffi.dart';

typedef _ActionN = Void Function(Pointer<Void> self, Pointer<Void> cmd, Pointer<Void> sender);
typedef _AddMethodN = Bool Function(Pointer<Void>, Pointer<Void>, Pointer<NativeFunction<_ActionN>>, Pointer<Utf8>);
typedef _AddMethodD = bool Function(Pointer<Void>, Pointer<Void>, Pointer<NativeFunction<_ActionN>>, Pointer<Utf8>);
typedef _ReplaceMethodN = Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<NativeFunction<_ActionN>>, Pointer<Utf8>);
typedef _ReplaceMethodD = Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<NativeFunction<_ActionN>>, Pointer<Utf8>);
typedef _SendDoubleN = Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Double);
typedef _SendDoubleD = Pointer<Void> Function(Pointer<Void>, Pointer<Void>, double);

class DVMacosTray {
  const DVMacosTray._();

  static const Set<String> implemented = <String>{'tray.show', 'tray.hide'};

  static DynamicLibrary? _objc;
  static NativeCallable<_ActionN>? _action;
  static Pointer<Void>? _item;
  static final List<String> _idsByTag = <String>[];

  /// Whether a status item is in the bar now.
  static bool get shown => _item != null;

  static void register(void Function(String, FutureOr<Object?> Function(Object?)) bind, {required DynamicLibrary objc}) {
    _objc = objc;
    bind('tray.show', (Object? arguments) {
      final Map<Object?, Object?> map = arguments is Map ? arguments : const <Object?, Object?>{};
      return _show(
        icon: '${map['icon'] ?? ''}',
        tooltip: '${map['tooltip'] ?? ''}',
        menu: map['menu'] is List ? map['menu']! as List<Object?> : const <Object?>[],
      );
    });
    bind('tray.hide', (Object? _) {
      _hide();
      return true;
    });
  }

  static bool _show({required String icon, required String tooltip, required List<Object?> menu}) {
    final DVMacosObjc o = DVMacosObjc(_objc!);
    final Pointer<Void> bar = o.send0(o.cls('NSStatusBar'), 'systemStatusBar');
    if (bar == nullptr) return false;
    Pointer<Void>? item = _item;
    if (item == null) {
      item = _objc!.lookupFunction<_SendDoubleN, _SendDoubleD>('objc_msgSend')(bar, o.sel('statusItemWithLength:'), -1.0);
      if (item == nullptr) return false;
      // Retained: the bar hands back an autoreleased item, and this one has
      // to outlive the pool.
      o.send0(item, 'retain');
      _item = item;
    }
    final Pointer<Void> button = o.send0(item, 'button');
    if (button != nullptr) {
      Pointer<Void> image = nullptr;
      if (icon.isNotEmpty) {
        image = o.send1(o.send0(o.cls('NSImage'), 'alloc'), 'initWithContentsOfFile:', o.nsString(icon));
      }
      if (image != nullptr) {
        o.send1(button, 'setImage:', image);
      } else {
        o.send1(button, 'setTitle:', o.nsString(tooltip.isEmpty ? '•' : tooltip.split(' ').first));
      }
      o.send1(button, 'setToolTip:', o.nsString(tooltip));
    }

    _idsByTag.clear();
    final Pointer<Void> target = _ensureTarget(o);
    final Pointer<Void> nsMenu = o.send1(o.send0(o.cls('NSMenu'), 'alloc'), 'initWithTitle:', o.nsString('Tray'));
    for (final Object? raw in menu) {
      if (raw is! Map) continue;
      final Pointer<Void> menuItem = o.send3(
        o.send0(o.cls('NSMenuItem'), 'alloc'),
        'initWithTitle:action:keyEquivalent:',
        o.nsString('${raw['label'] ?? ''}'),
        o.sel('dartvelTrayItemSelected:'),
        o.nsString(''),
      );
      _idsByTag.add('${raw['id'] ?? ''}');
      o.sendInt(menuItem, 'setTag:', _idsByTag.length - 1);
      o.send1(menuItem, 'setTarget:', target);
      if (raw['enabled'] == false) o.sendBool(menuItem, 'setEnabled:', false);
      o.send1(nsMenu, 'addItem:', menuItem);
    }
    o.send1(item, 'setMenu:', nsMenu);
    return true;
  }

  /// The application menu's target object, given a second action for the
  /// tray so a chosen item is dispatched to DVTray rather than DVMenus.
  static Pointer<Void> _ensureTarget(DVMacosObjc o) {
    final Pointer<Void> target = DVMacosMenus.ensureTarget();
    if (_action != null) return target;
    void onAction(Pointer<Void> self, Pointer<Void> cmd, Pointer<Void> sender) {
      final int tag = o.getInt(sender, 'tag');
      if (tag >= 0 && tag < _idsByTag.length) DVTray.dispatch(_idsByTag[tag]);
    }
    final NativeCallable<_ActionN> action = NativeCallable<_ActionN>.isolateLocal(onAction);
    final Pointer<Utf8> types = 'v@:@'.toNativeUtf8();
    try {
      final Pointer<Void> cls = o.cls('DVMenuTarget');
      final bool added = _objc!.lookupFunction<_AddMethodN, _AddMethodD>('class_addMethod')(
          cls, o.sel('dartvelTrayItemSelected:'), action.nativeFunction, types);
      if (!added) {
        _objc!.lookupFunction<_ReplaceMethodN, _ReplaceMethodD>('class_replaceMethod')(
            cls, o.sel('dartvelTrayItemSelected:'), action.nativeFunction, types);
      }
    } finally {
      calloc.free(types);
    }
    _action = action;
    return target;
  }

  /// Chooses item [index] of the tray menu the way a click would, through
  /// AppKit; for a test.
  static void performAction(int index) {
    final Pointer<Void>? item = _item;
    if (item == null) return;
    final DVMacosObjc o = DVMacosObjc(_objc!);
    o.sendInt(o.send0(item, 'menu'), 'performActionForItemAtIndex:', index);
  }

  /// The tray menu's titles as AppKit has them, for a test.
  static List<String> menuTitles() {
    final Pointer<Void>? item = _item;
    if (item == null) return const <String>[];
    final DVMacosObjc o = DVMacosObjc(_objc!);
    return o.titlesOf(o.send0(item, 'menu'));
  }

  static void _hide() {
    final Pointer<Void>? item = _item;
    if (item == null) return;
    final DVMacosObjc o = DVMacosObjc(_objc!);
    o.send1(o.send0(o.cls('NSStatusBar'), 'systemStatusBar'), 'removeStatusItem:', item);
    o.send0(item, 'release');
    _item = null;
    _idsByTag.clear();
  }

  static void unregister() {
    _hide();
    _action?.close();
    _action = null;
  }
}
