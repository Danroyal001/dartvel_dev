/// What one page version changes relative to another, node by node.
///
/// The content workflow's own `diff()` compares a document's top-level
/// fields, and a page document has two that matter: `title` and `root`. Every
/// edit anywhere on a page is therefore "root changed", which is true and
/// tells a reviewer nothing. This is the diff Studio's History panel shows.
///
/// Nodes are matched by id, which the editor keeps stable across edits, so:
///
/// - a node that changed container is a **move**, never a removal plus an
///   addition, which would read as deleted content;
/// - a removed or added container is **one** change that counts what it
///   held, rather than one line per descendant;
/// - a node whose index shifted only because a sibling was inserted before it
///   is not reported at all. Only the order among the siblings both versions
///   share counts.
library dartvel_flutter.studio.content_diff;

import 'dart:convert';

import '../../dartvel_flutter.dart';

/// How a node differs between the two versions.
enum DVPageChangeKind { added, removed, moved, changed }

/// One property that differs, with both values.
class DVPagePropertyChange {
  const DVPagePropertyChange(this.name, this.from, this.to);

  /// The property name. A breakpoint override is named `fontSize (tablet)`.
  final String name;
  final Object? from;
  final Object? to;

  /// [from] as a person reads it.
  String get fromText => describe(from);

  /// [to] as a person reads it.
  String get toText => describe(to);

  /// A property value as a short, readable string: text quoted, numbers
  /// without a trailing `.0`, a map as `key: value` pairs, absent as `—`.
  static String describe(Object? value) {
    if (value == null) return '—';
    if (value is String) {
      final String flat = value.replaceAll('\n', ' ');
      return '"${flat.length > 60 ? '${flat.substring(0, 57)}…' : flat}"';
    }
    if (value is double && value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    if (value is num || value is bool) return '$value';
    if (value is Map) {
      return <String>[
        for (final MapEntry<Object?, Object?> e in value.entries)
          '${e.key}: ${e.value is String ? e.value : describe(e.value)}',
      ].join(', ');
    }
    if (value is List) {
      return value.length == 1 ? '1 item' : '${value.length} items';
    }
    return '$value';
  }
}

/// One node that was added, removed, moved or changed.
class DVPageNodeChange {
  const DVPageNodeChange({
    required this.kind,
    required this.nodeId,
    required this.label,
    this.summary,
    this.properties = const <DVPagePropertyChange>[],
    this.descendants = 0,
    this.fromParent,
    this.toParent,
  });

  final DVPageChangeKind kind;
  final String nodeId;

  /// What the node is called in Layers: `Text`, `Image`, `Row`.
  final String label;

  /// What the node shows, when it shows something short: a text's words, an
  /// image's source. From the newer version, or the older for a removal.
  final String? summary;

  /// For [DVPageChangeKind.changed] (and a move that also changed): what
  /// differs.
  final List<DVPagePropertyChange> properties;

  /// For an addition or removal: how many nodes the node held, all of which
  /// came or went with it.
  final int descendants;

  /// For a move: the label of the container it left, and the one it is in.
  final String? fromParent;
  final String? toParent;
}

/// The node-level difference between two versions of one page.
class DVPageDocumentDiff {
  const DVPageDocumentDiff._({required this.title, required this.nodes});

  /// What [after] changes relative to [before]. A null [before] is a page
  /// with nothing published: every top-level node is an addition.
  factory DVPageDocumentDiff.between(
    DVPageDocument? before,
    DVPageDocument after,
  ) {
    final Map<String, _Placed> old = before == null
        ? <String, _Placed>{}
        : _index(before.root, null, before);
    final Map<String, _Placed> next = _index(after.root, null, after);
    final List<DVPageNodeChange> changes = <DVPageNodeChange>[];

    // Newer version first, in document order, so the list reads top to bottom
    // the way the page does.
    void walk(DVPageNode node) {
      final _Placed here = next[node.id]!;
      final _Placed? was = old[node.id];
      final bool isRoot = node.id == after.root.id;
      if (was == null && !isRoot) {
        changes.add(DVPageNodeChange(
          kind: DVPageChangeKind.added,
          nodeId: node.id,
          label: here.label,
          summary: _summary(node),
          descendants: _count(node),
        ));
        return; // Its children came with it.
      }
      if (was != null) {
        final List<DVPagePropertyChange> properties =
            _propertyChanges(was.node, node);
        final bool moved = !isRoot && _moved(was, here, old, next);
        if (moved) {
          changes.add(DVPageNodeChange(
            kind: DVPageChangeKind.moved,
            nodeId: node.id,
            label: here.label,
            summary: _summary(node),
            properties: properties,
            fromParent: was.parent == null ? null : old[was.parent]!.label,
            toParent: here.parent == null ? null : next[here.parent]!.label,
          ));
        } else if (properties.isNotEmpty) {
          changes.add(DVPageNodeChange(
            kind: DVPageChangeKind.changed,
            nodeId: node.id,
            label: here.label,
            summary: _summary(node),
            properties: properties,
          ));
        }
      }
      for (final DVPageNode child in node.children) {
        walk(child);
      }
    }

    walk(after.root);

    // Then removals, top-most only: a removed container took its children.
    if (before != null) {
      void removed(DVPageNode node) {
        if (!next.containsKey(node.id)) {
          changes.add(DVPageNodeChange(
            kind: DVPageChangeKind.removed,
            nodeId: node.id,
            label: old[node.id]!.label,
            summary: _summary(node),
            descendants: _count(node),
          ));
          return;
        }
        for (final DVPageNode child in node.children) {
          removed(child);
        }
      }

      removed(before.root);
    }

    return DVPageDocumentDiff._(
      title: before == null || before.title == after.title
          ? null
          : DVPagePropertyChange('title', before.title, after.title),
      nodes: List<DVPageNodeChange>.unmodifiable(changes),
    );
  }

