/// The tray icon on macOS: a status item in the system status bar.
///
/// NSStatusBar's item of variable length, its button imaged from the icon
/// file -- 18 points high, a template image when asked, drawn in the bar's
/// own colour -- or titled with the tooltip's first word where no image
/// loads, and an NSMenu of the items asked for: separators, disabled header
/// lines, check marks, submenus. Every leaf targets the same runtime-defined
/// object the application menu uses, under a second action that dispatches
/// to the tray by the item's number. Showing again changes the same status
/// item in place; hide removes it, and a menu chosen after that reaches
/// nobody.
///
/// A click on a status item opens its menu, as every macOS menu-bar
/// application does, so `onActivate` is not delivered here.
library;

import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../../../dartvel_flutter.dart' show DVTray;
import '../tray_menu.dart';
import 'macos_menus_ffi.dart';

typedef _ActionN = Void Function(Pointer<Void> self, Pointer<Void> cmd, Pointer<Void> sender);
typedef _AddMethodN = Bool Function(Pointer<Void>, Pointer<Void>, Pointer<NativeFunction<_ActionN>>, Pointer<Utf8>);
typedef _AddMethodD = bool Function(Pointer<Void>, Pointer<Void>, Pointer<NativeFunction<_ActionN>>, Pointer<Utf8>);
typedef _ReplaceMethodN = Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<NativeFunction<_ActionN>>, Pointer<Utf8>);
typedef _ReplaceMethodD = Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<NativeFunction<_ActionN>>, Pointer<Utf8>);
typedef _SendDoubleN = Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Double);
typedef _SendDoubleD = Pointer<Void> Function(Pointer<Void>, Pointer<Void>, double);
// setSize: takes an NSSize, two doubles, which both arm64 and x86_64 pass
// in the first two floating-point registers -- the same as two doubles.
typedef _SendSizeN = Void Function(Pointer<Void>, Pointer<Void>, Double, Double);
typedef _SendSizeD = void Function(Pointer<Void>, Pointer<Void>, double, double);

class DVMacosTray {
  const DVMacosTray._();

  static const Set<String> implemented = <String>{'tray.show', 'tray.hide'};

