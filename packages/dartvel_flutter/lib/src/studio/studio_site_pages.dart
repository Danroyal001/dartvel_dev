/// Every page the application answers, as Studio's Pages section opens them.
///
/// Studio's Pages listed what its own store held, so a site whose pages are
/// all compiled opened on "0 pages". A site is its compiled routes -- learned
/// from the application's own route manifest when Studio runs inside it, or
/// from the project graph when a server serves Studio -- plus the pages
/// stored in Studio, each marked code, stored, or a stored override of a
/// compiled route (`dvStudioSitePages` in dartvel_core does the merge, for
/// both).
///
/// A compiled page opens with its structure: the tree of headings, text,
/// links, images and buttons the page is made of. A server has the one the
/// build captured; an application Studio runs inside renders the page itself
/// and reads the tree off it. Both become the same page document, which is
/// what the editor edits and what an override stores.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SemanticsProperties;

import '../../dartvel_flutter.dart';

/// Where Studio's Pages section learns the site.
class DVStudioSiteSource {
  const DVStudioSiteSource({
    required this.pages,
    this.structure,
    this.preview,
  });

  /// Every route, compiled and stored.
  final Future<List<DVStudioSitePage>> Function() pages;

  /// The captured structure of a compiled page, as the build's semantics
  /// capture writes it, or null when there is none.
  final Future<Object?> Function(String route)? structure;

  /// The compiled page itself, built as its route builds it, where the
  /// application's code is in the process: Studio inside the application.
  final Widget? Function(String path)? preview;
}

/// [route] as the project graph describes a route.
Map<String, Object?> dvStudioRouteInfoJson(DVRouteInfo route) =>
    <String, Object?>{
      'path': route.path,
      'page': route.page,
      'source': route.directory,
      'kind': route.module == null ? 'page' : 'module page',
      'module': route.module,
    };

/// What a page's kind reads as in a badge.
String dvStudioPageKindLabel(DVStudioSitePage page) => switch (page.kind) {
  DVStudioPageKind.code => 'Code',
  DVStudioPageKind.stored => 'Studio',
  DVStudioPageKind.override => 'Override',
};

/// The tone of a page's kind badge.
Color dvStudioPageKindTone(DVStudioSitePage page) => switch (page.kind) {
  DVStudioPageKind.code => DVStudioStyle.muted,
  DVStudioPageKind.stored => DVStudioStyle.success,
  DVStudioPageKind.override => DVStudioStyle.warning,
};

// --- structure → document ----------------------------------------------------

/// The page document a captured structure describes.
///
/// [tree] is a list of nodes, each `{role, level, label, href, src,
/// children}` -- the shape the build's semantics capture writes and
/// [dvStudioStructureOf] reads off a rendered page. Headings become text at
/// their level's size, links text that navigates, buttons buttons, images
/// images, and a node with children a column of them. Structure with no
/// words of its own is flattened away: a column of one column is one column.
DVPageDocument dvStudioDocumentFromStructure(
  String route,
  Object? tree, {
  String? title,
}) {
  final DVPageNode root = DVPageNode(
    type: 'box',
    properties: <String, Object?>{'padding': 32, 'spacing': 16},
  );
  if (tree is List) {
    for (final Object? node in tree) {
      root.children.addAll(_nodesOf(node));
    }
  }
  return DVPageDocument(
    route: route,
    title: title ?? _titleOf(tree) ?? route,
    root: root,
  );
}

/// The first top-level heading, which a page is usually named by.
String? _titleOf(Object? tree) {
  String? found;
  void walk(Object? node) {
    if (found != null || node is! Map) return;
    if (node['level'] == 1 && '${node['label'] ?? ''}'.trim().isNotEmpty) {
      found = '${node['label']}'.trim();
      return;
    }
    for (final Object? child in (node['children'] as List?) ?? const <Object?>[]) {
      walk(child);
    }
  }

  if (tree is List) tree.forEach(walk);
  return found;
}

const Map<int, double> _headingSizes = <int, double>{
  1: 40,
  2: 30,
  3: 24,
  4: 20,
  5: 18,
  6: 16,
};

