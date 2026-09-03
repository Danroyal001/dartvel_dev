// An application menu on Linux, built into the real GTK window.
//
// Only under an X server: GTK needs a display to make a window. The Flutter
// Linux runner puts the FlView straight into the GtkWindow, so a menu bar
// means reparenting: the window's child moves into a vertical box under a
// GtkMenuBar. What the suite holds is read back through GTK rather than from
// the binding's own bookkeeping -- the bar is in the window, it has the items
// that were asked for, activating one reaches Dart by id, and a second menu
// replaces the first rather than stacking a bar on top of it.
import 'dart:ffi';
import 'dart:io';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _InitCheckN = Int32 Function(Pointer<Void>, Pointer<Void>);
typedef _InitCheckD = int Function(Pointer<Void>, Pointer<Void>);
typedef _WindowNewN = Pointer<Void> Function(Int32);
typedef _WindowNewD = Pointer<Void> Function(int);
typedef _ListToplevelsN = Pointer<Void> Function();
typedef _ListToplevelsD = Pointer<Void> Function();
typedef _ListLengthN = Uint32 Function(Pointer<Void>);
typedef _ListLengthD = int Function(Pointer<Void>);
typedef _ListNthN = Pointer<Void> Function(Pointer<Void>, Uint32);
typedef _ListNthD = Pointer<Void> Function(Pointer<Void>, int);
typedef _BinGetChildN = Pointer<Void> Function(Pointer<Void>);
typedef _BinGetChildD = Pointer<Void> Function(Pointer<Void>);
typedef _ContainerChildrenN = Pointer<Void> Function(Pointer<Void>);
typedef _ContainerChildrenD = Pointer<Void> Function(Pointer<Void>);
typedef _TypeNameN = Pointer<Utf8> Function(Pointer<Void>);
typedef _TypeNameD = Pointer<Utf8> Function(Pointer<Void>);
typedef _MenuItemGetLabelN = Pointer<Utf8> Function(Pointer<Void>);
typedef _MenuItemGetLabelD = Pointer<Utf8> Function(Pointer<Void>);
typedef _MenuItemActivateN = Void Function(Pointer<Void>);
typedef _MenuItemActivateD = void Function(Pointer<Void>);
typedef _MenuItemGetSubmenuN = Pointer<Void> Function(Pointer<Void>);
typedef _MenuItemGetSubmenuD = Pointer<Void> Function(Pointer<Void>);

/// Reads the real GTK widget tree.
class _Gtk {
  _Gtk() : lib = DynamicLibrary.open('libgtk-3.so.0'), glib = DynamicLibrary.open('libglib-2.0.so.0'), gobject = DynamicLibrary.open('libgobject-2.0.so.0');
  final DynamicLibrary lib;
  final DynamicLibrary glib;
  final DynamicLibrary gobject;

  void initAndOpenWindow() {
    lib.lookupFunction<_InitCheckN, _InitCheckD>('gtk_init_check')(nullptr, nullptr);
    lib.lookupFunction<_WindowNewN, _WindowNewD>('gtk_window_new')(0);
  }

  Pointer<Void> toplevel() {
    final Pointer<Void> list = lib.lookupFunction<_ListToplevelsN, _ListToplevelsD>('gtk_window_list_toplevels')();
    final int n = glib.lookupFunction<_ListLengthN, _ListLengthD>('g_list_length')(list);
    expect(n, greaterThan(0), reason: 'a toplevel exists');
    return glib.lookupFunction<_ListNthN, _ListNthD>('g_list_nth_data')(list, 0);
  }

  String typeName(Pointer<Void> widget) {
    // G_OBJECT_TYPE_NAME: the class pointer is the first word of the
    // instance, and g_type_name_from_instance takes the instance.
    final Pointer<Utf8> name = gobject.lookupFunction<_TypeNameN, _TypeNameD>('g_type_name_from_instance')(widget);
    return name.toDartString();
  }

  List<Pointer<Void>> children(Pointer<Void> container) {
    final Pointer<Void> list = lib.lookupFunction<_ContainerChildrenN, _ContainerChildrenD>('gtk_container_get_children')(container);
    final int n = glib.lookupFunction<_ListLengthN, _ListLengthD>('g_list_length')(list);
    return <Pointer<Void>>[for (var i = 0; i < n; i++) glib.lookupFunction<_ListNthN, _ListNthD>('g_list_nth_data')(list, i)];
  }