  static DynamicLibrary? _objc;
  static NativeCallable<_ActionN>? _action;
  static Pointer<Void>? _item;
  static Map<int, DVTrayNode> _byTag = const <int, DVTrayNode>{};

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
        template: map['template'] == true,
      );
    });
    bind('tray.hide', (Object? _) {
      _hide();
      return true;
    });
  }

  static bool _show({required String icon, required String tooltip, required List<Object?> menu, bool template = false}) {
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
    // Everything below changes the item that is already in the bar: a new
    // image, tooltip or menu on the same NSStatusItem, so an update does
    // not take the icon out of the bar and put it back.
    final Pointer<Void> button = o.send0(item, 'button');
    if (button != nullptr) {
      Pointer<Void> image = nullptr;
      final String? file = dvTrayIconFile(icon);
      if (file != null) {
        image = o.send1(o.send0(o.cls('NSImage'), 'alloc'), 'initWithContentsOfFile:', o.nsString(file));
      }
      if (image != nullptr) {
        // A status bar icon is drawn at the bar's height, 18 points by
        // AppKit's guidelines; an image at its pixel size would fill the
        // bar with a 512-point picture.
        _objc!.lookupFunction<_SendSizeN, _SendSizeD>('objc_msgSend')(image, o.sel('setSize:'), 18, 18);
        // A template image is drawn in the bar's own colour, light or dark.
        o.sendBool(image, 'setTemplate:', template);
        o.send1(button, 'setImage:', image);
        o.send1(button, 'setTitle:', o.nsString(''));
      } else {
        o.send1(button, 'setImage:', nullptr);
        o.send1(button, 'setTitle:', o.nsString(tooltip.isEmpty ? '•' : tooltip.split(' ').first));
      }
      o.send1(button, 'setToolTip:', o.nsString(tooltip));
    }

    final List<DVTrayNode> nodes = DVTrayNode.parse(menu);
    _byTag = DVTrayNode.index(nodes);
    final Pointer<Void> target = _ensureTarget(o);
    o.send1(item, 'setMenu:', _buildMenu(o, nodes, target));
    return true;
  }

  /// An NSMenu of [nodes], every leaf tagged with its number and targeting
  /// the tray action. Items are enabled as they were asked for rather than
  /// as AppKit's validation would decide, so a disabled item stays disabled.
  static Pointer<Void> _buildMenu(DVMacosObjc o, List<DVTrayNode> nodes, Pointer<Void> target) {
    final Pointer<Void> nsMenu = o.send1(o.send0(o.cls('NSMenu'), 'alloc'), 'initWithTitle:', o.nsString('Tray'));
    o.sendBool(nsMenu, 'setAutoenablesItems:', false);
    for (final DVTrayNode node in nodes) {
      if (node.kind == .separator) {
        o.send1(nsMenu, 'addItem:', o.send0(o.cls('NSMenuItem'), 'separatorItem'));
        continue;
      }
      final bool leaf = node.kind == .item;
      final Pointer<Void> menuItem = o.send3(
        o.send0(o.cls('NSMenuItem'), 'alloc'),
        'initWithTitle:action:keyEquivalent:',
        o.nsString(node.label),
        leaf ? o.sel('dartvelTrayItemSelected:') : nullptr,
        o.nsString(''),
      );
      o.sendInt(menuItem, 'setTag:', node.number);
      if (leaf) o.send1(menuItem, 'setTarget:', target);
      o.sendBool(menuItem, 'setEnabled:', node.kind == .submenu || node.enabled);
      final bool? checked = node.checked;
      // NSControlStateValueOn is 1. A radio item is drawn with the same
      // check mark: AppKit menus have no separate radio glyph.
      if (checked != null) o.sendInt(menuItem, 'setState:', checked ? 1 : 0);
      if (node.kind == .submenu) {
        o.send1(menuItem, 'setSubmenu:', _buildMenu(o, node.children, target));
      }
      o.send1(nsMenu, 'addItem:', menuItem);
    }
    return nsMenu;
  }

  /// The application menu's target object, given a second action for the
  /// tray so a chosen item is dispatched to DVTray rather than DVMenus.
  static Pointer<Void> _ensureTarget(DVMacosObjc o) {
    final Pointer<Void> target = DVMacosMenus.ensureTarget();
    if (_action != null) return target;
    void onAction(Pointer<Void> self, Pointer<Void> cmd, Pointer<Void> sender) {
      final DVTrayNode? node = _byTag[o.getInt(sender, 'tag')];
      if (node != null && node.choosable) DVTray.dispatch(node.id);
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

  /// Chooses item [index] of the tray menu's top level the way a click
  /// would, through AppKit; for a test.
  static void performAction(int index) {
    final Pointer<Void>? item = _item;
    if (item == null) return;
    final DVMacosObjc o = DVMacosObjc(_objc!);
    o.sendInt(o.send0(item, 'menu'), 'performActionForItemAtIndex:', index);
  }

  /// The tray menu's top-level titles as AppKit has them, for a test. A
  /// separator's title is empty.
  static List<String> menuTitles() {
    final Pointer<Void>? item = _item;
    if (item == null) return const <String>[];
    final DVMacosObjc o = DVMacosObjc(_objc!);
    return o.titlesOf(o.send0(item, 'menu'));
  }

  /// The state (0 off, 1 on) and enabled flag of top-level item [index], as
  /// AppKit has them; for a test.
  static (int state, bool enabled) itemState(int index) {
    final DVMacosObjc o = DVMacosObjc(_objc!);
    final Pointer<Void> menuItem = o.getAt(o.send0(_item!, 'menu'), 'itemAtIndex:', index);
    return (o.getInt(menuItem, 'state'), o.getBool(menuItem, 'isEnabled'));
  }

  static void _hide() {
    final Pointer<Void>? item = _item;
    if (item == null) return;
    final DVMacosObjc o = DVMacosObjc(_objc!);
    o.send1(o.send0(o.cls('NSStatusBar'), 'systemStatusBar'), 'removeStatusItem:', item);
    o.send0(item, 'release');
    _item = null;
    _byTag = const <int, DVTrayNode>{};
  }

  static void unregister() {
    _hide();
    // Not closed. Its function pointer was installed on an Objective-C class
    // with class_addMethod, and a method cannot be removed from a class: the
    // class points at this trampoline for the life of the process, so freeing
    // it leaves the next message to that selector jumping into freed memory.
    // One trampoline per process is the correct price for that.
  }
}
