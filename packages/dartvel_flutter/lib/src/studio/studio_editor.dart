import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart'
    show Icon, IconData, Icons, PopupMenuItem, showMenu;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/widgets.dart';

import '../../dartvel_flutter.dart';

/// Editing state for one page document: what is selected, what changed, and
/// how to undo it.
///
/// Every mutation goes through here rather than through
/// [DVPageDocumentEditor] directly, because an editor without undo is not an
/// editor — a mis-drop that cannot be reversed loses work.
class DVStudioEditorController extends ChangeNotifier {
  DVPageDocument _document;

  /// Snapshots taken before each mutation. Snapshotting the whole document is
  /// deliberate: an inverse-operation log has to be right for every operation
  /// to be right at all, and a page document is small.
  final List<Map<String, Object?>> _undo = <Map<String, Object?>>[];
  final List<Map<String, Object?>> _redo = <Map<String, Object?>>[];

  String? _selectedId;

  /// How many snapshots to keep. Deep enough for a working session, bounded
  /// so a long edit cannot grow without limit.
  final int historyLimit;

  /// A read-only controller refuses local mutations with a [StateError] but
  /// still applies edits from elsewhere: a viewer's screen follows the
  /// editors without getting to type. Settable, because the screen creates
  /// the controller and whatever attaches to it decides who may edit.
  bool readOnly;

  DVStudioEditorController(
    DVPageDocument document, {
    this.historyLimit = 100,
    this.readOnly = false,
  }) : _document = document;

  DVPageDocument get document => _document;

  final StreamController<DVStudioEdit> _edits =
      StreamController<DVStudioEdit>.broadcast();

  /// Every mutation this controller performs, as data another controller can
  /// [apply]. Edits applied from elsewhere are not republished, or two
  /// collaborators would echo each other forever.
  Stream<DVStudioEdit> get edits => _edits.stream;

  /// Performs an edit made elsewhere.
  ///
  /// Outside local undo: undoing would otherwise revert a collaborator's
  /// change, which is not what the person pressing undo meant. Throws
  /// [ArgumentError] when the edit cannot apply, leaving the document as it
  /// was.
  void apply(DVStudioEdit edit) {
    edit.applyTo(_editor);
    _dropDanglingSelection();
    notifyListeners();
  }

  /// The selected node, or null when nothing is selected.
  String? get selectedId => _selectedId;

  DVPageNode? get selectedNode =>
      _selectedId == null ? null : _editor.find(_selectedId!);

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  DVPageDocumentEditor get _editor => DVPageDocumentEditor(_document);

  void select(String? id) {
    if (_selectedId == id) return;
    _selectedId = id;
    notifyListeners();
  }

  /// Runs [mutate], recording the document beforehand so it can be undone.
  ///
  /// A mutation that throws — dropping a container into itself, say — leaves
  /// no history entry, so undo cannot replay a change that never happened.
  void _mutate(void Function(DVPageDocumentEditor editor) mutate) {
    if (readOnly) throw StateError('This editor is read-only.');
    final snapshot = _document.toJson();
    try {
      mutate(_editor);
    } catch (_) {
      rethrow;
    }
    _undo.add(snapshot);
    if (_undo.length > historyLimit) _undo.removeAt(0);
    _redo.clear();
    notifyListeners();
  }

  /// Inserts [node] under [parent]. This is a drop from the palette.
  void insert(DVPageNode node, {required String parent, int? index}) {
    _mutate((DVPageDocumentEditor editor) {
      editor.insert(node, parent: parent, index: index);
    });
    _edits.add(DVStudioEdit.insert(node, parent: parent, index: index));
    select(node.id);
  }

  /// Reparents a node. This is a drag between containers.
  void move(String id, {required String parent, int? index}) {
    _mutate((DVPageDocumentEditor editor) {
      editor.move(id, parent: parent, index: index);
    });
    _edits.add(DVStudioEdit.move(id, parent: parent, index: index));
  }

  /// Replaces a node. This is the property inspector.
  void update(String id, DVPageNode Function(DVPageNode node) transform) {
    _mutate((DVPageDocumentEditor editor) {
      editor.update(id, transform);
    });
    _edits.add(DVStudioEdit.update(id, _editor.find(id)!));
  }

  /// Sets one property on the selected node — the inspector's common case.
  void setProperty(String id, String name, Object? value) {
    update(id, (DVPageNode node) => node.withProperty(name, value));
  }

  /// Binds an action to a node, or clears it with null.
  void setAction(String id, Map<String, Object?>? action) {
    update(id, (DVPageNode node) => node.withAction(action));
  }

  void remove(String id) {
    _mutate((DVPageDocumentEditor editor) {
      editor.remove(id);
    });
    _edits.add(DVStudioEdit.remove(id));
    if (_selectedId == id) _selectedId = null;
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_document.toJson());
    _document = DVPageDocument.fromJson(_undo.removeLast());
    _edits.add(DVStudioEdit.replace(_document));
    _dropDanglingSelection();
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_document.toJson());
    _document = DVPageDocument.fromJson(_redo.removeLast());
    _edits.add(DVStudioEdit.replace(_document));
    _dropDanglingSelection();
    notifyListeners();
  }

  /// Undo can restore a document without the selected node in it; leaving the
  /// selection pointing at nothing would show an inspector for a node that
  /// does not exist.
  void _dropDanglingSelection() {
    if (_selectedId != null && _editor.find(_selectedId!) == null) {
      _selectedId = null;
    }
  }

  /// Where [save] sends the document, when not the page store.
  ///
  /// Settable by whatever attaches to the editor -- an approval step that
  /// holds the page for review is the case -- so the Pages tab's Publish
  /// button does not need to know. Null means the page store, as before.
  Future<void> Function(DVPageDocument document)? publisher;

  /// Persists the document, which publishes it -- or hands it to
  /// [publisher], which decides.
  Future<void> save() {
    final Future<void> Function(DVPageDocument document)? publish = publisher;
    if (publish != null) return publish(_document);
    return const DVPageStore().save(_document);
  }

  @override
  void dispose() {
    unawaited(_edits.close());
    super.dispose();
  }
}

/// What the palette drags and the canvas accepts.
///
/// A factory rather than a node, so each drop creates a fresh node with its
/// own id instead of dropping the same one repeatedly.
class DVStudioPaletteItem {
  final String label;
  final DVPageNode Function() create;

  const DVStudioPaletteItem({required this.label, required this.create});

  /// The default palette: every leaf type the renderer knows, plus the layout
  /// boxes. Built from `dvStudioLeafTypes` rather than restated, so a new node
  /// type appears in the palette, the canvas and the code export together.
  static List<DVStudioPaletteItem> get defaults => <DVStudioPaletteItem>[
        for (final leaf in dvStudioLeafTypes)
          DVStudioPaletteItem(label: leaf.label, create: leaf.create),
        // Built from dvStudioLayouts for the reason the leaves above are
        // built from dvStudioLeafTypes: four hand-written entries are a
        // fourth list of the same thing, and the wrapping row was missing
        // from every one of them.
        //
        // `single` is left out on purpose. It is what a box with one child
        // already is rather than something anybody drags in, and a palette
        // entry for it would create a box that behaves like a column with a
        // different name.
        for (final String layout in dvStudioLayouts)
          if (layout != 'single')
            DVStudioPaletteItem(
              label: dvStudioLayoutLabel(layout),
              create: () => DVPageNode.box(layout: layout),
            ),
      ];
}

