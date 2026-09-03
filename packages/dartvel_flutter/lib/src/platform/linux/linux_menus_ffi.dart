/// The application menu on Linux, built into the real GTK window.
///
/// The Flutter Linux runner puts the FlView straight into the GtkWindow, so a
/// menu bar means reparenting: the window's child moves into a vertical box
/// under a GtkMenuBar. Done once; a second menu replaces the bar inside the
/// box rather than stacking another, and the original child -- the view --
/// is kept below it, because a menu over nothing is what losing it produces.
///
/// A leaf item's "activate" signal is connected to one static callback, which
/// finds the item's id by widget address and hands it to DVMenus.dispatch.
/// Flutter's Linux embedder runs the Dart UI isolate on the GTK main thread,
/// so the callback arrives on the isolate that registered it.
library dartvel.platform.linux.menus;

import 'dart:ffi';

import 'package:ffi/ffi.dart';

import '../../../dartvel_flutter.dart' show DVMenus;

typedef _VoidPN = Pointer<Void> Function();
typedef _VoidPD = Pointer<Void> Function();
typedef _NewWithLabelN = Pointer<Void> Function(Pointer<Utf8>);
typedef _NewWithLabelD = Pointer<Void> Function(Pointer<Utf8>);
typedef _P_PN = Void Function(Pointer<Void>, Pointer<Void>);
typedef _P_PD = void Function(Pointer<Void>, Pointer<Void>);
typedef _PN = Void Function(Pointer<Void>);
typedef _PD = void Function(Pointer<Void>);
typedef _P_P_I_IN = Void Function(Pointer<Void>, Pointer<Void>, Int32, Int32, Uint32);
typedef _P_P_I_ID = void Function(Pointer<Void>, Pointer<Void>, int, int, int);
typedef _BoxNewN = Pointer<Void> Function(Int32, Int32);
typedef _BoxNewD = Pointer<Void> Function(int, int);
typedef _GetChildN = Pointer<Void> Function(Pointer<Void>);
typedef _GetChildD = Pointer<Void> Function(Pointer<Void>);
typedef _ListN = Pointer<Void> Function();
typedef _ListD = Pointer<Void> Function();
typedef _ListLenN = Uint32 Function(Pointer<Void>);
typedef _ListLenD = int Function(Pointer<Void>);
typedef _ListNthN = Pointer<Void> Function(Pointer<Void>, Uint32);
typedef _ListNthD = Pointer<Void> Function(Pointer<Void>, int);
typedef _TypeNameN = Pointer<Utf8> Function(Pointer<Void>);
typedef _TypeNameD = Pointer<Utf8> Function(Pointer<Void>);
typedef _SetBoolN = Void Function(Pointer<Void>, Int32);
typedef _SetBoolD = void Function(Pointer<Void>, int);
typedef _RefN = Pointer<Void> Function(Pointer<Void>);
typedef _RefD = Pointer<Void> Function(Pointer<Void>);
typedef _ActivateCbN = Void Function(Pointer<Void>, Pointer<Void>);
typedef _ConnectN = Uint64 Function(Pointer<Void>, Pointer<Utf8>,
    Pointer<NativeFunction<_ActivateCbN>>, Pointer<Void>, Pointer<Void>, Int32);
typedef _ConnectD = int Function(Pointer<Void>, Pointer<Utf8>,
    Pointer<NativeFunction<_ActivateCbN>>, Pointer<Void>, Pointer<Void>, int);
typedef _ReorderN = Void Function(Pointer<Void>, Pointer<Void>, Int32);
typedef _ReorderD = void Function(Pointer<Void>, Pointer<Void>, int);

/// GtkMenuItem address to id, for the activate callback.
final Map<int, String> _idsByItem = <int, String>{};

void _onActivate(Pointer<Void> item, Pointer<Void> _) {
  final String? id = _idsByItem[item.address];
  if (id != null) DVMenus.dispatch(id);
}

/// The Linux application-menu binding.
class DVLinuxMenus {
  const DVLinuxMenus._();

  static const Set<String> implemented = <String>{'menus.setApplicationMenu'};

  static DynamicLibrary? _gtk;
  static DynamicLibrary? _glib;
  static DynamicLibrary? _gobject;

  /// The bar currently in the window, if this binding put one there.
  static Pointer<Void>? _bar;

  static void register(
    DynamicLibrary gtk,
    DynamicLibrary glib,
    void Function(String, Object? Function(Object?)) bind,
  ) {
    _gtk = gtk;
    _glib = glib;
    _gobject = DynamicLibrary.open('libgobject-2.0.so.0');
    bind('menus.setApplicationMenu', (Object? arguments) {
      final Map<Object?, Object?> map =
          arguments is Map ? arguments : const <Object?, Object?>{};
      final Object? items = map['items'];
      return _install(items is List ? items : const <Object?>[]);
    });
  }

  static void unregister() {
    _idsByItem.clear();
    _bar = null;
  }