  /// The page title's change, or null when it did not change.
  final DVPagePropertyChange? title;

  /// Every node change, additions, moves and edits in the newer version's
  /// document order, then removals in the older one's.
  final List<DVPageNodeChange> nodes;

  bool get isEmpty => title == null && nodes.isEmpty;

  int get added => _of(DVPageChangeKind.added);
  int get removed => _of(DVPageChangeKind.removed);
  int get moved => _of(DVPageChangeKind.moved);
  int get changed => _of(DVPageChangeKind.changed);

  int _of(DVPageChangeKind kind) =>
      nodes.where((DVPageNodeChange c) => c.kind == kind).length;

  static Map<String, _Placed> _index(
    DVPageNode root,
    String? parent,
    DVPageDocument document,
  ) {
    final Map<String, _Placed> out = <String, _Placed>{};
    void visit(DVPageNode node, String? parentId) {
      out[node.id] = _Placed(node, parentId, _label(node, document));
      for (final DVPageNode child in node.children) {
        visit(child, node.id);
      }
    }

    visit(root, parent);
    return out;
  }

  static String _label(DVPageNode node, DVPageDocument document) {
    if (node.id == document.root.id) return 'Page';
    return dvStudioLeafTypeFor(node)?.label ?? dvStudioLayoutLabel(node.layout);
  }

  static String? _summary(DVPageNode node) {
    final Object? shown = node.properties['text'] ?? node.properties['src'];
    if (shown is! String || shown.trim().isEmpty) return null;
    final String flat = shown.replaceAll('\n', ' ').trim();
    return flat.length > 60 ? '${flat.substring(0, 57)}…' : flat;
  }

  static int _count(DVPageNode node) => node.children.fold<int>(
      0, (int n, DVPageNode child) => n + 1 + _count(child));

  /// Moved when the container changed, or when the node's place among the
  /// siblings present in both versions changed. Siblings added or removed
  /// around it shift its index without moving it.
  static bool _moved(
    _Placed was,
    _Placed here,
    Map<String, _Placed> old,
    Map<String, _Placed> next,
  ) {
    if (was.parent != here.parent) return true;
    if (was.parent == null) return false;
    List<String> shared(DVPageNode parent, Map<String, _Placed> other) =>
        <String>[
          for (final DVPageNode child in parent.children)
            if (other[child.id]?.parent == parent.id) child.id,
        ];
    final List<String> before = shared(old[was.parent]!.node, next);
    final List<String> after = shared(next[here.parent]!.node, old);
    return before.indexOf(here.node.id) != after.indexOf(here.node.id);
  }

  static List<DVPagePropertyChange> _propertyChanges(
    DVPageNode from,
    DVPageNode to,
  ) {
    final List<DVPagePropertyChange> out = <DVPagePropertyChange>[];
    if (from.type != to.type) {
      out.add(DVPagePropertyChange('type', from.type, to.type));
    }
    if (from.layout != to.layout) {
      out.add(DVPagePropertyChange('layout', from.layout, to.layout));
    }
    if (_encode(from.action) != _encode(to.action)) {
      out.add(DVPagePropertyChange('action', from.action, to.action));
    }
    out.addAll(_mapChanges(from.properties, to.properties, null));
    final List<String> breakpoints = <String>{
      ...from.breakpoints.keys,
      ...to.breakpoints.keys,
    }.toList()
      ..sort((String a, String b) => _breakpointOrder(a) - _breakpointOrder(b));
    for (final String breakpoint in breakpoints) {
      out.addAll(_mapChanges(
        from.breakpoints[breakpoint] ?? const <String, Object?>{},
        to.breakpoints[breakpoint] ?? const <String, Object?>{},
        breakpoint,
      ));
    }
    return out;
  }

  static int _breakpointOrder(String name) {
    for (final DVBreakpoint b in DVBreakpoint.values) {
      if (b.name == name) return b.index;
    }
    return DVBreakpoint.values.length;
  }

  static Iterable<DVPagePropertyChange> _mapChanges(
    Map<String, Object?> from,
    Map<String, Object?> to,
    String? breakpoint,
  ) sync* {
    final List<String> keys = <String>{...from.keys, ...to.keys}.toList()
      ..sort();
    for (final String key in keys) {
      if (_encode(from[key]) == _encode(to[key])) continue;
      yield DVPagePropertyChange(
        breakpoint == null ? key : '$key ($breakpoint)',
        from[key],
        to[key],
      );
    }
  }

  /// Canonical JSON, so `16` and `16.0`, or maps written in another key
  /// order, are not reported as changes nobody made.
  static String _encode(Object? value) => jsonEncode(_canonical(value));

  static Object? _canonical(Object? value) {
    if (value is double && value == value.roundToDouble()) return value.toInt();
    if (value is Map) {
      final List<String> keys = <String>[
        for (final Object? k in value.keys) '$k',
      ]..sort();
      return <String, Object?>{
        for (final String k in keys) k: _canonical(value[k]),
      };
    }
    if (value is List) {
      return <Object?>[for (final Object? v in value) _canonical(v)];
    }
    return value;
  }
}

class _Placed {
  _Placed(this.node, this.parent, this.label);
  final DVPageNode node;
  final String? parent;
  final String label;
}