// --- shared helpers ---------------------------------------------------------

/// What a node is called in Layers, on its selection chip and in the
/// inspector: the page, a leaf's palette label, or a box's layout label.
String _dvStudioNodeLabel(DVPageNode node, DVPageDocument document) {
  if (node.id == document.root.id) return 'Page';
  final DVStudioLeafType? leaf = dvStudioLeafTypeFor(node);
  return leaf?.label ?? dvStudioLayoutLabel(node.layout);
}

/// The container holding [id], or null when [id] is the root or absent.
DVPageNode? _dvStudioParentOf(DVPageNode node, String id) {
  for (final DVPageNode child in node.children) {
    if (child.id == id) return node;
    final DVPageNode? found = _dvStudioParentOf(child, id);
    if (found != null) return found;
  }
  return null;
}

/// Where an element inserted by tapping it goes: into the selected container,
/// beside a selected leaf in that leaf's container, or into the page.
///
/// Beside rather than into the page when a leaf is selected, because selecting
/// the heading inside a card and then adding a button means a button in that
/// card — landing it at the bottom of the page is an insert the person then has
/// to find and drag back.
String _dvStudioInsertTarget(DVStudioEditorController controller) {
  final DVPageDocument document = controller.document;
  final DVPageNode? selected = controller.selectedNode;
  if (selected == null) return document.root.id;
  if (selected.type == 'box') return selected.id;
  return _dvStudioParentOf(document.root, selected.id)?.id ?? document.root.id;
}

/// `spaceBetween` → `Space between`, for option labels and tooltips.
String _dvStudioHumanise(String name) {
  if (name.isEmpty) return name;
  final String spaced = name.replaceAllMapped(
    RegExp('([a-z0-9])([A-Z])'),
    (Match m) => '${m[1]} ${m[2]!.toLowerCase()}',
  );
  return spaced[0].toUpperCase() + spaced.substring(1);
}

/// The chip a drag carries: what is being moved, in the accent colour, so it
/// reads as a thing in the hand rather than a stray label.
Widget _dvStudioDragChip(IconData icon, String label) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: DVStudioStyle.accent,
      borderRadius: BorderRadius.circular(999),
      boxShadow: DVStudioStyle.shadow,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 14, color: const Color(0xFFFFFFFF)),
        const SizedBox(width: 6),
        DVText(label).modifier(
          const DVModifier()
              .fontSize(12)
              .color(const Color(0xFFFFFFFF))
              .fontWeight(FontWeight.w600),
        ),
      ],
    ),
  );
}

// --- insert panel -------------------------------------------------------------

/// The elements a page can be built from, grouped, searchable, and each one
/// draggable onto the canvas or insertable with a tap.
class DVStudioPalette extends StatefulWidget {
  final List<DVStudioPaletteItem> items;

  /// When given, tapping an item inserts it — into the selected container, or
  /// into the page when nothing that can hold children is selected. Without
  /// one the palette is drag-only, which is all it could ever be before.
  final DVStudioEditorController? controller;

  const DVStudioPalette({
    super.key,
    this.items = const <DVStudioPaletteItem>[],
    this.controller,
  });

  @override
  State<DVStudioPalette> createState() => _DVStudioPaletteState();
}

class _DVStudioPaletteState extends State<DVStudioPalette> {
  String _query = '';

  void _insert(DVStudioPaletteItem item) {
    final DVStudioEditorController? controller = widget.controller;
    if (controller == null) return;
    try {
      controller.insert(item.create(),
          parent: _dvStudioInsertTarget(controller));
    } on StateError {
      // A read-only editor: a viewer's palette shows what exists and inserts
      // nothing, rather than throwing into the gesture that tapped it.
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<DVStudioPaletteItem> entries =
        widget.items.isEmpty ? DVStudioPaletteItem.defaults : widget.items;
    final String query = _query.trim().toLowerCase();
    final List<(DVStudioPaletteItem, DVPageNode)> basics =
        <(DVStudioPaletteItem, DVPageNode)>[];
    final List<(DVStudioPaletteItem, DVPageNode)> layouts =
        <(DVStudioPaletteItem, DVPageNode)>[];
    for (final DVStudioPaletteItem item in entries) {
      if (query.isNotEmpty && !item.label.toLowerCase().contains(query)) {
        continue;
      }
      final DVPageNode sample = item.create();
      (sample.type == 'box' ? layouts : basics).add((item, sample));
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Two columns where a tile has room for its icon and label side by
        // side with its neighbour; one in a narrow rail.
        final int columns = constraints.maxWidth >= 180 ? 2 : 1;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: DVStudioTextInput(
                icon: DVStudioIcons.search,
                placeholder: 'Search elements',
                onChanged: (String value) => setState(() => _query = value),
              ),
            ),
            // Every tile built, not only the ones on screen: a palette is a
            // dozen tiles, and a lazy list left the layout group unbuilt in a
            // short panel — absent to anything looking for "Column" until
            // somebody happened to scroll to it.
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (basics.isNotEmpty)
                      ..._group('Basics', basics, columns),
                    if (layouts.isNotEmpty)
                      ..._group('Layout', layouts, columns),
                    if (basics.isEmpty && layouts.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: DVStudioStyle.caption(
                            'No element matches “${_query.trim()}”.'),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _group(
    String label,
    List<(DVStudioPaletteItem, DVPageNode)> items,
    int columns,
  ) {
    return <Widget>[
      Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 8),
        child: DVStudioStyle.overline(label),
      ),
      for (int i = 0; i < items.length; i += columns)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: <Widget>[
              for (int c = 0; c < columns; c++) ...<Widget>[
                if (c > 0) const SizedBox(width: 8),
                Expanded(
                  child: i + c < items.length
                      ? _DVStudioPaletteTile(
                          item: items[i + c].$1,
                          sample: items[i + c].$2,
                          onInsert: widget.controller == null
                              ? null
                              : () => _insert(items[i + c].$1),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
    ];
  }
}

class _DVStudioPaletteTile extends StatefulWidget {
  final DVStudioPaletteItem item;

  /// A node the item creates, read for its icon.
  final DVPageNode sample;
  final VoidCallback? onInsert;

  const _DVStudioPaletteTile({
    required this.item,
    required this.sample,
    required this.onInsert,
  });

  @override
  State<_DVStudioPaletteTile> createState() => _DVStudioPaletteTileState();
}

class _DVStudioPaletteTileState extends State<_DVStudioPaletteTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final IconData icon =
        DVStudioIcons.forNode(widget.sample.type, widget.sample.layout);
    final Widget face = MouseRegion(
      cursor: SystemMouseCursors.grab,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onInsert,
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: _hover ? DVStudioStyle.hover : DVStudioStyle.surface,
            border: Border.all(
              color: _hover ? DVStudioStyle.lineStrong : DVStudioStyle.line,
            ),
            borderRadius: BorderRadius.circular(DVStudioStyle.radius),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                icon,
                size: 18,
                color: _hover ? DVStudioStyle.accent : DVStudioStyle.muted,
              ),
              const SizedBox(height: 6),
              DVText(widget.item.label).modifier(
                const DVModifier()
                    .fontSize(12)
                    .color(DVStudioStyle.ink)
                    .fontWeight(FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
    return Draggable<DVStudioPaletteItem>(
      data: widget.item,
      feedback: _dvStudioDragChip(icon, widget.item.label),
      childWhenDragging: Opacity(opacity: 0.5, child: face),
      child: face,
    );
  }
}

// --- layers ---------------------------------------------------------------------

/// The document as a tree: every node, nested the way the page nests it.
///
/// The canvas shows what a page looks like; this shows what it is made of,
/// which is the only way to reach a node the canvas cannot — a spacer with no
/// height, a box whose children cover it completely. Selection is shared with
/// the canvas through the controller, so choosing in either shows in both.
class DVStudioLayers extends StatefulWidget {
  final DVStudioEditorController controller;

  const DVStudioLayers({super.key, required this.controller});

  @override
  State<DVStudioLayers> createState() => _DVStudioLayersState();
}

class _DVStudioLayersState extends State<DVStudioLayers> {
  final Set<String> _collapsed = <String>{};

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (BuildContext context, Widget? _) {
        final DVPageDocument document = widget.controller.document;
        final List<Widget> rows = <Widget>[];
        void walk(DVPageNode node, int depth) {
          final bool collapsed = _collapsed.contains(node.id);
          rows.add(_DVStudioLayerRow(
            key: ValueKey<String>('dv-studio-layer-${node.id}'),
            controller: widget.controller,
            node: node,
            depth: depth,
            label: _dvStudioNodeLabel(node, document),
            isRoot: node.id == document.root.id,
            collapsed: collapsed,
            onToggle: () => setState(() {
              if (!_collapsed.remove(node.id)) _collapsed.add(node.id);
            }),
          ));
          if (collapsed) return;
          for (final DVPageNode child in node.children) {
            walk(child, depth + 1);
          }
        }

        walk(document.root, 0);
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 6),
          children: rows,
        );
      },
    );
  }
}

class _DVStudioLayerRow extends StatefulWidget {
  final DVStudioEditorController controller;
  final DVPageNode node;
  final int depth;
  final String label;
  final bool isRoot;
  final bool collapsed;
  final VoidCallback onToggle;