  /// Builds the bar and puts it in the toplevel window.
  ///
  /// False when there is no window yet, said rather than pretended: the
  /// runner creates the window before Dart runs, so in a real app there is
  /// one, but a test or a headless start must not get a menu that went
  /// nowhere reported as success.
  static bool _install(List<Object?> items) {
    final DynamicLibrary gtk = _gtk!;
    final DynamicLibrary glib = _glib!;
    final DynamicLibrary gobject = _gobject!;

    final Pointer<Void> toplevels =
        gtk.lookupFunction<_ListN, _ListD>('gtk_window_list_toplevels')();
    final int count =
        glib.lookupFunction<_ListLenN, _ListLenD>('g_list_length')(toplevels);
    if (count == 0) return false;
    final Pointer<Void> window =
        glib.lookupFunction<_ListNthN, _ListNthD>('g_list_nth_data')(toplevels, 0);

    final _GetChildD binGetChild =
        gtk.lookupFunction<_GetChildN, _GetChildD>('gtk_bin_get_child');
    final _TypeNameD typeName = gobject
        .lookupFunction<_TypeNameN, _TypeNameD>('g_type_name_from_instance');
    final _P_PD containerAdd =
        gtk.lookupFunction<_P_PN, _P_PD>('gtk_container_add');
    final _P_PD containerRemove =
        gtk.lookupFunction<_P_PN, _P_PD>('gtk_container_remove');
    final _P_P_I_ID boxPackStart =
        gtk.lookupFunction<_P_P_I_IN, _P_P_I_ID>('gtk_box_pack_start');
    final _PD showAll = gtk.lookupFunction<_PN, _PD>('gtk_widget_show_all');
    final _PD destroy = gtk.lookupFunction<_PN, _PD>('gtk_widget_destroy');
    final _RefD ref = gobject.lookupFunction<_RefN, _RefD>('g_object_ref');
    final _PD unref = gobject.lookupFunction<_PN, _PD>('g_object_unref');

    // The box the bar lives in. Made once: the window's existing child -- the
    // Flutter view in a real app -- is moved into it below the bar.
    final Pointer<Void> child = binGetChild(window);
    Pointer<Void> box;
    if (child != nullptr && typeName(child).toDartString() == 'GtkBox' && _bar != null) {
      box = child;
      containerRemove(box, _bar!);
      destroy(_bar!);
      _idsByItem.clear();
    } else {
      box = gtk.lookupFunction<_BoxNewN, _BoxNewD>('gtk_box_new')(1, 0);
      if (child != nullptr) {
        ref(child);
        containerRemove(window, child);
        containerAdd(box, child);
        // pack_start with expand so the view keeps the space below the bar.
        gtk.lookupFunction<_SetBoolN, _SetBoolD>('gtk_widget_set_vexpand')(child, 1);
        unref(child);
      }
      containerAdd(window, box);
    }

    final Pointer<Void> bar =
        gtk.lookupFunction<_VoidPN, _VoidPD>('gtk_menu_bar_new')();
    for (final Object? item in items) {
      if (item is Map) {
        final Pointer<Void> widget = _buildItem(gtk, gobject, item);
        gtk.lookupFunction<_P_PN, _P_PD>('gtk_menu_shell_append')(bar, widget);
      }
    }
    // pack_start(box, bar, expand: false, fill: true, padding: 0)
    boxPackStart(box, bar, 0, 1, 0);
    // Put the bar first: the view was appended before it.
    _reorderFirst(gtk, box, bar);
    showAll(box);
    _bar = bar;
    return true;
  }

  static void _reorderFirst(DynamicLibrary gtk, Pointer<Void> box, Pointer<Void> bar) {
    gtk.lookupFunction<_ReorderN, _ReorderD>('gtk_box_reorder_child')(box, bar, 0);
  }

  static Pointer<Void> _buildItem(
      DynamicLibrary gtk, DynamicLibrary gobject, Map<Object?, Object?> item) {
    final Pointer<Utf8> label = '${item['label'] ?? ''}'.toNativeUtf8();
    final Pointer<Void> widget = gtk
        .lookupFunction<_NewWithLabelN, _NewWithLabelD>('gtk_menu_item_new_with_label')(label);
    calloc.free(label);
    if (item['enabled'] == false) {
      gtk.lookupFunction<_SetBoolN, _SetBoolD>('gtk_widget_set_sensitive')(widget, 0);
    }

    final Object? children = item['children'];
    if (children is List && children.isNotEmpty) {
      final Pointer<Void> submenu =
          gtk.lookupFunction<_VoidPN, _VoidPD>('gtk_menu_new')();
      for (final Object? child in children) {
        if (child is Map) {
          gtk.lookupFunction<_P_PN, _P_PD>('gtk_menu_shell_append')(
              submenu, _buildItem(gtk, gobject, child));
        }
      }
      gtk.lookupFunction<_P_PN, _P_PD>('gtk_menu_item_set_submenu')(widget, submenu);
      return widget;
    }

    // A leaf: its activation is what the application hears about.
    _idsByItem[widget.address] = '${item['id'] ?? ''}';
    final Pointer<Utf8> signal = 'activate'.toNativeUtf8();
    gobject.lookupFunction<_ConnectN, _ConnectD>('g_signal_connect_data')(
      widget,
      signal,
      Pointer.fromFunction<_ActivateCbN>(_onActivate),
      nullptr,
      nullptr,
      0,
    );
    calloc.free(signal);
    return widget;
  }
}
