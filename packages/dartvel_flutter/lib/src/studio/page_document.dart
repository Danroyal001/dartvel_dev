import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../../dartvel_flutter.dart';

/// One widget in a page document.
///
/// The builder edits these; the renderer instantiates them as the real
/// `DVBox`/`DVText`/`DVImageView` widgets — the document is a serialization of
/// the actual widget tree, not a canvas facsimile of it.
class DVPageNode {
  final String id;

  /// `box`, `text`, or `image`.
  final String type;

  /// For a box: `list`, `row`, `grid`, `stack`, or `single`.
  final String layout;

  /// Widget properties: `text`, `fontSize`, `padding`, `columns`, `src`,
  /// `alt` — whatever the type consumes.
  final Map<String, Object?> properties;

  /// A bound action, e.g. `{'type': 'navigate', 'to': '/pricing'}`.
  final Map<String, Object?>? action;

  final List<DVPageNode> children;

  DVPageNode({
    String? id,
    required this.type,
    this.layout = 'list',
    Map<String, Object?>? properties,
    this.action,
    List<DVPageNode>? children,
  })  : id = id ?? _newId(),
        properties = properties ?? <String, Object?>{},
        children = children ?? <DVPageNode>[];

  static int _counter = 0;

  static String _newId() =>
      'n${DateTime.now().microsecondsSinceEpoch}-${_counter++}';

  factory DVPageNode.text(String text) =>
      DVPageNode(type: 'text', properties: <String, Object?>{'text': text});

  factory DVPageNode.image(String src, {String? alt}) => DVPageNode(
        type: 'image',
        properties: <String, Object?>{'src': src, if (alt != null) 'alt': alt},
      );

  factory DVPageNode.box({String layout = 'list'}) =>
      DVPageNode(type: 'box', layout: layout);

  /// A copy with [name] set — what the property inspector applies.
  DVPageNode withProperty(String name, Object? value) => DVPageNode(
        id: id,
        type: type,
        layout: layout,
        properties: <String, Object?>{...properties, name: value},
        action: action,
        children: children,
      );

  /// A copy with the bound [action] — what the action editor applies.
  DVPageNode withAction(Map<String, Object?>? action) => DVPageNode(
        id: id,
        type: type,
        layout: layout,
        properties: properties,
        action: action,
        children: children,
      );

  factory DVPageNode.fromJson(Map<String, Object?> json) => DVPageNode(
        id: json['id'] as String?,
        type: json['type']! as String,
        layout: (json['layout'] as String?) ?? 'list',
        properties:
            (json['properties'] as Map?)?.cast<String, Object?>() ?? {},
        action: (json['action'] as Map?)?.cast<String, Object?>(),
        children: <DVPageNode>[
          for (final child in (json['children'] as List?) ?? const <Object?>[])
            DVPageNode.fromJson((child! as Map).cast<String, Object?>()),
        ],
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'type': type,
        'layout': layout,
        if (properties.isNotEmpty) 'properties': properties,
        if (action != null) 'action': action,
        if (children.isNotEmpty)
          'children': <Object?>[for (final c in children) c.toJson()],
      };
}

/// A builder-editable page: a route, a title, and a widget tree.
class DVPageDocument {
  final String route;
  String title;
  DVPageNode root;

  DVPageDocument({required this.route, this.title = '', DVPageNode? root})
      : root = root ?? DVPageNode.box();

  factory DVPageDocument.fromJson(Map<String, Object?> json) => DVPageDocument(
        route: json['route']! as String,
        title: (json['title'] as String?) ?? '',
        root: DVPageNode.fromJson(
          (json['root']! as Map).cast<String, Object?>(),
        ),
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'route': route,
        'title': title,
        'root': root.toJson(),
      };

  /// Full code export: the page as the same private expression-bodied
  /// `@DVPage` source a hand-written page uses. Once exported, the builder is
  /// out of the loop — the page is ordinary code.
  String toDartSource() {
    final name = _pageFunctionName();
    final buffer = StringBuffer()
      ..writeln("import 'package:flutter/widgets.dart';")
      ..writeln()
      ..writeln("import '../dartvel_client/dartvel_client.dart';")
      ..writeln()
      ..writeln('// Exported from Dartvel Studio. Ordinary page source: edit')
      ..writeln('// freely, the builder is no longer involved.')
      ..writeln("@DVPage(title: '${_escape(title)}')")
      ..writeln("@pragma('vm:entry-point')")
      ..writeln('Widget _$name(BuildContext context) =>')
      ..writeln('    ${_nodeSource(root, 2)};');
    return buffer.toString();
  }