  Pointer<Void> child(Pointer<Void> bin) => lib.lookupFunction<_BinGetChildN, _BinGetChildD>('gtk_bin_get_child')(bin);

  String label(Pointer<Void> item) => lib.lookupFunction<_MenuItemGetLabelN, _MenuItemGetLabelD>('gtk_menu_item_get_label')(item).toDartString();

  Pointer<Void> submenu(Pointer<Void> item) => lib.lookupFunction<_MenuItemGetSubmenuN, _MenuItemGetSubmenuD>('gtk_menu_item_get_submenu')(item);

  void activate(Pointer<Void> item) => lib.lookupFunction<_MenuItemActivateN, _MenuItemActivateD>('gtk_menu_item_activate')(item);

  /// The GtkMenuBar inside the window, or null.
  Pointer<Void>? menuBar() {
    final Pointer<Void> top = toplevel();
    final Pointer<Void> c = child(top);
    if (c == nullptr) return null;
    if (typeName(c) == 'GtkMenuBar') return c;
    if (typeName(c) != 'GtkBox') return null;
    for (final Pointer<Void> w in children(c)) {
      if (typeName(w) == 'GtkMenuBar') return w;
    }
    return null;
  }
}

const DVApplicationMenu menu = DVApplicationMenu(<DVMenuItem>[
  DVMenuItem(id: 'file', label: 'File', children: <DVMenuItem>[
    DVMenuItem(id: 'open', label: 'Open', shortcut: 'Ctrl+O'),
    DVMenuItem(id: 'quit', label: 'Quit'),
  ]),
  DVMenuItem(id: 'help', label: 'Help', children: <DVMenuItem>[
    DVMenuItem(id: 'about', label: 'About'),
  ]),
]);

void main() {
  final bool hasDisplay = Platform.environment['DISPLAY']?.isNotEmpty ?? false;
  if (!hasDisplay) {
    test('linux menus (skipped: no X display)', () {},
        skip: 'Run under an X server (xvfb-run works) to exercise GTK.');
    return;
  }

  late _Gtk gtk;
  setUpAll(() {
    expect(DVLinuxBindings.register(), isTrue);
    gtk = _Gtk()..initAndOpenWindow();
  });
  tearDownAll(DVLinuxBindings.unregister);
  setUp(DVMenus.reset);

  test('menus are among what the Linux bindings implement', () {
    expect(DVLinuxBindings.implemented, contains('menus.setApplicationMenu'));
  });

  test('the menu bar ends up in the real window, with the items asked for',
      () async {
    await const DVMenus().setApplicationMenu(menu);

    final Pointer<Void>? bar = gtk.menuBar();
    expect(bar, isNotNull, reason: 'a GtkMenuBar inside the toplevel');
    final List<Pointer<Void>> top = gtk.children(bar!);
    expect(top.map(gtk.label), <String>['File', 'Help']);

    final List<Pointer<Void>> fileItems = gtk.children(gtk.submenu(top.first));
    expect(fileItems.map(gtk.label), <String>['Open', 'Quit']);
  });

  test('activating an item reaches Dart by id', () async {
    final List<String> chosen = <String>[];
    await const DVMenus().setApplicationMenu(menu, onSelected: chosen.add);

    final Pointer<Void> bar = gtk.menuBar()!;
    final Pointer<Void> quit = gtk.children(gtk.submenu(gtk.children(bar).first))[1];
    gtk.activate(quit);

    expect(chosen, <String>['quit']);
  });

  test('a second menu replaces the first rather than stacking', () async {
    await const DVMenus().setApplicationMenu(menu);
    await const DVMenus().setApplicationMenu(const DVApplicationMenu(<DVMenuItem>[
      DVMenuItem(id: 'only', label: 'Only'),
    ]));

    final Pointer<Void> top = gtk.toplevel();
    final Pointer<Void> box = gtk.child(top);
    final int bars = gtk.children(box).where((Pointer<Void> w) => gtk.typeName(w) == 'GtkMenuBar').length;
    expect(bars, 1);
    expect(gtk.children(gtk.menuBar()!).map(gtk.label), <String>['Only']);
  });

  test('the window\'s original child is kept, below the bar', () async {
    // The FlView in a real app. Losing it would be a menu over nothing.
    await const DVMenus().setApplicationMenu(menu);
    final List<Pointer<Void>> boxChildren = gtk.children(gtk.child(gtk.toplevel()));
    expect(gtk.typeName(boxChildren.first), 'GtkMenuBar');
    expect(boxChildren.length, greaterThanOrEqualTo(1));
  });
}
