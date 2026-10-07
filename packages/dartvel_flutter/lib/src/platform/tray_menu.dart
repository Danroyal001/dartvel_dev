/// The tray menu as every binding reads it: one parse of what crossed the
/// bridge, numbered the same way on every desktop.
///
/// `DVTray.show` sends a tree of maps. macOS needs NSMenuItem tags,
/// Windows needs WM_COMMAND numbers and Linux needs the int32 ids
/// com.canonical.dbusmenu speaks, and three hand-written walks of the same
/// tree are three chances for a submenu item to dispatch the wrong id. So
/// the walk is here, once, and tested without a desktop.
library;

import 'dart:io';

/// What a node of the tray menu is.
enum DVTrayNodeKind {
  /// Something the user chooses, possibly with a check mark.
  item,

  /// A line between groups.
  separator,

  /// A label that is never chosen: a status line or a section title.
  header,

  /// An item that opens more items.
  submenu,
}

/// One entry of the tray menu, numbered.
class DVTrayNode {
  DVTrayNode({
    required this.number,
    required this.parent,
    required this.kind,
    required this.id,
    required this.label,
    required this.enabled,
    this.checked,
    this.radio = false,
    this.children = const <DVTrayNode>[],
  });

  /// 1-based, depth first: 0 is the root of the menu in dbusmenu's terms,
  /// so it is never an item's.
  final int number;

  /// The number of the submenu holding this node, 0 at the top level.
  final int parent;
  final DVTrayNodeKind kind;

  /// The application's id. Empty for a separator and usually a header.
  final String id;
  final String label;
  final bool enabled;

  /// Null where the item has no check mark at all.
  final bool? checked;

  /// Whether the mark is one of a group, drawn as a radio where the
  /// desktop draws one.
  final bool radio;
  final List<DVTrayNode> children;

  /// Whether choosing this node is something the application hears.
  bool get choosable => kind == .item && enabled && id.isNotEmpty;

  /// Parses the `menu` list `tray.show` carries. A malformed entry is
  /// skipped: this runs inside native callbacks, where a throw is a crash.
  static List<DVTrayNode> parse(List<Object?> menu) {
    int next = 0;
    List<DVTrayNode> walk(List<Object?> items, int parent) {
      final List<DVTrayNode> nodes = <DVTrayNode>[];
      for (final Object? raw in items) {
        if (raw is! Map) continue;
        final int number = ++next;
        final Object? childList = raw['children'];
        final String type = '${raw['type'] ?? ''}';
        final DVTrayNodeKind kind = switch (type) {
          'separator' => .separator,
          'header' => .header,
          _ when childList is List && childList.isNotEmpty => .submenu,
          _ => .item,
        };
        final Object? checked = raw['checked'];
        nodes.add(DVTrayNode(
          number: number,
          parent: parent,
          kind: kind,
          id: '${raw['id'] ?? ''}',
          label: '${raw['label'] ?? ''}',
          enabled: kind != .header && kind != .separator && raw['enabled'] != false,
          checked: checked is bool ? checked : null,
          radio: raw['radio'] == true,
          children: kind == .submenu ? walk(childList! as List<Object?>, number) : const <DVTrayNode>[],
        ));
      }
      return nodes;
    }

    return walk(menu, 0);
  }

  /// Every node by its number, submenus' children included.
  static Map<int, DVTrayNode> index(List<DVTrayNode> nodes) {
    final Map<int, DVTrayNode> byNumber = <int, DVTrayNode>{};
    void add(List<DVTrayNode> level) {
      for (final DVTrayNode node in level) {
        byNumber[node.number] = node;
        add(node.children);
      }
    }

    add(nodes);
    return byNumber;
  }
}

/// The file behind a tray icon's asset path, or null when there is none.
///
/// `DVTray.show` sends the generated asset's path, `assets/tray/on.png`,
/// and a status bar, a notification area and a StatusNotifierHost each load
/// a file. In a built application the file is under the bundle's
/// flutter_assets; in `flutter test` and `flutter run` it may be relative to
/// the working directory. [roots] overrides where to look, for a test.
String? dvTrayIconFile(String path, {List<String>? roots}) {
  if (path.isEmpty) return null;
  if (File(path).isAbsolute) return File(path).existsSync() ? path : null;
  for (final String root in roots ?? _flutterAssetRoots()) {
    final File candidate = File('$root/$path');
    if (candidate.existsSync()) return candidate.path;
  }
  return null;
}

List<String> _flutterAssetRoots() {
  final String executableDirectory = File(Platform.resolvedExecutable).parent.path;
  return <String>[
    // Linux and Windows bundles: data/flutter_assets beside the executable.
    '$executableDirectory/data/flutter_assets',
    // A macOS bundle: Contents/MacOS/<exe>, assets in App.framework.
    '$executableDirectory/../Frameworks/App.framework/Resources/flutter_assets',
    // flutter run / flutter test from the project directory.
    Directory.current.path,
  ];
}