List<DVPageNode> _nodesOf(Object? node) {
  if (node is! Map) return const <DVPageNode>[];
  final String role = '${node['role'] ?? ''}';
  final String label = '${node['label'] ?? ''}'.trim();
  final Object? href = node['href'];
  final int? level = node['level'] is num ? (node['level']! as num).toInt() : null;
  final List<DVPageNode> children = <DVPageNode>[
    for (final Object? child in (node['children'] as List?) ?? const <Object?>[])
      ..._nodesOf(child),
  ];
  if (role == 'img' || role == 'image') {
    final Object? src = node['src'];
    return <DVPageNode>[
      DVPageNode(
        type: 'image',
        properties: <String, Object?>{
          'src': src is String && src.isNotEmpty ? src : '',
          if (label.isNotEmpty) 'alt': label,
        },
      ),
    ];
  }
  if (href is String && href.isNotEmpty) {
    // A link's words are its label, or what is inside it.
    final String text = label.isNotEmpty ? label : _textIn(children);
    if (text.isEmpty) return children;
    return <DVPageNode>[
      DVPageNode(
        type: 'text',
        properties: <String, Object?>{
          'text': text,
          'color': '#5B3DF5',
          'fontWeight': 'medium',
        },
        action: <String, Object?>{'type': 'navigate', 'to': href},
      ),
    ];
  }
  if (role == 'button' && label.isNotEmpty && children.isEmpty) {
    return <DVPageNode>[
      DVPageNode(
        type: 'button',
        properties: <String, Object?>{'text': label, ...dvStudioButtonDefaults},
      ),
    ];
  }
  final List<DVPageNode> out = <DVPageNode>[];
  if (label.isNotEmpty) {
    out.add(
      DVPageNode(
        type: 'text',
        properties: <String, Object?>{
          'text': label,
          if (level != null && level > 0) ...<String, Object?>{
            'fontSize': _headingSizes[level.clamp(1, 6)],
            'fontWeight': level <= 2 ? 'bold' : 'semibold',
          },
          if (role == 'code') 'fontFamily': 'monospace',
        },
      ),
    );
  }
  if (children.isEmpty) return out;
  if (out.isEmpty && children.length == 1) return children;
  if (out.isEmpty && role != 'group' && role != 'list') return children;
  return <DVPageNode>[
    ...out,
    DVPageNode(
      type: 'box',
      layout: node['layout'] == 'row' ? 'row' : 'list',
      properties: <String, Object?>{'spacing': 12},
      children: children,
    ),
  ];
}

String _textIn(List<DVPageNode> nodes) => <String>[
  for (final DVPageNode node in nodes)
    if (node.properties['text'] case final String text when text.isNotEmpty)
      text
    else
      _textIn(node.children),
].where((String s) => s.isNotEmpty).join(' ');

// --- a rendered page → structure ---------------------------------------------

/// The structure of the page rendered under [context], in the shape the
/// build's semantics capture writes: the words, headings, links, images and
/// buttons, and the rows and columns they sit in.
///
/// Read off the element tree rather than the semantics tree, so it works in
/// a release build and on every platform Studio runs on.
List<Map<String, Object?>> dvStudioStructureOf(BuildContext context) {
  final List<Map<String, Object?>> out = <Map<String, Object?>>[];
  (context as Element).visitChildElements((Element child) {
    out.addAll(_structureOf(child));
  });
  return out;
}