  const _DVStudioLayerRow({
    super.key,
    required this.controller,
    required this.node,
    required this.depth,
    required this.label,
    required this.isRoot,
    required this.collapsed,
    required this.onToggle,
  });

  @override
  State<_DVStudioLayerRow> createState() => _DVStudioLayerRowState();
}

class _DVStudioLayerRowState extends State<_DVStudioLayerRow> {
  bool _hover = false;

  /// What follows the label, quieter: a text's words in quotes, an image's
  /// file, how many things a box holds, the page's route.
  ///
  /// Part of the same text as the label rather than a text of its own, so the
  /// page's content is drawn once — by the canvas — and a reader or a finder
  /// looking for "Plans" is not handed a second one in a sidebar.
  String? get _preview {
    final DVPageNode node = widget.node;
    if (widget.isRoot) {
      final String route = widget.controller.document.route;
      return route.isEmpty ? null : route;
    }
    if (node.type == 'text' || node.type == 'button') {
      final String text = '${node.properties['text'] ?? ''}'.trim();
      if (text.isEmpty) return null;
      final String clipped =
          text.length > 28 ? '${text.substring(0, 28)}…' : text;
      return '“$clipped”';
    }
    if (node.type == 'image') {
      final String src = '${node.properties['src'] ?? ''}';
      final int slash = src.lastIndexOf('/');
      final String name = slash >= 0 ? src.substring(slash + 1) : src;
      return name.isEmpty ? null : name;
    }
    if (node.type == 'box') {
      final int count = node.children.length;
      return count == 1 ? '1 item' : '$count items';
    }
    return null;
  }

  void _drop(Object data) {
    try {
      if (data is DVStudioPaletteItem) {
        widget.controller.insert(data.create(), parent: widget.node.id);
      } else if (data is String) {
        widget.controller.move(data, parent: widget.node.id);
      }
    } on ArgumentError {
      // A drop into the node's own subtree: refused by the editor, swallowed
      // here so a mis-drop does not throw into the gesture system.
    } on StateError {
      // Read-only.
    }
  }

  @override
  Widget build(BuildContext context) {
    final DVPageNode node = widget.node;
    final bool selected = widget.controller.selectedId == node.id;
    final bool isBox = node.type == 'box';
    final IconData icon = widget.isRoot
        ? DVStudioIcons.page
        : DVStudioIcons.forNode(node.type, node.layout);
    final String? preview = _preview;

    Widget row(bool dropping) => MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.controller.select(node.id),
            child: Container(
              height: 30,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              padding: EdgeInsets.only(
                  left: 4.0 + math.min(widget.depth * 14.0, 84.0), right: 4),
              decoration: BoxDecoration(
                color: dropping
                    ? DVStudioStyle.accentSoft
                    : selected
                        ? DVStudioStyle.selected
                        : _hover
                            ? DVStudioStyle.hover
                            : const Color(0x00000000),
                border: dropping
                    ? Border.all(color: DVStudioStyle.accent)
                    : null,
                borderRadius: BorderRadius.circular(DVStudioStyle.radiusSmall),
              ),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 18,
                    child: node.children.isEmpty
                        ? null
                        : GestureDetector(
                            key: ValueKey<String>(
                                'dv-studio-layer-toggle-${node.id}'),
                            behavior: HitTestBehavior.opaque,
                            onTap: widget.onToggle,
                            child: Icon(
                              widget.collapsed
                                  ? DVStudioIcons.chevronRight
                                  : DVStudioIcons.chevronDown,
                              size: 16,
                              color: DVStudioStyle.faint,
                            ),
                          ),
                  ),
                  Icon(
                    icon,
                    size: 15,
                    color: selected ? DVStudioStyle.accent : DVStudioStyle.muted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: <InlineSpan>[
                          TextSpan(
                            text: widget.label,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight:
                                  selected ? FontWeight.w600 : FontWeight.w500,
                              color: selected
                                  ? DVStudioStyle.accent
                                  : DVStudioStyle.ink,
                            ),
                          ),
                          if (preview != null)
                            TextSpan(
                              text: '  $preview',
                              style: const TextStyle(
                                fontSize: 12,
                                color: DVStudioStyle.faint,
                              ),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (selected && !widget.isRoot)
                    DVStudioIconButton(
                      icon: DVStudioIcons.delete,
                      tooltip: 'Delete',
                      size: 24,
                      onTap: () {
                        try {
                          widget.controller.remove(node.id);
                        } on StateError {
                          // Read-only.
                        }
                      },
                    ),
                ],
              ),
            ),
          ),
        );

    Widget built = isBox
        ? DragTarget<Object>(
            onWillAcceptWithDetails: (DragTargetDetails<Object> details) =>
                details.data is DVStudioPaletteItem ||
                (details.data is String && details.data != node.id),
            onAcceptWithDetails: (DragTargetDetails<Object> details) =>
                _drop(details.data),
            builder: (BuildContext context, List<Object?> candidate,
                    List<dynamic> _) =>
                row(candidate.isNotEmpty),
          )
        : row(false);

    if (!widget.isRoot) {
      built = Draggable<String>(
        data: node.id,
        feedback: _dvStudioDragChip(icon, widget.label),
        childWhenDragging: Opacity(opacity: 0.4, child: built),
        child: built,
      );
    }
    return built;
  }
}

