import 'dart:async';
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

    final styled = _applyStyle(node, built);
    return styled;
  }

  /// Folds a node's properties onto the widget as a [DVModifier].
  ///
  /// Every entry here is a control the builder's inspector can offer. A
  /// property the renderer ignores is one the inspector cannot meaningfully
  /// expose, so this list is the page builder's actual styling vocabulary.
  Widget _applyStyle(DVPageNode node, Widget built) {
    var modifier = const DVModifier();
    var modified = false;

    for (final property in dvStudioProperties) {
      final applied =
          property.apply(modifier, node.properties[property.name]);
      if (applied != null) {
        modifier = applied;
        modified = true;
      }
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

const Map<Object?, FontWeight> _fontWeights = <Object?, FontWeight>{
  'thin': FontWeight.w100,
  'light': FontWeight.w300,
  'normal': FontWeight.w400,
  'regular': FontWeight.w400,
  'medium': FontWeight.w500,
  'semibold': FontWeight.w600,
  'bold': FontWeight.w700,
  'black': FontWeight.w900,
};

const Map<Object?, AlignmentGeometry> _alignments = <Object?, AlignmentGeometry>{
  'topLeft': Alignment.topLeft,
  'topCenter': Alignment.topCenter,
  'topRight': Alignment.topRight,
  'centerLeft': Alignment.centerLeft,
  'center': Alignment.center,
  'centerRight': Alignment.centerRight,
  'bottomLeft': Alignment.bottomLeft,
  'bottomCenter': Alignment.bottomCenter,
  'bottomRight': Alignment.bottomRight,
};

/// Reads a colour from a document property.
///
/// A document is JSON, so a colour arrives either as the `0xAARRGGBB` integer
/// the `@DVPage` annotation already uses, or as the `#RRGGBB` string a web
/// editor's colour input produces. Both are accepted; anything else is ignored
/// rather than guessed at, so a typo renders unstyled instead of black.
Color? parseDocumentColor(Object? value) {
  if (value is int) return Color(value);
  if (value is! String) return null;
  var text = value.trim();
  if (text.startsWith('#')) text = text.substring(1);
  if (text.startsWith('0x') || text.startsWith('0X')) text = text.substring(2);
  if (text.length == 6) text = 'FF$text';
  if (text.length != 8) return null;
  final parsed = int.tryParse(text, radix: 16);
  return parsed == null ? null : Color(parsed);
}

/// How a document property is edited and applied.
///
/// Renderer and inspector both read this list, so a property cannot be
/// applied but uneditable, or offered but ignored — which is exactly what had
/// happened: `padding` rendered while the inspector offered no control for it.
enum DVStudioPropertyKind { number, colour, choice, flag }

class DVStudioProperty {
  final String name;
  final DVStudioPropertyKind kind;

  /// Applies this property's [value] to [modifier]. Returns null when the
  /// value is missing or unusable, so a typo renders unstyled rather than
  /// guessed at.
  final DVModifier? Function(DVModifier modifier, Object? value) apply;

  /// The accepted values, for [DVStudioPropertyKind.choice].
  final List<String> choices;

  const DVStudioProperty(
    this.name,
    this.kind,
    this.apply, {
    this.choices = const <String>[],
  });
}

DVModifier? _number(
  DVModifier modifier,
  Object? value,
  DVModifier Function(DVModifier m, double v) apply,
) =>
    value is num ? apply(modifier, value.toDouble()) : null;

DVModifier? _colour(
  DVModifier modifier,
  Object? value,
  DVModifier Function(DVModifier m, Color v) apply,
) {
  final parsed = parseDocumentColor(value);
  return parsed == null ? null : apply(modifier, parsed);
}

/// Every styling control the page builder offers.
final List<DVStudioProperty> dvStudioProperties = <DVStudioProperty>[
  DVStudioProperty('fontSize', DVStudioPropertyKind.number,
      (m, v) => _number(m, v, (m, v) => m.fontSize(v))),
  DVStudioProperty('letterSpacing', DVStudioPropertyKind.number,
      (m, v) => _number(m, v, (m, v) => m.letterSpacing(v))),
  DVStudioProperty('padding', DVStudioPropertyKind.number,
      (m, v) => _number(m, v, (m, v) => m.padding(v))),
  DVStudioProperty('margin', DVStudioPropertyKind.number,
      (m, v) => _number(m, v, (m, v) => m.margin(v))),
  DVStudioProperty('width', DVStudioPropertyKind.number,
      (m, v) => _number(m, v, (m, v) => m.width(v))),
  DVStudioProperty('height', DVStudioPropertyKind.number,
      (m, v) => _number(m, v, (m, v) => m.height(v))),
  DVStudioProperty('rounded', DVStudioPropertyKind.number,
      (m, v) => _number(m, v, (m, v) => m.rounded(v))),
  DVStudioProperty('color', DVStudioPropertyKind.colour,
      (m, v) => _colour(m, v, (m, v) => m.color(v))),
  DVStudioProperty('backgroundColor', DVStudioPropertyKind.colour,
      (m, v) => _colour(m, v, (m, v) => m.backgroundColor(v))),
  DVStudioProperty(
    'fontWeight',
    DVStudioPropertyKind.choice,
    (m, v) {
      final weight = _fontWeights[v];
      return weight == null ? null : m.fontWeight(weight);
    },
    choices: _fontWeights.keys.cast<String>().toList(growable: false),
  ),
  DVStudioProperty(
    'align',
    DVStudioPropertyKind.choice,
    (m, v) {
      final alignment = _alignments[v];
      return alignment == null ? null : m.align(alignment);
    },
    choices: _alignments.keys.cast<String>().toList(growable: false),
  ),
  DVStudioProperty('card', DVStudioPropertyKind.flag,
      (m, v) => v == true ? m.card() : null),
];

/// Stores documents through `DV.Database`, WordPress-style: page content is
/// data, so saving is publishing.
class DVPageStore {
  static const String table = 'dartvel_pages';

  const DVPageStore();

  static final StreamController<String> _changes =
      StreamController<String>.broadcast();

  /// Routes whose stored document changed, as it changes.
  ///
  /// This is what makes "saving publishes" true for an app that is already
  /// running: a route showing a stored page reloads when its document is
  /// saved, instead of serving whatever it read when it was first opened.
  static Stream<String> get changes => _changes.stream;

  /// Documents already read, so an override resolves during navigation
  /// without a database round trip on every page.
  static final Map<String, DVPageDocument> _cache = <String, DVPageDocument>{};
  static bool _primed = false;
  static Future<void>? _priming;

  /// Whether [prime] has finished, so [cached] can be trusted for a route it
  /// reports nothing for.
  static bool get isPrimed => _primed;

  /// The override stored for [route], if it is already in memory.
  ///
  /// Synchronous by design: navigation cannot await a query without either
  /// stalling the transition or flashing the wrong page.
  static DVPageDocument? cached(String route) => _cache[route];

  /// Reads every stored document into memory.
  ///
  /// Called once at startup by the generated runtime. Concurrent callers
  /// share the one read.
  static Future<void> prime() {
    if (_primed) return Future<void>.value();
    return _priming ??= _prime().whenComplete(() => _priming = null);
  }

  static Future<void> _prime() async {
    // Read into a local map first. Clearing the cache up front would discard
    // documents saved while the read was in flight — and lose them entirely
    // if the read then failed.
    final loaded = <String, DVPageDocument>{};
    try {
      const store = DVPageStore();
      await store._initialize();
      final rows = await DV.Database.query('SELECT route, document FROM $table');
      for (final row in rows) {
        loaded[row['route']! as String] = DVPageDocument.fromJson(
          (jsonDecode(row['document']! as String) as Map)
              .cast<String, Object?>(),
        );
      }
    } catch (_) {
      // No database configured, or no table yet: there are no overrides,
      // which is a legitimate state rather than a failure. Compiled pages
      // serve as they always did.
      _primed = true;
      return;
    }
    // A save that landed during the read is newer than the read, so it wins.
    loaded.forEach((String route, DVPageDocument document) {
      _cache.putIfAbsent(route, () => document);
    });
    _primed = true;
  }

  /// Drops the in-memory cache and any read in flight. Intended for tests.
  static void resetCache() {
    _cache.clear();
    _primed = false;
    _priming = null;
  }

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
    _cache[document.route] = document;
    _changes.add(document.route);
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
    _cache.remove(route);
    _changes.add(route);
  }
}

/// Serves the Studio document for [route] when one exists, and [fallback]
/// otherwise.
///
/// Precedence is deliberate and is the point of the builder: a stored
/// document **overrides** the compiled `@DVPage`. A compiled page is the
/// fallback entrypoint an app ships with — the editor has to be able to
/// change it, or a shipped page could never be edited, only added to.
///
/// The store is read into memory once ([DVPageStore.prime]), so navigation
/// resolves an override synchronously. Before that read finishes the fallback
/// renders, which is why a cold start shows the compiled page rather than a
/// blank frame; the override applies as soon as it is known.
class DVStudioPageRoute extends StatefulWidget {
  final String route;

  /// The compiled page for this route, when there is one. Null for a route
  /// that exists only as a stored document.
  final Widget? fallback;

  /// Shown when neither a stored document nor a [fallback] claims the route.
  final Widget Function(String route)? notFound;

  const DVStudioPageRoute(
    this.route, {
    super.key,
    this.fallback,
    this.notFound,
  });

  @override
  State<DVStudioPageRoute> createState() => _DVStudioPageRouteState();
}

class _DVStudioPageRouteState extends State<DVStudioPageRoute> {
  DVPageDocument? _document;
  StreamSubscription<String>? _subscription;

  @override
  void initState() {
    super.initState();
    _adopt();
    if (!DVPageStore.isPrimed) {
      // Cold start: the fallback renders now and the override applies when
      // the read lands.
      unawaited(DVPageStore.prime().then((_) {
        if (mounted) setState(_adopt);
      }));
    }
    // Saving publishes: a running app must pick up an edit to the page it is
    // currently showing, not the copy it read when the route opened.
    _subscription = DVPageStore.changes.listen((String route) {
      if (route == widget.route && mounted) setState(_adopt);
    });
  }

  @override
  void didUpdateWidget(DVStudioPageRoute oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.route != widget.route) _adopt();
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _adopt() {
    _document = DVPageStore.cached(widget.route);
  }

  @override
  Widget build(BuildContext context) {
    final document = _document;
    if (document != null) return DVPageDocumentRenderer(document);
    final fallback = widget.fallback;
    if (fallback != null) return fallback;
    return widget.notFound?.call(widget.route) ??
        DVBox.list(<Widget>[
          const DVText('404'),
          DVText("No page at '${widget.route}'"),
        ]);
  }
}

/// A set of page documents shipped together — the unit an OTA patch carries.
///
/// Editor changes reach a *running* app through [DVPageStore.changes]. This
/// is how they reach an *installed* one: the bundle travels with a release or
/// patch, and applying it writes the documents into the store, at which point
/// the running app picks them up through the same change stream.
class DVPageBundle {
  /// The release this bundle belongs to, for provenance in logs and rollback.
  final String version;

  final List<DVPageDocument> pages;

  /// Routes whose documents this bundle removes, restoring their compiled
  /// pages. Without this an edit could be shipped but never withdrawn.
  final List<String> removedRoutes;

  const DVPageBundle({
    required this.version,
    this.pages = const <DVPageDocument>[],
    this.removedRoutes = const <String>[],
  });

  factory DVPageBundle.fromJson(Map<String, Object?> json) {
    final version = json['version'];
    if (version is! String || version.isEmpty) {
      throw ArgumentError.value(
        json,
        'json',
        'A page bundle needs a non-empty "version" so an applied bundle can '
            'be identified and rolled back.',
      );
    }
    return DVPageBundle(
      version: version,
      pages: <DVPageDocument>[
        for (final page in (json['pages'] as List?) ?? const <Object?>[])
          DVPageDocument.fromJson((page! as Map).cast<String, Object?>()),
      ],
      removedRoutes: <String>[
        for (final route
            in (json['removedRoutes'] as List?) ?? const <Object?>[])
          route! as String,
      ],
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'version': version,
        'pages': <Object?>[for (final page in pages) page.toJson()],
        if (removedRoutes.isNotEmpty) 'removedRoutes': removedRoutes,
      };

  String encode() => jsonEncode(toJson());

  static DVPageBundle decode(String source) =>
      DVPageBundle.fromJson((jsonDecode(source) as Map).cast<String, Object?>());
}

/// Applies page bundles delivered with a release or OTA patch.
class DVPageBundleInstaller {
  const DVPageBundleInstaller();

  static const String table = 'dartvel_page_bundles';

  Future<void> _initialize() async {
    await DV.Database.execute(
      'CREATE TABLE IF NOT EXISTS $table (version TEXT, applied_at TEXT)',
    );
  }

  /// Versions already applied, newest last.
  Future<List<String>> appliedVersions() async {
    await _initialize();
    final rows = await DV.Database.query(
      'SELECT version FROM $table ORDER BY applied_at',
    );
    return <String>[
      for (final row in rows) row['version']! as String,
    ];
  }

  /// Whether [version] has already been applied.
  Future<bool> isApplied(String version) async =>
      (await appliedVersions()).contains(version);

  /// Writes [bundle]'s documents into the store and records the version.
  ///
  /// Idempotent: applying the same version twice is a no-op, because an OTA
  /// patch can be delivered more than once and re-applying it would undo
  /// edits made since. Returns whether anything was written.
  Future<bool> apply(DVPageBundle bundle) async {
    await _initialize();
    if (await isApplied(bundle.version)) return false;

    const store = DVPageStore();
    for (final page in bundle.pages) {
      await store.save(page);
    }
    for (final route in bundle.removedRoutes) {
      await store.delete(route);
    }
    await DV.Database.execute(
      'INSERT INTO $table (version, applied_at) VALUES (?, ?)',
      <Object?>[bundle.version, DateTime.now().toIso8601String()],
    );
    return true;
  }

  /// Forgets that [version] was applied, so it can be applied again.
  ///
  /// This does not restore the documents the bundle replaced — a rollback
  /// ships the previous bundle rather than inverting this one, which is the
  /// only way to be sure what an app ends up with.
  Future<void> forget(String version) async {
    await _initialize();
    await DV.Database.execute(
      'DELETE FROM $table WHERE version = ?',
      <Object?>[version],
    );
  }
}