List<Map<String, Object?>> _structureOf(Element element) {
  final Widget widget = element.widget;
  List<Map<String, Object?>> inner() {
    final List<Map<String, Object?>> children = <Map<String, Object?>>[];
    element.visitChildElements((Element child) {
      children.addAll(_structureOf(child));
    });
    return children;
  }

  Map<String, Object?> node({
    String? role,
    int? level,
    String label = '',
    String? href,
    String? src,
    String? layout,
    List<Map<String, Object?>> children = const <Map<String, Object?>>[],
  }) =>
      <String, Object?>{
        'role': role,
        'level': level,
        'label': label,
        'href': href,
        'src': ?src,
        'layout': ?layout,
        'children': children,
      };

  if (widget is Offstage && widget.offstage) return const <Map<String, Object?>>[];
  if (widget is Visibility && !widget.visible) return const <Map<String, Object?>>[];
  if (widget is DVNavLink) {
    final String href = widget.externalUrl ?? widget.to.path;
    final List<Map<String, Object?>> children = inner();
    return <Map<String, Object?>>[
      node(
        role: 'link',
        href: href,
        label: widget.semanticLabel ?? _labelIn(children),
      ),
    ];
  }
  if (widget is Image) {
    final ImageProvider<Object> image = widget.image;
    final String? src = switch (image) {
      NetworkImage(:final String url) => url,
      AssetImage(:final String assetName) => assetName,
      ExactAssetImage(:final String assetName) => assetName,
      _ => null,
    };
    return <Map<String, Object?>>[
      node(role: 'img', label: widget.semanticLabel ?? '', src: src),
    ];
  }
  if (widget is RichText) {
    final String text = widget.text.toPlainText().trim();
    if (text.isEmpty) return const <Map<String, Object?>>[];
    return <Map<String, Object?>>[node(label: text)];
  }
  if (widget is Semantics) {
    final SemanticsProperties properties = widget.properties;
    final int? level = properties.headingLevel;
    final bool heading = (level != null && level > 0) || properties.header == true;
    if (heading || properties.button == true) {
      final List<Map<String, Object?>> children = inner();
      final String label = properties.label ?? _labelIn(children);
      if (properties.button == true && !heading) {
        return <Map<String, Object?>>[node(role: 'button', label: label)];
      }
      return <Map<String, Object?>>[
        node(level: level != null && level > 0 ? level : 2, label: label),
      ];
    }
  }
  if (widget is Flex) {
    final List<Map<String, Object?>> children = inner();
    if (children.length < 2) return children;
    return <Map<String, Object?>>[
      node(
        role: 'group',
        layout: widget.direction == Axis.horizontal ? 'row' : 'list',
        children: children,
      ),
    ];
  }
  return inner();
}

String _labelIn(List<Map<String, Object?>> nodes) => <String>[
  for (final Map<String, Object?> node in nodes)
    if ('${node['label'] ?? ''}'.isNotEmpty)
      '${node['label']}'
    else
      _labelIn(((node['children'] as List?) ?? const <Object?>[])
          .cast<Map<String, Object?>>()),
].where((String s) => s.isNotEmpty).join(' ');

// --- the compiled page, live -------------------------------------------------

/// A compiled page drawn on the artboard, as the application draws it, at a
/// device's width. A preview: it is looked at, not clicked through.
class DVStudioLivePage extends StatelessWidget {
  const DVStudioLivePage({
    super.key,
    required this.page,
    required this.width,
    this.zoom,
    this.captureKey,
  });

  /// The page, built as its route builds it.
  final Widget page;

  /// The device width it is laid out at.
  final double width;

  /// How far it is magnified, or null to fit the space there is.
  final double? zoom;

  /// Where [dvStudioStructureOf] reads the page from.
  final GlobalKey? captureKey;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final double fit =
            ((box.maxWidth - 48) / width).clamp(0.25, 1.0).toDouble();
        final double scale = zoom ?? fit;
        final double height = box.maxHeight.isFinite
            ? (box.maxHeight - 48) / scale
            : 900;
        return ColoredBox(
          color: DVStudioStyle.canvas,
          child: SingleChildScrollView(
            padding: const .all(24),
            child: Center(
              child: SizedBox(
                width: width * scale,
                height: height * scale,
                child: FittedBox(
                  fit: .contain,
                  alignment: .topCenter,
                  child: SizedBox(
                    key: const ValueKey<String>('dv-studio-live-page'),
                    width: width,
                    height: height,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFFFF),
                        border: Border.all(color: DVStudioStyle.line),
                      ),
                      child: ClipRect(
                        child: AbsorbPointer(
                          child: MediaQuery(
                            data: MediaQuery.of(context).copyWith(
                              size: Size(width, height),
                            ),
                            child: Material(
                              child: KeyedSubtree(
                                key: captureKey,
                                child: page,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