// --- canvas -----------------------------------------------------------------------

/// The editing canvas.
///
/// Renders the document as the real widgets it describes — the same
/// [DVPageDocumentRenderer] output the running app shows — with selection and
/// drop targets layered over it. What is edited is what ships.
///
/// The page sits on an artboard the width of the device being designed for,
/// on a workspace: tapping the workspace clears the selection, the way it does
/// in every design tool, because otherwise there is no way to see a page
/// without an outline on it.
class DVStudioCanvas extends StatefulWidget {
  final DVStudioEditorController controller;

  /// The width the page is laid out at — a device's — or null to fill the
  /// space the canvas has.
  final double? viewportWidth;

  /// How far the artboard is magnified, from its top centre.
  final double zoom;

  const DVStudioCanvas({
    super.key,
    required this.controller,
    this.viewportWidth,
    this.zoom = 1.0,
  });

  @override
  State<DVStudioCanvas> createState() => _DVStudioCanvasState();
}

class _DVStudioCanvasState extends State<DVStudioCanvas> {
  /// The node under the pointer. A notifier rather than state, so moving the
  /// mouse repaints outlines rather than rebuilding the page.
  final ValueNotifier<String?> _hovered = ValueNotifier<String?>(null);
  final FocusNode _focus = FocusNode(debugLabel: 'dv-studio-canvas');
  final ScrollController _vertical = ScrollController();
  final ScrollController _horizontal = ScrollController();

