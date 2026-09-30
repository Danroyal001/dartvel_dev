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

import 'dart:async';

import 'package:flutter/gestures.dart' show HitTestEntry, PointerSignalEvent;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show BoxHitTestResult, SemanticsProperties;

import '../../dartvel_flutter.dart';

/// Where Studio's Pages section learns the site.
class DVStudioSiteSource {
  const DVStudioSiteSource({
    required this.pages,
    this.structure,
    this.preview,
    DVStudioPageView? view,
    this.look,
  }) : _view = view;

  /// Every route, compiled and stored.
  final Future<List<DVStudioSitePage>> Function() pages;

  /// The captured structure of a compiled page, as the build's semantics
  /// capture writes it, or null when there is none.
  final Future<Object?> Function(String route)? structure;

  /// The compiled page itself, built as its route builds it, where the
  /// application's code is in the process: Studio inside the application.
  final Widget? Function(String path)? preview;

  final DVStudioPageView? _view;

  /// Each page as its route builds it -- the page, its layouts and its
  /// shell -- with a document Studio is editing in place of the page's body
  /// when one is given. The generated `dartvelPagePreview` is one, so a
  /// [preview] that is one serves as both.
  DVStudioPageView? get view {
    final DVStudioPageView? given = _view;
    if (given != null) return given;
    final Widget? Function(String path)? preview = this.preview;
    return preview is DVStudioPageView ? preview : null;
  }

  /// The application's themes and scroll behaviour, which a page on the
  /// canvas is drawn with. Null draws it in whatever theme is in force.
  final DVStudioAppLook? look;
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
  // Not 'Override': a person who has never written code knows what a copy
  // is.
  DVStudioPageKind.override => 'Studio copy',
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

/// A compiled page drawn on the artboard, as the application draws it, in a
/// window of a device's size. A preview: it is looked at and scrolled, not
/// clicked through -- a tap on one of its links must not take Studio away.
class DVStudioLivePage extends StatelessWidget {
  const DVStudioLivePage({
    super.key,
    required this.page,
    required this.width,
    this.height,
    this.zoom,
    this.captureKey,
    this.look,
    this.appearance,
    this.location,
  });

  /// The page, built as its route builds it.
  final Widget page;

  /// The device width it is laid out at.
  final double width;

  /// The device's height, or null to fill the space there is.
  final double? height;

  /// How far it is magnified, or null to fit the space there is.
  final double? zoom;

  /// Where [dvStudioStructureOf] reads the page from.
  final GlobalKey? captureKey;

  /// The page's address.
  final String? location;

  /// The application's look, which the page is drawn in. Without one, the
  /// page takes whatever theme is in force.
  final DVStudioAppLook? look;

