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

  DVStudioEditorController(DVPageDocument document, {this.historyLimit = 100})
      : _document = document;

  DVPageDocument get document => _document;

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
    select(node.id);
  }

  /// Reparents a node. This is a drag between containers.
  void move(String id, {required String parent, int? index}) {
    _mutate((DVPageDocumentEditor editor) {
      editor.move(id, parent: parent, index: index);
    });
  }

  /// Replaces a node. This is the property inspector.
  void update(String id, DVPageNode Function(DVPageNode node) transform) {
    _mutate((DVPageDocumentEditor editor) {
      editor.update(id, transform);
    });
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
    if (_selectedId == id) _selectedId = null;
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_document.toJson());
    _document = DVPageDocument.fromJson(_undo.removeLast());
    _dropDanglingSelection();
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_document.toJson());
    _document = DVPageDocument.fromJson(_redo.removeLast());
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

  /// Persists the document, which publishes it.
  Future<void> save() => const DVPageStore().save(_document);
}

/// What the palette drags and the canvas accepts.
///
/// A factory rather than a node, so each drop creates a fresh node with its
/// own id instead of dropping the same one repeatedly.
class DVStudioPaletteItem {
  final String label;
  final DVPageNode Function() create;

  const DVStudioPaletteItem({required this.label, required this.create});

  /// The default palette: the primitives a Dartvel page is built from.
  static List<DVStudioPaletteItem> get defaults => <DVStudioPaletteItem>[
        DVStudioPaletteItem(
          label: 'Text',
          create: () => DVPageNode.text('Text'),
        ),
        DVStudioPaletteItem(
          label: 'Column',
          create: () => DVPageNode.box(),
        ),
        DVStudioPaletteItem(
          label: 'Row',
          create: () => DVPageNode.box(layout: 'row'),
        ),
        DVStudioPaletteItem(
          label: 'Grid',
          create: () => DVPageNode.box(layout: 'grid'),
        ),
        DVStudioPaletteItem(
          label: 'Image',
          create: () => DVPageNode.image('https://example.com/image.png'),
        ),
      ];
}

/// The draggable source list.
class DVStudioPalette extends StatelessWidget {
  final List<DVStudioPaletteItem> items;

  const DVStudioPalette({super.key, this.items = const <DVStudioPaletteItem>[]});

  @override
  Widget build(BuildContext context) {
    final entries = items.isEmpty ? DVStudioPaletteItem.defaults : items;
    return DVBox.list(<Widget>[
      for (final item in entries)
        Draggable<DVStudioPaletteItem>(
          data: item,
          feedback: DVText(item.label),
          child: DVText(item.label),
        ),
    ]);
  }
}

/// The editing canvas.
///
/// Renders the document as the real widgets it describes — the same
/// [DVPageDocumentRenderer] output the running app shows — with selection and
/// drop targets layered over it. What is edited is what ships.
class DVStudioCanvas extends StatefulWidget {
  final DVStudioEditorController controller;

  const DVStudioCanvas({super.key, required this.controller});

  @override
  State<DVStudioCanvas> createState() => _DVStudioCanvasState();
}