  /// The artboard's minimum height, so an empty page is a page to drop onto
  /// rather than a strip.
  double _minHeight = 600;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(DVStudioCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _hovered.dispose();
    _focus.dispose();
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  void _select(String? id) {
    widget.controller.select(id);
    // Focus follows the click, so Delete and Escape act on the canvas and not
    // on whichever inspector field last had the caret.
    if (!_focus.hasFocus) _focus.requestFocus();
  }

  void _removeSelected() {
    final String? id = widget.controller.selectedId;
    if (id == null || id == widget.controller.document.root.id) return;
    try {
      widget.controller.remove(id);
    } on StateError {
      // Read-only.
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double available =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 1280;
        final double width = widget.viewportWidth ??
            math.min(math.max(available - 96, 320), 1280).toDouble();
        final double zoom = widget.zoom > 0 ? widget.zoom : 1;
        // In the page's own pixels, so a fitted page still reaches the bottom
        // of the canvas once it is drawn at the zoom.
        _minHeight = constraints.maxHeight.isFinite
            ? math.max(constraints.maxHeight - 120, 240) / zoom
            : 600;

        final DVPageDocument document = widget.controller.document;
        final String route = document.route.isEmpty ? 'Untitled' : document.route;
        final Widget artboard = SizedBox(
          key: const ValueKey<String>('dv-studio-artboard'),
          width: width,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: DVStudioStyle.surface,
              borderRadius: BorderRadius.circular(3),
              boxShadow: DVStudioStyle.shadowLarge,
            ),
            child: _buildNode(document.root, root: true),
          ),
        );
        final Widget scaled = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(DVStudioIcons.page,
                      size: 13, color: DVStudioStyle.muted),
                  const SizedBox(width: 5),
                  DVStudioStyle.caption(
                    '$route  ·  ${widget.viewportWidth == null ? 'Fill' : '${width.round()} px'}'
                    '${zoom == 1 ? '' : '  ·  ${(zoom * 100).round()}%'}',
                  ),
                ],
              ),
            ),
            // Laid out at the device's width and drawn at the zoom, inside a
            // box the size of the drawing, so scrolling, centring and hit
            // testing all find the page where it is drawn. Scaling the drawing
            // alone left the layout full size: a desktop page fitted into a
            // narrow canvas was drawn beside the visible area rather than in
            // it, and a tap on one of its nodes selected nothing.
            if (zoom == 1)
              artboard
            else
              SizedBox(
                width: width * zoom,
                child: FittedBox(
                  fit: BoxFit.fitWidth,
                  alignment: Alignment.topLeft,
                  child: artboard,
                ),
              ),
          ],
        );

        return CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.delete): _removeSelected,
            const SingleActivator(LogicalKeyboardKey.backspace):
                _removeSelected,
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                widget.controller.select(null),
            const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
                widget.controller.undo,
            const SingleActivator(LogicalKeyboardKey.keyZ, meta: true):
                widget.controller.undo,
            const SingleActivator(LogicalKeyboardKey.keyZ,
                control: true, shift: true): widget.controller.redo,
            const SingleActivator(LogicalKeyboardKey.keyZ,
                meta: true, shift: true): widget.controller.redo,
          },
          child: Focus(
            focusNode: _focus,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _select(null),
              child: ColoredBox(
                color: DVStudioStyle.canvas,
                child: CustomPaint(
                  painter: const _DVStudioDotGrid(),
                  child: SingleChildScrollView(
                    controller: _vertical,
                    padding: const EdgeInsets.symmetric(vertical: 36),
                    child: SingleChildScrollView(
                      controller: _horizontal,
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: math.max(available, width * zoom + 96),
                        ),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 48),
                            child: scaled,
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

  Widget _buildNode(DVPageNode node, {bool root = false}) {
    final DVStudioEditorController controller = widget.controller;
    final bool isContainer = node.type == 'box';
    final String label = _dvStudioNodeLabel(node, controller.document);
    final IconData icon = root
        ? DVStudioIcons.page
        : DVStudioIcons.forNode(node.type, node.layout);

    Widget rendered = isContainer
        ? _buildContainer(node)
        : DVPageDocumentRenderer(
            DVPageDocument(route: '', root: node),
          );
    if (root) {
      // The page is at least the artboard's height, so the whole artboard is
      // somewhere to drop onto and somewhere to click to select the page.
      rendered = ConstrainedBox(
        constraints: BoxConstraints(minHeight: _minHeight),
        child: rendered,
      );
    }

    Widget build(bool dropping) {
      // Selection is a tap on the node itself; the gesture sits outside the
      // rendered widget so a bound action in the document does not fire while
      // editing.
      final Widget selectable = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _select(node.id),
        child: _DVStudioNodeChrome(
          id: node.id,
          label: label,
          icon: icon,
          selected: controller.selectedId == node.id,
          dropping: dropping,
          hovered: _hovered,
          child: rendered,
        ),
      );
      if (root) return selectable;
      // Existing nodes are draggable so they can be reparented. Not the page:
      // there is nowhere for it to go.
      return Draggable<String>(
        data: node.id,
        feedback: _dvStudioDragChip(icon, label),
        childWhenDragging: Opacity(opacity: 0.4, child: selectable),
        child: selectable,
      );
    }

    if (!isContainer) return build(false);
    return DragTarget<Object>(
      onWillAcceptWithDetails: (DragTargetDetails<Object> details) =>
          details.data is DVStudioPaletteItem ||
          (details.data is String && details.data != node.id),
      onAcceptWithDetails: (DragTargetDetails<Object> details) {
        final Object data = details.data;
        try {
          if (data is DVStudioPaletteItem) {
            controller.insert(data.create(), parent: node.id);
          } else if (data is String) {
            // A drop into the node's own subtree is rejected by the editor;
            // swallowing it keeps a mis-drop from throwing into the gesture
            // system.
            controller.move(data, parent: node.id);
          }
        } on ArgumentError {
          return;
        } on StateError {
          return;
        }
      },
      builder: (BuildContext context, List<Object?> candidate,
              List<dynamic> _) =>
          build(candidate.isNotEmpty),
    );
  }

  Widget _buildContainer(DVPageNode node) {
    // A stack's children name where they sit, the same way they do when the
    // page runs. Without it a screen of hand-placed elements is a heap in the
    // corner of the canvas and a design once it ships.
    final bool places = node.layout == 'stack';
    final List<Widget> children = <Widget>[
      for (final DVPageNode child in node.children)
        places
            ? dvStudioPlace(child.properties, _buildNode(child))
            : _buildNode(child),
    ];

    // Drawn by the same two functions the page uses. This used to be a third
    // switch over the layout name and nothing else -- no padding, no
    // background, no radius, no spacing, no alignment -- so a card was a bare
    // column while somebody was styling it and a card once the page ran, and
    // the person styling it could not see what they were doing.
    //
    // The styling travels and the behaviour does not: a canvas that navigates
    // away when somebody taps the card they are editing is worse than one
    // that shows the card unstyled.
    return dvStudioStyled(
      node,
      dvStudioLayoutBox(node, children),
      withAction: false,
    );
  }
}

/// The workspace's dot grid.
class _DVStudioDotGrid extends CustomPainter {
  const _DVStudioDotGrid();

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = const Color(0xFFD7D7E2);
    for (double y = 10; y < size.height; y += 20) {
      for (double x = 10; x < size.width; x += 20) {
        canvas.drawCircle(Offset(x, y), 0.9, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DVStudioDotGrid oldDelegate) => false;
}

/// Selection, hover and drop affordances drawn over a node without changing
/// how it lays out.
///
/// The same widget structure whether or not anything is drawn, so hovering or
/// selecting a node never remounts what it renders — an image does not reload
/// because the pointer crossed it.
class _DVStudioNodeChrome extends StatelessWidget {
  final String id;
  final String label;
  final IconData icon;
  final bool selected;
  final bool dropping;
  final ValueNotifier<String?> hovered;
  final Widget child;

  const _DVStudioNodeChrome({
    required this.id,
    required this.label,
    required this.icon,
    required this.selected,
    required this.dropping,
    required this.hovered,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      // Opaque, the default, so only the innermost node under the pointer is
      // hovered: a text inside a card outlines the text, not the card as well.
      onEnter: (_) => hovered.value = id,
      onExit: (_) {
        if (hovered.value == id) hovered.value = null;
      },
      child: Stack(
        // Passthrough, so the node is laid out exactly as it would be without
        // the chrome: a stretched child in a column stays stretched.
        fit: StackFit.passthrough,
        clipBehavior: Clip.none,
        children: <Widget>[
          child,
          Positioned.fill(
            child: IgnorePointer(
              child: ValueListenableBuilder<String?>(
                valueListenable: hovered,
                builder: (BuildContext context, String? hoveredId, Widget? _) {
                  final bool hover = hoveredId == id && !selected;
                  if (!selected && !hover && !dropping) {
                    return const SizedBox.shrink();
                  }
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      color: dropping
                          ? DVStudioStyle.accent.withValues(alpha: 0.08)
                          : null,
                      border: Border.all(
                        color: selected || dropping
                            ? DVStudioStyle.accent
                            : DVStudioStyle.accent.withValues(alpha: 0.45),
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          if (selected) ...<Widget>[
            Positioned(
              left: -1,
              top: -20,
              child: IgnorePointer(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: DVStudioStyle.accent,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(icon, size: 11, color: const Color(0xFFFFFFFF)),
                      const SizedBox(width: 4),
                      DVText(label).modifier(
                        const DVModifier()
                            .fontSize(11)
                            .color(const Color(0xFFFFFFFF))
                            .fontWeight(FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            for (final Alignment corner in const <Alignment>[
              Alignment.topLeft,
              Alignment.topRight,
              Alignment.bottomLeft,
              Alignment.bottomRight,
            ])
              Positioned(
                left: corner.x < 0 ? -3.5 : null,
                right: corner.x > 0 ? -3.5 : null,
                top: corner.y < 0 ? -3.5 : null,
                bottom: corner.y > 0 ? -3.5 : null,
                child: IgnorePointer(
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: DVStudioStyle.surface,
                      border: Border.all(color: DVStudioStyle.accent),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// --- inspector ------------------------------------------------------------------

/// The properties that lay out a group, in the order the inspector draws
/// them. A name listed here that the property table no longer has is skipped;
/// a property in the table that is listed nowhere lands in "Other".
const List<(String, List<String>)> _dvStudioGroupLayout =
    <(String, List<String>)>[
  ('Size & spacing', <String>[
    'width',
    'height',
    'margin',
    'padding',
    'paddingTop',
    'paddingRight',
    'paddingBottom',
    'paddingLeft',
  ]),
  ('Typography', <String>[
    'fontFamily',
    'fontSize',
    'fontWeight',
    'lineHeight',
    'letterSpacing',
    'color',
    'maxLines',
    'overflow',
  ]),
  ('Fill', <String>[
    'backgroundColor',
    'gradientFrom',
    'gradientTo',
    'gradientAngle',
  ]),
  ('Border', <String>[
    'borderWidth',
    'borderColor',
    'borderTopWidth',
    'borderRightWidth',
    'borderBottomWidth',
    'borderLeftWidth',
    'rounded',
    'roundedTopLeft',
    'roundedTopRight',
    'roundedBottomLeft',
    'roundedBottomRight',
  ]),
  ('Effects', <String>[
    'opacity',
    'rotation',
    'shadowColor',
    'shadowX',
    'shadowY',
    'shadowBlur',
    'shadowSpread',
    'blur',
    'backdropBlur',
    'clip',
  ]),
];

/// Which properties the inspector offers for [node], grouped and ordered the
/// way it draws them.
///
/// Generated against `dvStudioProperties` and `dvStudioLayoutProperties`
/// rather than written out: the inspector used to be one flat list of the
/// property table, so nothing in the table could be missing from it, and
/// grouping must not change that. A property no group names is placed in
/// "Other" instead of vanishing.
List<(String, List<String>)> dvStudioInspectorGroupsFor(DVPageNode node) {
  final Set<String> known = <String>{
    for (final DVStudioProperty property in dvStudioProperties) property.name,
  };
  final Set<String> placed = <String>{};
  final List<(String, List<String>)> groups = <(String, List<String>)>[];

  void add(String label, Iterable<String> names) {
    final List<String> kept = <String>[
      for (final String name in names)
        if (placed.add(name)) name,
    ];
    if (kept.isNotEmpty) groups.add((label, kept));
  }

  switch (node.type) {
    case 'text' || 'button':
      add('Content', <String>['text']);
    case 'image':
      add('Content', <String>['src', 'alt', 'fit']);
  }

  final bool isBox = dvStudioLeafTypeFor(node) == null;
  add('Layout', <String>[
    if (isBox)
      for (final DVStudioLayoutProperty property in dvStudioLayoutProperties)
        if (property.appliesTo(node.layout)) property.name,
    if (known.contains('align')) 'align',
  ]);

  final bool isText = node.type == 'text' || node.type == 'button';
  final List<(String, List<String>)> ordered = isText
      ? <(String, List<String>)>[
          _dvStudioGroupLayout[1],
          _dvStudioGroupLayout[0],
          ..._dvStudioGroupLayout.skip(2),
        ]
      : _dvStudioGroupLayout;
  for (final (String label, List<String> names) in ordered) {
    add(label, names.where(known.contains));
  }

  add('Other', <String>[
    for (final DVStudioProperty property in dvStudioProperties)
      if (!placed.contains(property.name)) property.name,
  ]);
  return groups;
}

/// Short labels for a pair of fields drawn on one row.
const Map<String, String> _dvStudioShortLabels = <String, String>{
  'width': 'W',
  'height': 'H',
  'paddingTop': 'T',
  'paddingRight': 'R',
  'paddingBottom': 'B',
  'paddingLeft': 'L',
  'borderTopWidth': 'T',
  'borderRightWidth': 'R',
  'borderBottomWidth': 'B',
  'borderLeftWidth': 'L',
  'roundedTopLeft': 'TL',
  'roundedTopRight': 'TR',
  'roundedBottomLeft': 'BL',
  'roundedBottomRight': 'BR',
  'shadowX': 'X',
  'shadowY': 'Y',
  'shadowBlur': 'B',
  'shadowSpread': 'S',
};

/// Fields that share a row, and what the row is called.
const Map<(String, String), String> _dvStudioPairs = <(String, String), String>{
  ('width', 'height'): 'Size',
  ('paddingTop', 'paddingRight'): 'Sides',
  ('paddingBottom', 'paddingLeft'): '',
  ('borderTopWidth', 'borderRightWidth'): 'Sides',
  ('borderBottomWidth', 'borderLeftWidth'): '',
  ('roundedTopLeft', 'roundedTopRight'): 'Corners',
  ('roundedBottomLeft', 'roundedBottomRight'): '',
  ('shadowX', 'shadowY'): 'Offset',
  ('shadowBlur', 'shadowSpread'): '',
};

const Map<String, String> _dvStudioLabels = <String, String>{
  'text': 'Text',
  'src': 'Source',
  'alt': 'Alt text',
  'fit': 'Fit',
  'spacing': 'Gap',
  'mainAxis': 'Distribute',
  'crossAxis': 'Align',
  'scroll': 'Scrolls',
  'columns': 'Columns',
  'align': 'Position',
  'margin': 'Margin',
  'padding': 'Padding',
  'fontFamily': 'Font',
  'fontSize': 'Size',
  'fontWeight': 'Weight',
  'lineHeight': 'Line height',
  'letterSpacing': 'Letters',
  'color': 'Colour',
  'maxLines': 'Max lines',
  'overflow': 'Overflow',
  'backgroundColor': 'Background',
  'gradientFrom': 'From',
  'gradientTo': 'To',
  'gradientAngle': 'Angle',
  'borderWidth': 'Width',
  'borderColor': 'Colour',
  'rounded': 'Radius',
  'opacity': 'Opacity',
  'rotation': 'Rotation',
  'shadowColor': 'Shadow',
  'blur': 'Blur',
  'backdropBlur': 'Backdrop',
  'clip': 'Clip content',
};

const Map<String, String> _dvStudioUnits = <String, String>{
  'spacing': 'px',
  'width': 'px',
  'height': 'px',
  'margin': 'px',
  'padding': 'px',
  'paddingTop': 'px',
  'paddingRight': 'px',
  'paddingBottom': 'px',
  'paddingLeft': 'px',
  'fontSize': 'px',
  'letterSpacing': 'px',
  'lineHeight': '×',
  'gradientAngle': '°',
  'borderWidth': 'px',
  'borderTopWidth': 'px',
  'borderRightWidth': 'px',
  'borderBottomWidth': 'px',
  'borderLeftWidth': 'px',
  'rounded': 'px',
  'roundedTopLeft': 'px',
  'roundedTopRight': 'px',
  'roundedBottomLeft': 'px',
  'roundedBottomRight': 'px',
  'rotation': '°',
  'shadowX': 'px',
  'shadowY': 'px',
  'shadowBlur': 'px',
  'shadowSpread': 'px',
  'blur': 'px',
  'backdropBlur': 'px',
};

/// Edits the selected node's properties.
class DVStudioInspector extends StatelessWidget {
  final DVStudioEditorController controller;

  const DVStudioInspector({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) {
        final DVPageNode? node = controller.selectedNode;
        if (node == null) {
          return DVStudioStyle.emptyState(
            icon: Icons.touch_app_outlined,
            title: 'Nothing selected',
            message: 'Select an element on the canvas or in Layers to edit '
                'how it looks and behaves.',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _header(node),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (final (String label, List<String> names)
                        in dvStudioInspectorGroupsFor(node))
                      _DVStudioInspectorGroup(
                        key: ValueKey<String>(
                            'dv-studio-inspector-group-$label'),
                        label: label,
                        children: _fields(node, names),
                      ),
                    _DVStudioInspectorGroup(
                      key: const ValueKey<String>(
                          'dv-studio-inspector-group-Interaction'),
                      label: 'Interaction',
                      children: <Widget>[
                        _row(
                          'Navigate to',
                          DVStudioTextInput(
                            key: ValueKey<String>(
                                'dv-studio-inspector-${node.id}-action'),
                            icon: DVStudioIcons.link,
                            placeholder: '/route',
                            value: '${node.action?['to'] ?? ''}',
                            onChanged: (String value) => _guard(() =>
                                controller.setAction(
                                  node.id,
                                  value.trim().isEmpty
                                      ? null
                                      : <String, Object?>{
                                          'type': 'navigate',
                                          'to': value.trim(),
                                        },
                                )),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Runs an edit, ignoring a read-only refusal: a viewer's inspector shows
  /// the values and changes nothing, rather than throwing on each keystroke.
  static void _guard(VoidCallback edit) {
    try {
      edit();
    } on StateError {
      return;
    }
  }

  Widget _header(DVPageNode node) {
    final bool isRoot = node.id == controller.document.root.id;
    final String shortId =
        node.id.length > 6 ? node.id.substring(0, 6) : node.id;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: DVStudioStyle.line)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: DVStudioStyle.accentSoft,
              borderRadius: BorderRadius.circular(DVStudioStyle.radius),
            ),
            child: Icon(
              isRoot
                  ? DVStudioIcons.page
                  : DVStudioIcons.forNode(node.type, node.layout),
              size: 17,
              color: DVStudioStyle.accent,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                DVStudioStyle.heading(
                    _dvStudioNodeLabel(node, controller.document)),
                const SizedBox(height: 3),
                // Flexible, so a narrow inspector wraps the id under the badge
                // rather than pushing it past the edge.
                Row(
                  children: <Widget>[
                    Flexible(
                      child: DVStudioStyle.badge(node.type,
                          tone: DVStudioStyle.muted),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: DVStudioStyle.caption('#$shortId',
                          color: DVStudioStyle.faint),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (!isRoot)
            DVStudioIconButton(
              icon: DVStudioIcons.delete,
              tooltip: 'Delete element',
              onTap: () => _guard(() => controller.remove(node.id)),
            ),
        ],
      ),
    );
  }

  /// A label and its control: side by side where there is room, the label
  /// above the control where there is not.
  ///
  /// A fixed label column beside the control leaves the control a few pixels
  /// in a narrow panel, which is an overflow rather than a small field — and a
  /// panel is as wide as whatever shell hosts it decides.
  Widget _row(String label, Widget control) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth >= 220) {
          return Row(
            children: <Widget>[
              SizedBox(width: 78, child: DVStudioStyle.caption(label)),
              Expanded(child: control),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (label.isNotEmpty) ...<Widget>[
              DVStudioStyle.caption(label),
              const SizedBox(height: 4),
            ],
            control,
          ],
        );
      },
    );
  }

  List<Widget> _fields(DVPageNode node, List<String> names) {
    final List<Widget> rows = <Widget>[];
    for (int i = 0; i < names.length; i++) {
      final String name = names[i];
      final String? next = i + 1 < names.length ? names[i + 1] : null;
      final String? pairLabel =
          next == null ? null : _dvStudioPairs[(name, next)];
      if (pairLabel != null && next != null) {
        final Widget first = _control(node, name, compact: true);
        final Widget second = _control(node, next, compact: true);
        rows.add(_row(
          pairLabel,
          // Side by side where each half has room for its short label and a
          // few digits; one above the other where it does not.
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) =>
                constraints.maxWidth >= 150
                    ? Row(
                        children: <Widget>[
                          Expanded(child: first),
                          const SizedBox(width: 6),
                          Expanded(child: second),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          first,
                          const SizedBox(height: 6),
                          second,
                        ],
                      ),
          ),
        ));
        i++;
        continue;
      }
      rows.add(_row(
        _dvStudioLabels[name] ?? _dvStudioHumanise(name),
        _control(node, name),
      ));
    }
    return rows;
  }

  /// The control for one property, keyed `dv-studio-inspector-<id>-<name>`.
  Widget _control(DVPageNode node, String name, {bool compact = false}) {
    final Key key = ValueKey<String>('dv-studio-inspector-${node.id}-$name');
    final Object? value = node.properties[name];
    void set(Object? next) =>
        _guard(() => controller.setProperty(node.id, name, next));

    // Node content, which is not in the property tables.
    if (name == 'text' || name == 'src' || name == 'alt') {
      return DVStudioTextInput(
        key: key,
        value: '${value ?? ''}',
        placeholder: name == 'src' ? 'https://… or assets/…' : null,
        onChanged: (String text) => name == 'text'
            ? set(text)
            : set(text.trim().isEmpty ? null : text.trim()),
      );
    }
    if (name == 'fit') {
      return _DVStudioInspectorSelect(
        key: key,
        value: value is String ? value : null,
        options: dvStudioImageFits,
        onChanged: set,
      );
    }

    DVStudioPropertyKind? kind;
    List<String> choices = const <String>[];
    DVStudioProperty? property;
    for (final DVStudioProperty candidate in dvStudioProperties) {
      if (candidate.name == name) {
        property = candidate;
        kind = candidate.kind;
        choices = candidate.choices;
        break;
      }
    }
    if (property == null) {
      for (final DVStudioLayoutProperty candidate
          in dvStudioLayoutProperties) {
        if (candidate.name == name) {
          kind = candidate.kind;
          choices = candidate.choices;
          break;
        }
      }
    }

    switch (kind) {
      case DVStudioPropertyKind.number:
        return DVStudioTextInput(
          key: key,
          label: compact ? _dvStudioShortLabels[name] : null,
          value: value == null ? '' : '$value',
          placeholder: compact ? null : '—',
          suffix: compact ? null : _dvStudioUnits[name],
          onChanged: (String text) {
            final String trimmed = text.trim();
            if (trimmed.isEmpty) return set(null);
            final num? parsed = num.tryParse(trimmed);
            // Half-typed — "1." on the way to "1.5" — is left alone rather
            // than clearing the property under the caret.
            if (parsed != null) set(parsed);
          },
        );
      case DVStudioPropertyKind.colour:
        final Color? colour = parseDocumentColor(value);
        return Row(
          key: key,
          children: <Widget>[
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: colour ?? DVStudioStyle.surface,
                border: Border.all(color: DVStudioStyle.lineStrong),
                borderRadius:
                    BorderRadius.circular(DVStudioStyle.radiusSmall),
              ),
              child: colour == null
                  ? const Icon(Icons.block,
                      size: 13, color: DVStudioStyle.faint)
                  : null,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: DVStudioTextInput(
                value: value == null ? '' : '$value',
                placeholder: '#000000',
                onChanged: (String text) =>
                    set(text.trim().isEmpty ? null : text.trim()),
              ),
            ),
          ],
        );
      case DVStudioPropertyKind.flag:
        return Align(
          alignment: Alignment.centerLeft,
          child: _DVStudioInspectorToggle(
            key: key,
            value: value == true,
            onChanged: (bool on) => set(on ? true : null),
          ),
        );
      case DVStudioPropertyKind.choice:
        final String? current = value is String ? value : null;
        if (name == 'align' && choices.length == 9) {
          return Align(
            alignment: Alignment.centerLeft,
            child: _DVStudioAlignGrid(
              key: key,
              keyPrefix: 'dv-studio-inspector-${node.id}-$name',
              options: choices,
              value: current,
              onChanged: set,
            ),
          );
        }
        final Map<String, IconData>? icons = _dvStudioChoiceIcons(
            name, node.layout);
        if (icons != null && choices.every(icons.containsKey)) {
          return _DVStudioInspectorOptions(
            key: key,
            keyPrefix: 'dv-studio-inspector-${node.id}-$name',
            options: choices,
            icons: icons,
            value: current,
            onChanged: set,
          );
        }
        return _DVStudioInspectorSelect(
          key: key,
          value: current,
          options: choices,
          onChanged: set,
        );
      case DVStudioPropertyKind.text:
      case null:
        return DVStudioTextInput(
          key: key,
          value: value == null ? '' : '$value',
          onChanged: (String text) {
            if (property != null) {
              set(_parseProperty(property, text));
            } else {
              set(text.trim().isEmpty ? null : text.trim());
            }
          },
        );
    }
  }
}

/// Icons for the choices that have an obvious one. A choice with no entry
/// here is offered as a menu, which says its values in words.
Map<String, IconData>? _dvStudioChoiceIcons(String name, String layout) {
  final bool vertical = layout == 'list' || layout == 'single';
  switch (name) {
    case 'mainAxis':
      return vertical
          ? const <String, IconData>{
              'start': Icons.align_vertical_top,
              'center': Icons.align_vertical_center,
              'end': Icons.align_vertical_bottom,
              'spaceBetween': Icons.vertical_distribute,
              'spaceAround': Icons.view_agenda_outlined,
              'spaceEvenly': Icons.format_align_justify,
            }
          : const <String, IconData>{
              'start': Icons.align_horizontal_left,
              'center': Icons.align_horizontal_center,
              'end': Icons.align_horizontal_right,
              'spaceBetween': Icons.horizontal_distribute,
              'spaceAround': Icons.view_week_outlined,
              'spaceEvenly': Icons.format_align_justify,
            };
    case 'crossAxis':
      return vertical
          ? const <String, IconData>{
              'stretch': Icons.open_in_full,
              'start': Icons.align_horizontal_left,
              'center': Icons.align_horizontal_center,
              'end': Icons.align_horizontal_right,
            }
          : const <String, IconData>{
              'stretch': Icons.open_in_full,
              'start': Icons.align_vertical_top,
              'center': Icons.align_vertical_center,
              'end': Icons.align_vertical_bottom,
            };
  }
  return null;
}

/// A collapsible group of inspector fields.
class _DVStudioInspectorGroup extends StatefulWidget {
  final String label;
  final List<Widget> children;

  const _DVStudioInspectorGroup({
    super.key,
    required this.label,
    required this.children,
  });

  @override
  State<_DVStudioInspectorGroup> createState() =>
      _DVStudioInspectorGroupState();
}

class _DVStudioInspectorGroupState extends State<_DVStudioInspectorGroup> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: DVStudioStyle.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 12, _open ? 10 : 12),
              child: Row(
                children: <Widget>[
                  Expanded(child: DVStudioStyle.overline(widget.label)),
                  Icon(
                    _open ? DVStudioIcons.chevronDown : DVStudioIcons.chevronRight,
                    size: 16,
                    color: DVStudioStyle.faint,
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (int i = 0; i < widget.children.length; i++) ...<Widget>[
                    if (i > 0) const SizedBox(height: 8),
                    widget.children[i],
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A choice drawn as a row of options, each keyed `<prefix>-<value>`. Tapping
/// the chosen option again clears it, back to the default.
class _DVStudioInspectorOptions extends StatelessWidget {
  final String keyPrefix;
  final List<String> options;
  final Map<String, IconData> icons;
  final String? value;
  final ValueChanged<String?> onChanged;

  const _DVStudioInspectorOptions({
    super.key,
    required this.keyPrefix,
    required this.options,
    required this.icons,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: DVStudioStyle.canvas,
        borderRadius: BorderRadius.circular(DVStudioStyle.radiusSmall),
      ),
      child: Row(
        children: <Widget>[
          for (final String option in options)
            Expanded(
              child: DVStudioStyle.tooltip(
                _dvStudioHumanise(option),
                GestureDetector(
                  key: ValueKey<String>('$keyPrefix-$option'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(option == value ? null : option),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: option == value
                            ? DVStudioStyle.surface
                            : const Color(0x00000000),
                        borderRadius: BorderRadius.circular(4),
                        boxShadow:
                            option == value ? DVStudioStyle.shadow : null,
                      ),
                      child: Icon(
                        icons[option],
                        size: 15,
                        color: option == value
                            ? DVStudioStyle.ink
                            : DVStudioStyle.muted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Where a node sits in its box, as the nine positions it can take.
class _DVStudioAlignGrid extends StatelessWidget {
  final String keyPrefix;
  final List<String> options;
  final String? value;
  final ValueChanged<String?> onChanged;

  const _DVStudioAlignGrid({
    super.key,
    required this.keyPrefix,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 78,
      height: 78,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: DVStudioStyle.canvas,
        borderRadius: BorderRadius.circular(DVStudioStyle.radiusSmall),
      ),
      child: Column(
        children: <Widget>[
          for (int r = 0; r < 3; r++)
            Expanded(
              child: Row(
                children: <Widget>[
                  for (int c = 0; c < 3; c++)
                    Expanded(child: _cell(options[r * 3 + c])),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _cell(String option) {
    final bool active = option == value;
    return DVStudioStyle.tooltip(
      _dvStudioHumanise(option),
      GestureDetector(
        key: ValueKey<String>('$keyPrefix-$option'),
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(active ? null : option),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Center(
            child: Container(
              width: active ? 9 : 5,
              height: active ? 9 : 5,
              decoration: BoxDecoration(
                color: active ? DVStudioStyle.accent : DVStudioStyle.faint,
                borderRadius: BorderRadius.circular(active ? 2 : 999),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A switch for a flag property.
class _DVStudioInspectorToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _DVStudioInspectorToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 34,
          height: 20,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: value ? DVStudioStyle.accent : DVStudioStyle.lineStrong,
            borderRadius: BorderRadius.circular(999),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 120),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 16,
              height: 16,
              decoration: const BoxDecoration(
                color: DVStudioStyle.surface,
                shape: BoxShape.circle,
                boxShadow: DVStudioStyle.shadow,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A choice with more values than fit a row, opened as a menu.
class _DVStudioInspectorSelect extends StatelessWidget {
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  const _DVStudioInspectorSelect({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  Future<void> _open(BuildContext context) async {
    final RenderObject? box = context.findRenderObject();
    final OverlayState? overlay = Overlay.maybeOf(context);
    final RenderObject? overlayBox = overlay?.context.findRenderObject();
    if (box is! RenderBox || overlayBox is! RenderBox) return;
    final Offset origin = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    final String? picked = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        origin & box.size,
        Offset.zero & overlayBox.size,
      ),
      items: <PopupMenuItem<String>>[
        const PopupMenuItem<String>(value: '', child: Text('Default')),
        for (final String option in options)
          PopupMenuItem<String>(
            value: option,
            child: Text(_dvStudioHumanise(option)),
          ),
      ],
    );
    if (picked == null) return;
    onChanged(picked.isEmpty ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => unawaited(_open(context)),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: DVStudioStyle.surface,
            border: Border.all(color: DVStudioStyle.lineStrong),
            borderRadius: BorderRadius.circular(DVStudioStyle.radiusSmall),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: DVStudioStyle.body(
                  value == null ? 'Default' : _dvStudioHumanise(value!),
                  color: value == null ? DVStudioStyle.faint : DVStudioStyle.ink,
                ),
              ),
              const Icon(DVStudioIcons.chevronDown,
                  size: 16, color: DVStudioStyle.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Turns what was typed into the value the renderer expects.
///
/// An empty field clears the property rather than storing an empty string,
/// so deleting a value removes the styling instead of leaving one the
/// renderer silently ignores.
Object? _parseProperty(DVStudioProperty property, String input) {
  final text = input.trim();
  if (text.isEmpty) return null;
  return switch (property.kind) {
    DVStudioPropertyKind.number => num.tryParse(text),
    DVStudioPropertyKind.flag => text.toLowerCase() == 'true',
    DVStudioPropertyKind.colour ||
    DVStudioPropertyKind.choice ||
    DVStudioPropertyKind.text =>
      text,
  };
}