  /// The appearance somebody chose to see it in; null for the one the
  /// application shows on this device.
  final Brightness? appearance;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        final double fit =
            ((box.maxWidth - 48) / width).clamp(0.25, 1.0).toDouble();
        final double scale = zoom ?? fit;
        final double h = height ??
            (box.maxHeight.isFinite ? (box.maxHeight - 48) / scale : 900);
        return ColoredBox(
          color: DVStudioStyle.canvas,
          child: SingleChildScrollView(
            padding: const .all(24),
            child: Center(
              child: SizedBox(
                width: width * scale,
                height: h * scale,
                child: FittedBox(
                  fit: .contain,
                  alignment: .topCenter,
                  child: DVStudioPageWindow(
                    key: const ValueKey<String>('dv-studio-live-page'),
                    location: location,
                    width: width,
                    height: h,
                    look: look,
                    appearance: appearance,
                    child: _DVStudioLookOnly(
                      child: KeyedSubtree(key: captureKey, child: page),
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

/// A page's window on the canvas: a device's size, the application's look,
/// the device's MediaQuery, and nothing of Studio's -- so the page inside is
/// laid out and painted as it is in a browser window that size.
class DVStudioPageWindow extends StatelessWidget {
  const DVStudioPageWindow({
    super.key,
    required this.width,
    required this.height,
    required this.child,
    this.look,
    this.appearance,
    this.location,
  });

  final double width;
  final double height;
  final Widget child;

  /// The address the page is at, which the page reads its router state for.
  final String? location;
  final DVStudioAppLook? look;
  final Brightness? appearance;

  @override
  Widget build(BuildContext context) {
    final Brightness device = MediaQuery.platformBrightnessOf(context);
    final DVStudioAppLook? look = this.look;
    final Brightness shown = look?.resolve(device, chosen: appearance).brightness ??
        appearance ??
        device;
    Widget inside = DVPagePreviewScope(
      child: location == null
          ? child
          : DVStudioPreviewLocation(path: location!, child: child),
    );
    if (look != null) {
      inside = look.wrap(inside, brightness: device, chosen: appearance);
    }
    return RepaintBoundary(
      child: SizedBox(
        width: width,
        height: height,
        child: ClipRect(
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              size: Size(width, height),
              platformBrightness: shown,
              padding: EdgeInsets.zero,
              viewPadding: EdgeInsets.zero,
              viewInsets: EdgeInsets.zero,
            ),
            child: inside,
          ),
        ),
      ),
    );
  }
}

/// The page, to be looked at: a tap goes nowhere, and the mouse wheel
/// scrolls whatever scrolls under it, as it does on the site.
class _DVStudioLookOnly extends StatefulWidget {
  const _DVStudioLookOnly({required this.child});
  final Widget child;

  @override
  State<_DVStudioLookOnly> createState() => _DVStudioLookOnlyState();
}

class _DVStudioLookOnlyState extends State<_DVStudioLookOnly> {
  final GlobalKey _inside = GlobalKey(debugLabel: 'dv-studio-look-only');

  /// The wheel, handed to what is under the pointer in the page. The page
  /// is behind an AbsorbPointer, so it is hit-tested here, by hand.
  void _wheel(PointerSignalEvent event) {
    final RenderObject? box = _inside.currentContext?.findRenderObject();
    if (box is! RenderBox) return;
    final BoxHitTestResult result = BoxHitTestResult();
    box.hitTest(result, position: box.globalToLocal(event.position));
    for (final HitTestEntry entry in result.path) {
      entry.target.handleEvent(event.transformed(entry.transform), entry);
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerSignal: _wheel,
        child: AbsorbPointer(
          child: KeyedSubtree(key: _inside, child: widget.child),
        ),
      );
}

/// A page drawn on the canvas at [path], as far as the page can tell: the
/// router's state under it is a state for [path], not for Studio.
///
/// A layout that lights up the link to the page being shown reads the path
/// from `GoRouterState.of(context)`, which inside Studio found Studio's own
/// route: the site's header on the canvas lit nothing, and the docs sidebar
/// marked no page, where the live page marks both. go_router keys that state
/// by the page a route was built for and keeps its registry to itself, so
/// the preview is a page of its own, in a router of its own whose one route
/// is [path].
class DVStudioPreviewLocation extends StatefulWidget {
  const DVStudioPreviewLocation({
    super.key,
    required this.path,
    required this.child,
  });

  final String path;
  final Widget child;

  @override
  State<DVStudioPreviewLocation> createState() =>
      _DVStudioPreviewLocationState();
}

class _DVStudioPreviewLocationState extends State<DVStudioPreviewLocation> {
  GoRouter? _router;
  String? _path;

  /// A router of the preview's own, with one route, [path], and already
  /// there. Built again only when the path changes.
  ///
  /// Only its delegate is mounted -- no information provider, no parser --
  /// so nothing it does reaches the browser's address bar, which is the
  /// application's router's.
  GoRouter _routerFor(String path) {
    final GoRouter? built = _router;
    if (built != null && _path == path) return built;
    // After the frame: the Router still holds the old delegate until it is
    // rebuilt with this one.
    if (built != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => built.dispose());
    }
    final GoRouter router = GoRouter(
      initialLocation: path,
      routes: <RouteBase>[
        GoRoute(
          path: path,
          pageBuilder: (BuildContext context, GoRouterState state) =>
              const NoTransitionPage<void>(
                child: Builder(builder: _DVStudioPreviewChild.of),
              ),
        ),
      ],
    );
    unawaited(router.routerDelegate
        .setNewRoutePath(router.configuration.findMatch(Uri(path: path))));
    _path = path;
    return _router = router;
  }

  @override
  void dispose() {
    _router?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Nothing to stand in for outside an application with a router.
    if (GoRouter.maybeOf(context) == null) return widget.child;
    final GoRouter router = _routerFor(widget.path);
    return _DVStudioPreviewChild(
      content: widget.child,
      child: Router<RouteMatchList>(routerDelegate: router.routerDelegate),
    );
  }
}

/// Hands the preview's content to the page inside its router, which is
/// built in that router's navigator rather than under this widget.
class _DVStudioPreviewChild extends InheritedWidget {
  const _DVStudioPreviewChild({required this.content, required super.child});

  final Widget content;

  static Widget of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_DVStudioPreviewChild>()!
      .content;

  @override
  bool updateShouldNotify(_DVStudioPreviewChild oldWidget) =>
      content != oldWidget.content;
}