class _DVStudioCanvasState extends State<DVStudioCanvas> {
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
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) =>
      _buildNode(widget.controller.document.root);

  Widget _buildNode(DVPageNode node) {
    final isContainer = node.type == 'box';
    final rendered = isContainer
        ? _buildContainer(node)
        : DVPageDocumentRenderer(
            DVPageDocument(route: '', root: node),
          );

    // Selection is a tap on the node itself; the gesture sits outside the
    // rendered widget so a bound action in the document does not fire while
    // editing.
    final selectable = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.controller.select(node.id),
      child: _DVStudioSelection(
        selected: widget.controller.selectedId == node.id,
        child: rendered,
      ),
    );

    // Existing nodes are draggable so they can be reparented; containers are
    // also drop targets.
    final draggable = Draggable<String>(
      data: node.id,
      feedback: DVText(node.type),
      childWhenDragging: Opacity(opacity: 0.4, child: selectable),
      child: selectable,
    );

    if (!isContainer) return draggable;
    return DragTarget<Object>(
      onWillAcceptWithDetails: (DragTargetDetails<Object> details) =>
          details.data is DVStudioPaletteItem ||
          (details.data is String && details.data != node.id),
      onAcceptWithDetails: (DragTargetDetails<Object> details) {
        final data = details.data;
        if (data is DVStudioPaletteItem) {
          widget.controller.insert(data.create(), parent: node.id);
        } else if (data is String) {
          // A drop into the node's own subtree is rejected by the editor;
          // swallowing it keeps a mis-drop from throwing into the gesture
          // system.
          try {
            widget.controller.move(data, parent: node.id);
          } on ArgumentError {
            return;
          }
        }
      },
      builder: (BuildContext context, List<Object?> candidate, List<dynamic> _) =>
          draggable,
    );
  }

  Widget _buildContainer(DVPageNode node) {
    final children = <Widget>[
      for (final child in node.children) _buildNode(child),
    ];
    return switch (node.layout) {
      'row' => DVBox.row(children),
      'grid' => DVBox.grid(
          children,
          columns: (node.properties['columns'] as num?)?.toInt() ?? 2,
        ),
      'stack' => DVBox.stack(children),
      _ => DVBox.list(children),
    };
  }
}

/// Draws the selection affordance around a node.
class _DVStudioSelection extends StatelessWidget {
  final bool selected;
  final Widget child;

  const _DVStudioSelection({required this.selected, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!selected) return child;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF6C4BF4), width: 2),
      ),
      child: child,
    );
  }
}

/// Edits the selected node's properties.
class DVStudioInspector extends StatelessWidget {
  final DVStudioEditorController controller;

  const DVStudioInspector({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) {
        final node = controller.selectedNode;
        if (node == null) return const DVText('Nothing selected');
        return DVBox.list(<Widget>[
          DVText('${node.type} (${node.layout})'),
          if (node.type == 'text')
            _DVStudioField(
              label: 'text',
              value: '${node.properties['text'] ?? ''}',
              onChanged: (String value) =>
                  controller.setProperty(node.id, 'text', value),
            ),
          if (node.type == 'image')
            _DVStudioField(
              label: 'src',
              value: '${node.properties['src'] ?? ''}',
              onChanged: (String value) =>
                  controller.setProperty(node.id, 'src', value),
            ),
          // Rendered from dvStudioProperties, the same list the renderer
          // applies, so the inspector cannot offer a control the page ignores
          // or omit one it honours.
          for (final property in dvStudioProperties)
            _DVStudioField(
              label: property.name,
              hint: property.choices.isEmpty
                  ? null
                  : property.choices.join(' / '),
              value: '${node.properties[property.name] ?? ''}',
              onChanged: (String value) => controller.setProperty(
                node.id,
                property.name,
                _parseProperty(property, value),
              ),
            ),
          _DVStudioField(
            label: 'navigate to',
            value: '${node.action?['to'] ?? ''}',
            onChanged: (String value) => controller.setAction(
              node.id,
              value.isEmpty
                  ? null
                  : <String, Object?>{'type': 'navigate', 'to': value},
            ),
          ),
        ]).scrollable();
      },
    );
  }
}

class _DVStudioField extends StatelessWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  /// Accepted values, shown beneath the field. Kept out of the label because
  /// an unbounded label overflows the inspector row.
  final String? hint;

  const _DVStudioField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final field = DVBox.row(<Widget>[
      Flexible(child: DVText(label)),
      Expanded(
        child: EditableText(
          key: ValueKey<String>('dv-studio-field-$label-$value'),
          controller: TextEditingController(text: value),
          focusNode: FocusNode(),
          style: const TextStyle(fontSize: 14, color: Color(0xFF111111)),
          cursorColor: const Color(0xFF6C4BF4),
          backgroundCursorColor: const Color(0xFFCCCCCC),
          onChanged: onChanged,
        ),
      ),
    ]);
    final hintText = hint;
    if (hintText == null) return field;
    return DVBox.list(<Widget>[
      field,
      DVText(hintText).modifier(const DVModifier().fontSize(11)),
    ]);
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
    DVStudioPropertyKind.choice =>
      text,
  };
}