  String _pageFunctionName() {
    final parts = route
        .split('/')
        .where((String s) => s.isNotEmpty)
        .map((String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9]'), ''))
        .where((String s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'indexPage';
    final buffer = StringBuffer(parts.first);
    for (final part in parts.skip(1)) {
      buffer
        ..write(part[0].toUpperCase())
        ..write(part.substring(1));
    }
    return '${buffer}Page';
  }

  static String _escape(String value) =>
      value.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

  String _nodeSource(DVPageNode node, int depth) {
    final pad = '  ' * depth;
    String core;
    switch (node.type) {
      case 'text':
        // const-receiver: valid even under a .modifier(...) call.
        core = "const DVText('${_escape('${node.properties['text'] ?? ''}')}')";
      case 'image':
        core =
            "const DVImageView(DVImage.network('${_escape('${node.properties['src'] ?? ''}')}'"
            "${node.properties['alt'] != null ? ", alt: '${_escape('${node.properties['alt']}')}'" : ''}))";
      default:
        final children = node.children
            .map((DVPageNode c) => '\n$pad  ${_nodeSource(c, depth + 1)},')
            .join();
        final childList = children.isEmpty ? '[]' : '[$children\n$pad]';
        core = switch (node.layout) {
          'row' => 'DVBox.row($childList)',
          'grid' =>
            'DVBox.grid($childList, columns: ${node.properties['columns'] ?? 2})',
          'stack' => 'DVBox.stack($childList)',
          'single' => node.children.isEmpty
              ? 'DVBox(const SizedBox.shrink())'
              : 'DVBox(${_nodeSource(node.children.first, depth + 1)})',
          _ => 'DVBox.list($childList)',
        };
    }

    // Actions ride the modifier chain: `.onPressed` lives on DVModifier, not
    // on every widget, which a compile of exported output proved.
    final modifiers = _modifierSource(node);
    if (modifiers.isNotEmpty) core = '$core.modifier($modifiers)';
    return core;
  }

  String _modifierSource(DVPageNode node) {
    var source = 'const DVModifier()';
    var any = false;
    final action = node.action;
    if (action != null && action['type'] == 'navigate') {
      source =
          "$source.onPressed(DV.Navigation.to(const DVRouteTarget('${_escape('${action['to']}')}')))";
      any = true;
    }
    final fontSize = node.properties['fontSize'];
    if (fontSize is num) {
      source = '$source.fontSize(${fontSize.toDouble()})';
      any = true;
    }
    final padding = node.properties['padding'];
    if (padding is num) {
      source = '$source.padding(${padding.toDouble()})';
      any = true;
    }
    return any ? source : '';
  }
}

/// The operations a drag-and-drop surface calls. UI gestures reduce to these
/// four; everything else in the builder is chrome around them.
class DVPageDocumentEditor {
  final DVPageDocument document;

  DVPageDocumentEditor(this.document);

  DVPageNode? _findIn(DVPageNode node, String id) {
    if (node.id == id) return node;
    for (final child in node.children) {
      final found = _findIn(child, id);
      if (found != null) return found;
    }
    return null;
  }

  DVPageNode? find(String id) => _findIn(document.root, id);

  DVPageNode? _parentOf(DVPageNode node, String id) {
    for (final child in node.children) {
      if (child.id == id) return node;
      final found = _parentOf(child, id);
      if (found != null) return found;
    }
    return null;
  }

  /// Inserts [node] under [parent], at [index] or the end. This is a drop.
  void insert(DVPageNode node, {required String parent, int? index}) {
    final target = find(parent);
    if (target == null) {
      throw ArgumentError.value(parent, 'parent', 'No such node.');
    }
    target.children.insert(
      index == null || index > target.children.length
          ? target.children.length
          : index,
      node,
    );
  }

  /// Removes the node. This is a delete.
  DVPageNode remove(String id) {
    final parent = _parentOf(document.root, id);
    if (parent == null) {
      throw ArgumentError.value(id, 'id', 'No such node, or it is the root.');
    }
    final node = parent.children.firstWhere((DVPageNode c) => c.id == id);
    parent.children.remove(node);
    return node;
  }

  /// Reparents the node. This is a drag between containers.
  void move(String id, {required String parent, int? index}) {
    final moving = find(id);
    final target = find(parent);
    if (moving == null || target == null) {
      throw ArgumentError('No such node.');
    }
    // Dropping a container into its own subtree would orphan the tree.
    if (_findIn(moving, parent) != null) {
      throw ArgumentError(
        'Cannot move a node into its own subtree.',
      );
    }
    remove(id);
    insert(moving, parent: parent, index: index);
  }

  /// Replaces the node with [transform]'s result. This is the inspector.
  void update(String id, DVPageNode Function(DVPageNode node) transform) {
    if (document.root.id == id) {
      document.root = transform(document.root);
      return;
    }
    final parent = _parentOf(document.root, id);
    if (parent == null) {
      throw ArgumentError.value(id, 'id', 'No such node.');
    }
    final index =
        parent.children.indexWhere((DVPageNode c) => c.id == id);
    parent.children[index] = transform(parent.children[index]);
  }
}

/// Renders a document as the real widgets it describes.
///
/// Used identically by the running app (published pages) and the editing
/// surface — what is edited is what ships.
class DVPageDocumentRenderer extends StatelessWidget {
  final DVPageDocument document;

  const DVPageDocumentRenderer(this.document, {super.key});

  @override
  Widget build(BuildContext context) => _build(document.root);

  Widget _build(DVPageNode node) {
    Widget built;
    switch (node.type) {
      case 'text':
        built = DVText('${node.properties['text'] ?? ''}');
      case 'image':
        built = DVImageView(
          DVImage.network(
            '${node.properties['src'] ?? ''}',
            alt: node.properties['alt'] as String?,
          ),
        );
      default:
        final children =
            node.children.map(_build).toList(growable: false);
        built = switch (node.layout) {
          'row' => DVBox.row(children),
          'grid' => DVBox.grid(
              children,
              columns: (node.properties['columns'] as num?)?.toInt() ?? 2,
            ),
          'stack' => DVBox.stack(children),
          'single' => children.isEmpty
              ? const DVBox(SizedBox.shrink())
              : DVBox(children.first),
          _ => DVBox.list(children),
        };
    }

    var modifier = const DVModifier();
    var modified = false;
    final fontSize = node.properties['fontSize'];
    if (fontSize is num) {
      modifier = modifier.fontSize(fontSize.toDouble());
      modified = true;
    }
    final padding = node.properties['padding'];
    if (padding is num) {
      modifier = modifier.padding(padding.toDouble());
      modified = true;
    }

    final action = node.action;
    if (action != null && action['type'] == 'navigate') {
      modifier = modifier.onPressed(
        DV.Navigation.to(DVRouteTarget('${action['to']}')),
      );
      modified = true;
    }

    if (!modified) return built;
    if (built is DVText) return built.modifier(modifier);
    if (built is DVBox) return built.modifier(modifier);
    return DVBox(built).modifier(modifier);
  }
}

/// Stores documents through `DV.Database`, WordPress-style: page content is
/// data, so saving is publishing.
class DVPageStore {
  static const String table = 'dartvel_pages';

  const DVPageStore();

  Future<void> _initialize() async {
    await DV.Database.execute(
      'CREATE TABLE IF NOT EXISTS $table (route TEXT, title TEXT, '
      'document TEXT)',
    );
  }

  /// Upserts by route and publishes the change to watchers.
  Future<void> save(DVPageDocument document) async {
    await _initialize();
    await DV.Database.execute(
      'DELETE FROM $table WHERE route = ?',
      <Object?>[document.route],
    );
    await DV.Database.execute(
      'INSERT INTO $table (route, title, document) VALUES (?, ?, ?)',
      <Object?>[document.route, document.title, jsonEncode(document.toJson())],
    );
  }

  Future<DVPageDocument?> load(String route) async {
    await _initialize();
    final rows = await DV.Database.query(
      'SELECT document FROM $table WHERE route = ?',
      <Object?>[route],
    );
    if (rows.isEmpty) return null;
    return DVPageDocument.fromJson(
      (jsonDecode(rows.first['document']! as String) as Map)
          .cast<String, Object?>(),
    );
  }

  Future<List<String>> routes() async {
    await _initialize();
    final rows = await DV.Database.query('SELECT route FROM $table');
    return rows
        .map((Map<String, Object?> row) => row['route']! as String)
        .toList(growable: false)
      ..sort();
  }

  Future<void> delete(String route) async {
    await _initialize();
    await DV.Database.execute(
      'DELETE FROM $table WHERE route = ?',
      <Object?>[route],
    );
  }
}
