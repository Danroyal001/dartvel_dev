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

  /// Per-breakpoint overrides of [properties], keyed by [DVBreakpoint] name.
  ///
  /// Mobile-first, like every responsive system people already know: the
  /// base properties are the phone, and an override at a breakpoint applies
  /// from that width up until a wider breakpoint overrides it again. Empty
  /// for most nodes, and written to JSON only when it is not.
  final Map<String, Map<String, Object?>> breakpoints;

  final List<DVPageNode> children;

  DVPageNode({
    String? id,
    required this.type,
    this.layout = 'list',
    Map<String, Object?>? properties,
    this.action,
    Map<String, Map<String, Object?>>? breakpoints,
    List<DVPageNode>? children,
  })  : id = id ?? _newId(),
        properties = properties ?? <String, Object?>{},
        breakpoints = breakpoints ?? <String, Map<String, Object?>>{},
        children = children ?? <DVPageNode>[];

  /// The widths, narrowest first, that [propertiesFor] cascades through.
  static const List<DVBreakpoint> _cascade = <DVBreakpoint>[
    DVBreakpoint.mobile,
    DVBreakpoint.tablet,
    DVBreakpoint.desktop,
    DVBreakpoint.wide,
  ];

  /// The properties in effect at [breakpoint]: the base, then every override
  /// from the narrowest breakpoint up to and including this one.
  Map<String, Object?> propertiesFor(DVBreakpoint breakpoint) {
    if (breakpoints.isEmpty) return properties;
    final Map<String, Object?> effective = <String, Object?>{...properties};
    for (final DVBreakpoint step in _cascade) {
      final Map<String, Object?>? overrides = breakpoints[step.name];
      if (overrides != null) effective.addAll(overrides);
      if (step == breakpoint) break;
    }
    return effective;
  }

  /// A copy with [name] overridden at [breakpoint], or the override removed
  /// when [value] is null. A breakpoint left with no overrides is dropped.
  DVPageNode withBreakpointProperty(
    DVBreakpoint breakpoint,
    String name,
    Object? value,
  ) {
    final Map<String, Map<String, Object?>> next =
        <String, Map<String, Object?>>{
      for (final MapEntry<String, Map<String, Object?>> e in breakpoints.entries)
        e.key: <String, Object?>{...e.value},
    };
    final Map<String, Object?> at =
        next.putIfAbsent(breakpoint.name, () => <String, Object?>{});
    if (value == null) {
      at.remove(name);
    } else {
      at[name] = value;
    }
    if (at.isEmpty) next.remove(breakpoint.name);
    return DVPageNode(
      id: id,
      type: type,
      layout: layout,
      properties: properties,
      action: action,
      breakpoints: next,
      children: children,
    );
  }

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
        breakpoints: breakpoints,
        children: children,
      );

  /// A copy with a different node [type], for palette factories that build on
  /// an existing shape.
  DVPageNode withType(String type) => DVPageNode(
        id: id,
        type: type,
        layout: layout,
        properties: properties,
        action: action,
        breakpoints: breakpoints,
        children: children,
      );

  /// A copy with the bound [action] — what the action editor applies.
  DVPageNode withAction(Map<String, Object?>? action) => DVPageNode(
        id: id,
        type: type,
        layout: layout,
        properties: properties,
        action: action,
        breakpoints: breakpoints,
        children: children,
      );

  factory DVPageNode.fromJson(Map<String, Object?> json) => DVPageNode(
        id: json['id'] as String?,
        type: json['type']! as String,
        layout: (json['layout'] as String?) ?? 'list',
        properties:
            (json['properties'] as Map?)?.cast<String, Object?>() ?? {},
        action: (json['action'] as Map?)?.cast<String, Object?>(),
        breakpoints: <String, Map<String, Object?>>{
          if (json['breakpoints'] is Map)
            for (final MapEntry<Object?, Object?> e
                in (json['breakpoints'] as Map).entries)
              if (e.value is Map)
                '${e.key}': (e.value as Map).cast<String, Object?>(),
        },
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
        if (breakpoints.isNotEmpty) 'breakpoints': breakpoints,
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

  /// The spacing and alignment arguments an exported box carries.
  ///
  /// Only what the document actually says. An export that wrote every
  /// default out would turn a page nobody had styled into source full of
  /// decisions nobody made.
  String _layoutArgumentSource(Map<String, Object?> properties) {
    final StringBuffer out = StringBuffer();
    final Object? spacing = properties['spacing'];
    if (spacing is num) out.write(', spacing: ${_tidySource(spacing)}');
    final Object? main = properties['mainAxis'];
    if (main is String && dvStudioAlignNames.contains(main)) {
      out.write(', align: DVAlign.$main');
    }
    final Object? cross = properties['crossAxis'];
    if (cross is String && dvStudioCrossAlignNames.contains(cross)) {
      out.write(', crossAlign: DVCrossAlign.$cross');
    }
    return out.toString();
  }

  /// Just the spacing, for the constructors that take no alignment.
  String _spacingArgumentSource(Map<String, Object?> properties) {
    final Object? spacing = properties['spacing'];
    return spacing is num ? ', spacing: ${_tidySource(spacing)}' : '';
  }

  static String _tidySource(num value) =>
      value == value.roundToDouble() ? '${value.toInt()}' : '$value';

  String _nodeSource(DVPageNode node, int depth) {
    final pad = '  ' * depth;
    String core;
    final leaf = dvStudioLeafTypeFor(node);
    if (leaf != null) {
      // const-receiver where possible: valid even under a .modifier(...) call.
      core = leaf.source(node, _escape);
    } else {
        final children = node.children
            .map((DVPageNode c) => '\n$pad  ${_nodeSource(c, depth + 1)},')
            .join();
        final childList = children.isEmpty ? '[]' : '[$children\n$pad]';
        final String layoutArgs = _layoutArgumentSource(node.properties);
        final bool scrolls = node.properties['scroll'] == true;
        core = switch (node.layout) {
          'row' when scrolls =>
            'DVBox.horizontalScrollable($childList${_spacingArgumentSource(node.properties)})',
          'row' => 'DVBox.row($childList$layoutArgs)',
          'grid' =>
            'DVBox.grid($childList, columns: ${node.properties['columns'] ?? 2})',
          'stack' => 'DVBox.stack($childList)',
          'single' => node.children.isEmpty
              ? 'DVBox(const SizedBox.shrink())'
              : 'DVBox(${_nodeSource(node.children.first, depth + 1)})',
          _ => scrolls
              ? 'DVBox.list($childList$layoutArgs).scrollable()'
              : 'DVBox.list($childList$layoutArgs)',
        };
    }

    // Actions ride the modifier chain: `.onPressed` lives on DVModifier, not
    // on every widget, which a compile of exported output proved.
    if (node.breakpoints.isEmpty) {
      final modifiers = _modifierSource(node, node.properties);
      if (modifiers.isNotEmpty) core = '$core.modifier($modifiers)';
      return core;
    }

    // Overrides exist, so the export switches on the breakpoint the way a
    // hand-written page would, rather than flattening to one width. The
    // Builder is what gives the switch a context to read the screen from.
    final buffer = StringBuffer()
      ..writeln('Builder(builder: (BuildContext context) =>')
      ..writeln('$pad    switch (context.screen.breakpoint) {');
    for (final DVBreakpoint step in DVPageNode._cascade) {
      final modifiers = _modifierSource(node, node.propertiesFor(step));
      final widget = modifiers.isEmpty ? core : '$core.modifier($modifiers)';
      buffer.writeln('$pad      DVBreakpoint.${step.name} => $widget,');
    }
    buffer.write('$pad    })');
    return buffer.toString();
  }

  String _modifierSource(DVPageNode node, Map<String, Object?> properties) {
    var source = 'const DVModifier()';
    var any = false;
    final action = node.action;
    if (action != null && action['type'] == 'navigate') {
      source =
          "$source.onPressed(DV.Navigation.to(const DVRouteTarget('${_escape('${action['to']}')}')))";
      any = true;
    }
    // Every style, from the table the renderer applies. Written out here as
    // two of them were, an export drops whatever nobody remembered to add.
    for (final DVStudioProperty property in dvStudioProperties) {
      final String? call =
          property.source(properties[property.name], properties);
      if (call == null) continue;
      source = '$source$call';
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
  Widget build(BuildContext context) =>
      _build(document.root, context.screen.breakpoint);

  Widget _build(DVPageNode raw, DVBreakpoint breakpoint) {
    // The node as it is at this width: the base properties with every
    // override up to this breakpoint applied. Resolved once here, so the
    // layout and the modifiers below read the same values.
    final DVPageNode node = raw.breakpoints.isEmpty
        ? raw
        : DVPageNode(
            id: raw.id,
            type: raw.type,
            layout: raw.layout,
            properties: raw.propertiesFor(breakpoint),
            action: raw.action,
            children: raw.children,
          );
    Widget built;
    final leaf = dvStudioLeafTypeFor(node);
    if (leaf != null) {
      built = leaf.build(node);
    } else {
        final children = node.children
            .map((DVPageNode c) => _build(c, breakpoint))
            .toList(growable: false);
        // How the children sit together, which a box could describe and not
        // render: every list and row came out with the framework's default
        // gap, packed to the start and stretched across, whatever the
        // document said.
        final double spacing = dvStudioSpacingOf(node.properties);
        final DVAlign main = dvStudioAlignOf(node.properties['mainAxis']);
        final DVCrossAlign cross =
            dvStudioCrossAlignOf(node.properties['crossAxis']);
        // Whether the box scrolls its own axis. Almost every screen in a
        // design is taller than the device, and a document that could not
        // say so rendered the overflow stripe on the first screen.
        final bool scrolls = node.properties['scroll'] == true;
        built = switch (node.layout) {
          'row' when scrolls =>
            DVBox.horizontalScrollable(children, spacing: spacing),
          'row' => DVBox.row(children,
              spacing: spacing, align: main, crossAlign: cross),
          'grid' => DVBox.grid(
              children,
              columns: (node.properties['columns'] as num?)?.toInt() ?? 2,
            ),
          'stack' => DVBox.stack(children),
          'single' => children.isEmpty
              ? const DVBox(SizedBox.shrink())
              : DVBox(children.first),
          _ => scrolls
              ? DVBox.list(children,
                      spacing: spacing, align: main, crossAlign: cross)
                  .scrollable()
              : DVBox.list(children,
                  spacing: spacing, align: main, crossAlign: cross),
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
      final applied = property.apply(
        modifier,
        node.properties[property.name],
        node.properties,
      );
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


/// A leaf node type the page builder can place.
///
/// Renderer, Dart exporter and palette all read [dvStudioLeafTypes], for the
/// same reason the styling controls share one list: a type handled in the
/// renderer but not the exporter produces a page that previews correctly and
/// exports to code that will not compile.
class DVStudioLeafType {
  final String type;

  /// Palette label.
  final String label;

  /// A new node of this type, as dropped from the palette.
  final DVPageNode Function() create;

  /// Renders the node. Styling and actions are applied by the caller.
  final Widget Function(DVPageNode node) build;

  /// The node as Dart source, for `toDartSource`.
  final String Function(DVPageNode node, String Function(String) escape) source;

  const DVStudioLeafType({
    required this.type,
    required this.label,
    required this.create,
    required this.build,
    required this.source,
  });
}

double _size(DVPageNode node, String name, double fallback) {
  final value = node.properties[name];
  return value is num ? value.toDouble() : fallback;
}

final List<DVStudioLeafType> dvStudioLeafTypes = <DVStudioLeafType>[
  DVStudioLeafType(
    type: 'text',
    label: 'Text',
    create: () => DVPageNode.text('Text'),
    build: (node) => DVText('${node.properties['text'] ?? ''}'),
    source: (node, escape) =>
        "const DVText('${escape('${node.properties['text'] ?? ''}')}')",
  ),
  DVStudioLeafType(
    type: 'image',
    label: 'Image',
    create: () => DVPageNode.image('https://example.com/image.png'),
    // Where the image comes from is the node's to say. It could only ever be
    // a URL, which left assets, files and stored bytes unreachable from a
    // page -- and an imported design permanently dependent on somebody
    // else's address staying up. Read through DVImage's own reader, so a
    // page and a model field cannot disagree about what a source name means.
    build: (node) => DVImageView(dvStudioImageOf(node.properties)),
    source: (node, escape) {
      final DVImage image = dvStudioImageOf(node.properties);
      final String alt = image.alt == null
          ? ''
          : ", alt: '${escape('${image.alt}')}'";
      return 'const DVImageView(DVImage.${image.source.name}'
          "('${escape(image.reference)}'$alt))";
    },
  ),
  // A button is a text node that announces itself as one. The tap itself is
  // the node's action, the same mechanism any node uses, so this adds the
  // semantics and the tap target rather than a second way to handle presses.
  DVStudioLeafType(
    type: 'button',
    label: 'Button',
    create: () => DVPageNode.text('Button').withType('button'),
    build: (node) => DVText('${node.properties['text'] ?? ''}').modifier(
      const DVModifier().semanticButton().minimumTapTarget(),
    ),
    source: (node, escape) =>
        "DVText('${escape('${node.properties['text'] ?? ''}')}')"
        '.modifier(const DVModifier().semanticButton().minimumTapTarget())',
  ),
  DVStudioLeafType(
    type: 'spacer',
    label: 'Spacer',
    create: () => DVPageNode.text('').withType('spacer').withProperty('size', 16),
    build: (node) => SizedBox(height: _size(node, 'size', 16)),
    source: (node, escape) =>
        'const SizedBox(height: ${_size(node, 'size', 16)})',
  ),
  DVStudioLeafType(
    type: 'divider',
    label: 'Divider',
    create: () =>
        DVPageNode.text('').withType('divider').withProperty('thickness', 1),
    build: (node) => SizedBox(
      height: _size(node, 'thickness', 1),
      child: const ColoredBox(color: Color(0x33000000)),
    ),
    source: (node, escape) =>
        'const SizedBox(height: ${_size(node, 'thickness', 1)}, '
        'child: ColoredBox(color: Color(0x33000000)))',
  ),
];

/// The leaf type [node] declares, or null when it is a layout box.
DVStudioLeafType? dvStudioLeafTypeFor(DVPageNode node) {
  for (final leaf in dvStudioLeafTypes) {
    if (leaf.type == node.type) return leaf;
  }
  return null;
}

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
/// What kind of value a property takes, which is what the inspector offers
/// and how a typed value is read back.
enum DVStudioPropertyKind { number, colour, choice, flag, text }

class DVStudioProperty {
  final String name;
  final DVStudioPropertyKind kind;

  /// Applies this property's [value] to [modifier]. Returns null when the
  /// value is missing or unusable, so a typo renders unstyled rather than
  /// guessed at.
  ///
  /// The node's whole property map comes too, because some styles are one
  /// decision made of two values: a border's colour and its width apply
  /// through one call, and applied separately whichever ran last would hold
  /// a default for the other.
  final DVModifier? Function(
    DVModifier modifier,
    Object? value,
    Map<String, Object?> properties,
  ) apply;

  /// The modifier call an export writes for [value], or null when there is
  /// nothing to write.
  ///
  /// Here rather than in the exporter so a style cannot be rendered and not
  /// exported. That had already happened: the export wrote two of the twelve
  /// styles the renderer applied, so a page left the builder as an unstyled
  /// skeleton that compiled.
  final String? Function(Object? value, Map<String, Object?> properties)
      source;

  /// The accepted values, for [DVStudioPropertyKind.choice].
  final List<String> choices;

  /// The property this one is part of, when a style is one decision made of
  /// two values.
  ///
  /// `borderWidth` is `borderColor`'s: the two apply through one call and are
  /// exported once, by the one they belong to. Named here rather than left
  /// implicit so that "every style the renderer applies is exported" can be
  /// checked without a special case written into the check.
  final String? companionOf;

  const DVStudioProperty(
    this.name,
    this.kind,
    this.apply, {
    required this.source,
    this.choices = const <String>[],
    this.companionOf,
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
      (m, v, p) => _number(m, v, (m, v) => m.fontSize(v)),
      source: (v, p) => _numberSource('fontSize', v)),
  DVStudioProperty('letterSpacing', DVStudioPropertyKind.number,
      (m, v, p) => _number(m, v, (m, v) => m.letterSpacing(v)),
      source: (v, p) => _numberSource('letterSpacing', v)),
  // The two a designer sets on nearly every text layer and the document had
  // nowhere to put: an import wrote the family and nothing read it, so every
  // screen came out in the default font, and paragraphs came out at the
  // font's own leading rather than the design's.
  DVStudioProperty('fontFamily', DVStudioPropertyKind.text,
      (m, v, p) => v is String && v.isNotEmpty ? m.fontFamily(v) : null,
      source: (v, p) =>
          v is String && v.isNotEmpty ? ".fontFamily('${_escapeSource(v)}')" : null),
  DVStudioProperty('lineHeight', DVStudioPropertyKind.number,
      (m, v, p) => _number(m, v, (m, v) => m.lineHeight(v)),
      source: (v, p) => _numberSource('lineHeight', v)),
  DVStudioProperty('padding', DVStudioPropertyKind.number,
      (m, v, p) => _padding(m, p),
      source: (v, p) => _hasEdgePadding(p) ? null : _numberSource('padding', v)),
  // Four sides, because a design almost never has one number: 24 across
  // against 8 down is the shape of a card, and a document that could say
  // only one of them left the import to keep the largest.
  //
  // Each side applies the whole EdgeInsets rather than its own edge: a
  // modifier replaces the padding it is given, so four modifiers would leave
  // only the last one applied.
  for (final String side in _paddingEdges)
    DVStudioProperty(side, DVStudioPropertyKind.number,
        (m, v, p) => _padding(m, p),
        source: (v, p) => _paddingEdgeSource(side, p)),
  DVStudioProperty('margin', DVStudioPropertyKind.number,
      (m, v, p) => _number(m, v, (m, v) => m.margin(v)),
      source: (v, p) => _numberSource('margin', v)),
  DVStudioProperty('width', DVStudioPropertyKind.number,
      (m, v, p) => _number(m, v, (m, v) => m.width(v)),
      source: (v, p) => _numberSource('width', v)),
  DVStudioProperty('height', DVStudioPropertyKind.number,
      (m, v, p) => _number(m, v, (m, v) => m.height(v)),
      source: (v, p) => _numberSource('height', v)),
  DVStudioProperty('rounded', DVStudioPropertyKind.number,
      (m, v, p) => _number(m, v, (m, v) => m.rounded(v)),
      source: (v, p) => _numberSource('rounded', v)),
  // A shadow is one decision made of five values, so the colour owns it and
  // the rest are its companions: applied separately, whichever ran last
  // would hold defaults for the other four.
  DVStudioProperty(
    'shadowColor',
    DVStudioPropertyKind.colour,
    (m, v, p) {
      final List<BoxShadow>? shadow = _shadowOf(v, p);
      return shadow == null ? null : m.shadow(shadow);
    },
    source: (v, p) {
      final List<BoxShadow>? shadow = _shadowOf(v, p);
      if (shadow == null) return null;
      final BoxShadow cast = shadow.single;
      return '.shadow(<BoxShadow>[BoxShadow(color: '
          'Color(0x${_hex(cast.color)}), '
          'offset: Offset(${cast.offset.dx}, ${cast.offset.dy}), '
          'blurRadius: ${cast.blurRadius}, '
          'spreadRadius: ${cast.spreadRadius})])';
    },
  ),
  // Declared so the inspector offers each one, and exported by the colour.
  for (final String part in _shadowParts)
    DVStudioProperty(
      part,
      DVStudioPropertyKind.number,
      (m, v, p) {
        final List<BoxShadow>? shadow = _shadowOf(p['shadowColor'], p);
        return shadow == null ? null : m.shadow(shadow);
      },
      source: (v, p) => null,
      companionOf: 'shadowColor',
    ),
  DVStudioProperty('color', DVStudioPropertyKind.colour,
      (m, v, p) => _colour(m, v, (m, v) => m.color(v)),
      source: (v, p) => _colourSource('color', v)),
  DVStudioProperty('backgroundColor', DVStudioPropertyKind.colour,
      (m, v, p) => _colour(m, v, (m, v) => m.backgroundColor(v)),
      source: (v, p) => _colourSource('backgroundColor', v)),
  DVStudioProperty(
    'fontWeight',
    DVStudioPropertyKind.choice,
    (m, v, p) {
      final weight = _fontWeights[v];
      return weight == null ? null : m.fontWeight(weight);
    },
    choices: _fontWeights.keys.cast<String>().toList(growable: false),
    source: (v, p) =>
        _fontWeights.containsKey(v) ? '.fontWeight(FontWeight.$v)' : null,
  ),
  DVStudioProperty(
    'align',
    DVStudioPropertyKind.choice,
    (m, v, p) {
      final alignment = _alignments[v];
      return alignment == null ? null : m.align(alignment);
    },
    choices: _alignments.keys.cast<String>().toList(growable: false),
    source: (v, p) =>
        _alignments.containsKey(v) ? '.align(Alignment.$v)' : null,
  ),
  // A border is two values making one decision, which is why apply is given
  // the whole property map. A width with no colour is a border nobody can
  // see, and applying the colour and the width as two independent modifiers
  // would leave whichever ran last holding a default for the other.
  DVStudioProperty(
    'borderColor',
    DVStudioPropertyKind.colour,
    (m, v, p) {
      final colour = parseDocumentColor(v);
      if (colour == null) return null;
      return m.border(Border.all(color: colour, width: _borderWidthOf(p)));
    },
    source: (v, p) {
      final colour = parseDocumentColor(v);
      if (colour == null) return null;
      return '.border(Border.all(color: Color(0x${_hex(colour)}), '
          'width: ${_borderWidthOf(p)}))';
    },
  ),
  // Declared so the inspector offers it and the table stays the one place a
  // style is defined. The colour above draws it: a width alone is a border
  // nobody chose a colour for, and choosing one would put a line in the
  // design that nobody asked for.
  DVStudioProperty(
    'borderWidth',
    DVStudioPropertyKind.number,
    (m, v, p) {
      final colour = parseDocumentColor(p['borderColor']);
      if (colour == null || v is! num) return null;
      return m.border(Border.all(color: colour, width: v.toDouble()));
    },
    source: (v, p) => null,
    companionOf: 'borderColor',
  ),
  DVStudioProperty(
    'opacity',
    DVStudioPropertyKind.number,
    (m, v, p) {
      // Flutter asserts on anything outside 0..1, and a document can carry
      // any number at all: a page that will not render because of one value
      // is worse than one drawn at full strength.
      if (v is! num || v < 0 || v > 1) return null;
      return m.opacity(v.toDouble());
    },
    source: (v, p) =>
        v is num && v >= 0 && v <= 1 ? '.opacity(${v.toDouble()})' : null,
  ),
  DVStudioProperty('card', DVStudioPropertyKind.flag,
      (m, v, p) => v == true ? m.card() : null,
      source: (v, p) => v == true ? '.card()' : null),
];

/// The border width a document asks for, defaulting to one point.
///
/// A designer who set a colour and left the width alone means a hairline, not
/// nothing.
double _borderWidthOf(Map<String, Object?> properties) {
  final Object? width = properties['borderWidth'];
  return width is num ? width.toDouble() : 1;
}

String _hex(Color colour) =>
    (colour.toARGB32() & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0').toUpperCase();



/// The parts of a shadow that are not its colour.
const List<String> _shadowParts = <String>[
  'shadowX',
  'shadowY',
  'shadowBlur',
  'shadowSpread',
];

/// The shadow [colour] and [properties] describe, or null when there is
/// none.
///
/// A blur with no colour is not a shadow: defaulting to black would put one
/// under every box that named a radius, which is a design nobody drew.
List<BoxShadow>? _shadowOf(Object? colour, Map<String, Object?> properties) {
  final Color? parsed = parseDocumentColor(colour);
  if (parsed == null) return null;
  double part(String name) {
    final Object? value = properties[name];
    return value is num ? value.toDouble() : 0;
  }

  return <BoxShadow>[
    BoxShadow(
      color: parsed,
      offset: Offset(part('shadowX'), part('shadowY')),
      blurRadius: part('shadowBlur'),
      spreadRadius: part('shadowSpread'),
    ),
  ];
}

/// The named edges, in the order [paddingOnly] takes them.
const List<String> _paddingEdges = <String>[
  'paddingLeft',
  'paddingTop',
  'paddingRight',
  'paddingBottom',
];

/// Whether any single edge is named, which is what makes this padding more
/// than one number.
bool _hasEdgePadding(Map<String, Object?> properties) =>
    _paddingEdges.any((String side) => properties[side] is num);

/// The value for one edge: its own if it has one, else the one number, else
/// nothing.
double _paddingEdge(Map<String, Object?> properties, String side) {
  final Object? own = properties[side];
  if (own is num) return own.toDouble();
  final Object? all = properties['padding'];
  return all is num ? all.toDouble() : 0;
}

/// Applies the whole padding, whichever property asked.
DVModifier? _padding(DVModifier modifier, Map<String, Object?> properties) {
  if (!_hasEdgePadding(properties)) {
    final Object? all = properties['padding'];
    return all is num ? modifier.padding(all.toDouble()) : null;
  }
  return modifier.paddingOnly(
    left: _paddingEdge(properties, 'paddingLeft'),
    top: _paddingEdge(properties, 'paddingTop'),
    right: _paddingEdge(properties, 'paddingRight'),
    bottom: _paddingEdge(properties, 'paddingBottom'),
  );
}

/// The exported call, written once.
///
/// Emitted by the first named edge and by none of the others, because the
/// call says all four sides and a second one would replace the first.
String? _paddingEdgeSource(String side, Map<String, Object?> properties) {
  if (!_hasEdgePadding(properties)) return null;
  final String first =
      _paddingEdges.firstWhere((String s) => properties[s] is num);
  if (side != first) return null;
  final String args = <String>[
    'left: ${_paddingEdge(properties, 'paddingLeft')}',
    'top: ${_paddingEdge(properties, 'paddingTop')}',
    'right: ${_paddingEdge(properties, 'paddingRight')}',
    'bottom: ${_paddingEdge(properties, 'paddingBottom')}',
  ].join(', ');
  return '.paddingOnly($args)';
}

/// A single-quoted Dart literal's contents.
String _escapeSource(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

String? _numberSource(String name, Object? value) =>
    value is num ? '.$name(${value.toDouble()})' : null;

String? _colourSource(String name, Object? value) {
  final Color? colour = parseDocumentColor(value);
  return colour == null ? null : '.$name(Color(0x${_hex(colour)}))';
}

/// A property that is an argument to the box rather than a modifier on it.
///
/// These cannot live in [dvStudioProperties]: every entry there has to apply
/// to a [DVModifier], and spacing is not something a modifier can express --
/// it is how [DVBox] lays its children out. They are a list of their own
/// rather than nothing, because a property the renderer honours and the
/// inspector cannot offer is exactly the drift that list exists to prevent.
class DVStudioLayoutProperty {
  const DVStudioLayoutProperty(this.name, this.kind, {this.choices = const <String>[]});

  final String name;
  final DVStudioPropertyKind kind;
  final List<String> choices;
}

/// How a box lays its children out, as the inspector offers it.
final List<DVStudioLayoutProperty> dvStudioLayoutProperties =
    <DVStudioLayoutProperty>[
  const DVStudioLayoutProperty('spacing', DVStudioPropertyKind.number),
  const DVStudioLayoutProperty('mainAxis', DVStudioPropertyKind.choice,
      choices: dvStudioAlignNames),
  const DVStudioLayoutProperty('crossAxis', DVStudioPropertyKind.choice,
      choices: dvStudioCrossAlignNames),
  // Whether the box scrolls its own axis: a list down, a row across. Almost
  // every screen in a design is taller than the device it runs on.
  const DVStudioLayoutProperty('scroll', DVStudioPropertyKind.flag),
];

/// The image a node describes.
///
/// `src` is the reference and `source` names its kind, defaulting to a URL so
/// that every document written before a page could say otherwise reads as it
/// always did. Built through [DVImage.fromJson] rather than a switch here, so
/// a page node and a model field cannot come to disagree about what `stored`
/// or `asset` means -- including the leniency, which is deliberate there: a
/// page that will not render because one word is misspelled is worse than one
/// that tries the address.
DVImage dvStudioImageOf(Map<String, Object?> properties) {
  final String reference = '${properties['src'] ?? ''}';
  // An image with no source yet: one just dropped onto the canvas, or one an
  // import could not resolve. A normal state, and a common one -- the reader
  // refuses an empty reference, which is right for a model field and would
  // take a page down here over a picture nobody has chosen.
  if (reference.isEmpty) return const DVImage.network('');
  return DVImage.fromJson(<String, Object?>{
        'reference': reference,
        if (properties['source'] != null) 'source': properties['source'],
        if (properties['alt'] != null) 'alt': properties['alt'],
      }) ??
      const DVImage.network('');
}

/// The names [DVAlign] answers to in a page document.
const List<String> dvStudioAlignNames = <String>[
  'start',
  'center',
  'end',
  'spaceBetween',
  'spaceAround',
  'spaceEvenly',
];

/// The names [DVCrossAlign] answers to.
const List<String> dvStudioCrossAlignNames = <String>[
  'stretch',
  'start',
  'center',
  'end',
];

/// The gap a box leaves between its children.
///
/// Eight when unset, which is the framework's default and what every page
/// rendered before this was read. Zero when the document says zero: a design
/// with no gaps is a real design, and reading a deliberate zero as "unset" is
/// the fallback that swallows it.
double dvStudioSpacingOf(Map<String, Object?> properties) {
  final Object? spacing = properties['spacing'];
  return spacing is num ? spacing.toDouble() : 8;
}

/// [DVAlign] by name, defaulting to start.
///
/// A name that is not an alignment falls back rather than throwing.
/// Documents are data: they are edited by hand and they arrive from imports,
/// and a page that will not render because one word is misspelled is worse
/// than a page laid out to the start.
DVAlign dvStudioAlignOf(Object? name) => switch (name) {
      'center' => DVAlign.center,
      'end' => DVAlign.end,
      'spaceBetween' => DVAlign.spaceBetween,
      'spaceAround' => DVAlign.spaceAround,
      'spaceEvenly' => DVAlign.spaceEvenly,
      _ => DVAlign.start,
    };

/// [DVCrossAlign] by name, defaulting to stretch.
DVCrossAlign dvStudioCrossAlignOf(Object? name) => switch (name) {
      'start' => DVCrossAlign.start,
      'center' => DVCrossAlign.center,
      'end' => DVCrossAlign.end,
      _ => DVCrossAlign.stretch,
    };

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
