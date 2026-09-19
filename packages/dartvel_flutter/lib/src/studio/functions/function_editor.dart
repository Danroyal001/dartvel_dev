import 'package:flutter/material.dart';

import '../../../dartvel_flutter.dart';

/// Editing state for one workflow: selection and undo/redo, the same bargain
/// the page editor makes.
class DVWorkflowEditorController extends ChangeNotifier {
  DVWorkflowDocument _document;

  final List<Map<String, Object?>> _undo = <Map<String, Object?>>[];
  final List<Map<String, Object?>> _redo = <Map<String, Object?>>[];

  String? _selectedId;

  final int historyLimit;

  /// Edits [document], saving into [store] -- a database for an app or a
  /// server, the Studio API for the Studio a web-server binary serves.
  DVWorkflowEditorController(
    DVWorkflowDocument document, {
    this.historyLimit = 100,
    DVFunctionStore store = const DVWorkflowStore(),
  })  : _document = document,
        _store = store;

  final DVFunctionStore _store;

  DVWorkflowDocument get document => _document;

  String? get selectedId => _selectedId;

  DVWorkflowStep? get selectedStep =>
      _selectedId == null ? null : _editor.find(_selectedId!);

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  DVWorkflowDocumentEditor get _editor => DVWorkflowDocumentEditor(_document);

  void select(String? id) {
    if (_selectedId == id) return;
    _selectedId = id;
    notifyListeners();
  }

  void _mutate(void Function(DVWorkflowDocumentEditor editor) mutate) {
    final snapshot = _document.toJson();
    mutate(_editor);
    _undo.add(snapshot);
    if (_undo.length > historyLimit) _undo.removeAt(0);
    _redo.clear();
    notifyListeners();
  }

  /// Replaces the document with [next], undoably. Inputs and the result are
  /// the document's own fields, not steps, so they change it whole.
  void _replace(DVWorkflowDocument next) {
    _undo.add(_document.toJson());
    if (_undo.length > historyLimit) _undo.removeAt(0);
    _redo.clear();
    _document = next;
    notifyListeners();
  }

  DVWorkflowDocument _with({
    List<DVWorkflowParameter>? parameters,
    DVWorkflowType? returns,
    bool clearReturns = false,
  }) =>
      DVWorkflowDocument(
        name: _document.name,
        side: _document.side,
        parameters: parameters ?? _document.parameters,
        returns: clearReturns ? null : (returns ?? _document.returns),
        steps: _document.steps,
      );

  /// Adds an input called inputN, as Text: a new input has a type from the
  /// start, so nothing untyped is ever created in the builder.
  void addInput() {
    int n = _document.parameters.length + 1;
    final Set<String> taken = <String>{
      for (final DVWorkflowParameter p in _document.parameters) p.name,
    };
    while (taken.contains('input$n')) {
      n++;
    }
    _replace(_with(parameters: <DVWorkflowParameter>[
      ..._document.parameters,
      DVWorkflowParameter('input$n', DVWorkflowType.text),
    ]));
  }

  void setInput(int index, DVWorkflowParameter input) {
    final List<DVWorkflowParameter> next =
        List<DVWorkflowParameter>.of(_document.parameters);
    next[index] = input;
    _replace(_with(parameters: next));
  }

  void removeInput(int index) {
    final List<DVWorkflowParameter> next =
        List<DVWorkflowParameter>.of(_document.parameters)..removeAt(index);
    _replace(_with(parameters: next));
  }

  /// What the workflow returns, or null for nothing.
  void setReturns(DVWorkflowType? type) =>
      _replace(_with(returns: type, clearReturns: type == null));

  /// Inserts a step. This is a drop from the palette.
  void insert(
    DVWorkflowStep step, {
    String parent = DVWorkflowDocumentEditor.rootParent,
    int? index,
  }) {
    _mutate((DVWorkflowDocumentEditor editor) {
      editor.insert(step, parent: parent, index: index);
    });
    select(step.id);
  }

  /// Reparents a step, including into a condition branch.
  void move(
    String id, {
    String parent = DVWorkflowDocumentEditor.rootParent,
    int? index,
  }) {
    _mutate((DVWorkflowDocumentEditor editor) {
      editor.move(id, parent: parent, index: index);
    });
  }

  void update(
    String id,
    DVWorkflowStep Function(DVWorkflowStep step) transform,
  ) {
    _mutate((DVWorkflowDocumentEditor editor) {
      editor.update(id, transform);
    });
  }

  void remove(String id) {
    _mutate((DVWorkflowDocumentEditor editor) {
      editor.remove(id);
    });
    if (_selectedId == id) _selectedId = null;
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_document.toJson());
    _document = DVWorkflowDocument.fromJson(_undo.removeLast());
    _dropDanglingSelection();
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_document.toJson());
    _document = DVWorkflowDocument.fromJson(_redo.removeLast());
    _dropDanglingSelection();
    notifyListeners();
  }

  void _dropDanglingSelection() {
    if (_selectedId != null && _editor.find(_selectedId!) == null) {
      _selectedId = null;
    }
  }

  /// Persists the workflow, which publishes it.
  Future<void> save() => _store.save(_document);

  /// The Dart this workflow exports to — the view-code panel.
  String viewCode() => _document.toDartSource();
}

/// A step type the palette can drop.
class DVWorkflowPaletteItem {
  final String label;
  final DVWorkflowStep Function() create;

  const DVWorkflowPaletteItem({required this.label, required this.create});

  static List<DVWorkflowPaletteItem> get defaults =>
      <DVWorkflowPaletteItem>[
        DVWorkflowPaletteItem(
          label: 'Call',
          create: () => DVWorkflowStep.call(''),
        ),
        DVWorkflowPaletteItem(
          label: 'Set',
          create: () => DVWorkflowStep.set(
            'value',
            const DVWorkflowValue.literal(''),
          ),
        ),
        DVWorkflowPaletteItem(
          label: 'Condition',
          create: () => DVWorkflowStep.condition(
            const DVWorkflowValue.literal(true),
          ),
        ),
        DVWorkflowPaletteItem(
          label: 'Return',
          create: () =>
              DVWorkflowStep.returns(const DVWorkflowValue.literal('')),
        ),
      ];
}

/// How a kind of step looks: the word on its card, its glyph and its colour.
///
/// One table, read by the palette, the canvas and the inspector, so a
/// condition is the same amber diamond everywhere it appears.
class _DVWorkflowKind {
  final String label;
  final String title;
  final String hint;
  final IconData icon;
  final Color tone;

  const _DVWorkflowKind(this.label, this.title, this.hint, this.icon, this.tone);

  static const _DVWorkflowKind call = _DVWorkflowKind('CALL', 'Call',
      'Run a backend function', Icons.bolt_outlined, DVStudioStyle.accent);
  static const _DVWorkflowKind set = _DVWorkflowKind('SET', 'Set',
      'Keep a value for later', Icons.data_object, Color(0xFF0F9BA8));
  static const _DVWorkflowKind condition = _DVWorkflowKind(
      'CONDITION',
      'Condition',
      'Branch on a value',
      Icons.call_split,
      DVStudioStyle.warning);
  static const _DVWorkflowKind returns = _DVWorkflowKind('RETURN', 'Return',
      'Finish with a result', Icons.keyboard_return, DVStudioStyle.success);

  static _DVWorkflowKind of(String type) => switch (type) {
        'call' => call,
        'set' => set,
        'condition' => condition,
        'return' => returns,
        _ => _DVWorkflowKind(type.toUpperCase(), type, 'A custom step',
            Icons.circle_outlined, DVStudioStyle.muted),
      };
}

/// The draggable step palette, as insert tiles.
class DVWorkflowPalette extends StatelessWidget {
  final List<DVWorkflowPaletteItem> items;

  const DVWorkflowPalette({
    super.key,
    this.items = const <DVWorkflowPaletteItem>[],
  });

  @override
  Widget build(BuildContext context) {
    final List<DVWorkflowPaletteItem> entries =
        items.isEmpty ? DVWorkflowPaletteItem.defaults : items;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Two up where the pane is wide enough for two readable tiles, one
        // up where it is not: a narrow pane is a pane beside a canvas that
        // needs the room more.
        final bool twoUp = constraints.maxWidth >= 200;
        final List<Widget> tiles = <Widget>[
          for (final DVWorkflowPaletteItem item in entries) _tile(item),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            DVStudioStyle.overline('Steps'),
            const SizedBox(height: DVStudioStyle.space3),
            if (twoUp)
              for (int i = 0; i < tiles.length; i += 2)
                Padding(
                  padding: const EdgeInsets.only(bottom: DVStudioStyle.space2),
                  child: Row(
                    children: <Widget>[
                      Expanded(child: tiles[i]),
                      const SizedBox(width: DVStudioStyle.space2),
                      Expanded(
                        child: i + 1 < tiles.length
                            ? tiles[i + 1]
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                )
            else
              for (final Widget tile in tiles)
                Padding(
                  padding: const EdgeInsets.only(bottom: DVStudioStyle.space2),
                  child: tile,
                ),
          ],
        );
      },
    );
  }

  Widget _tile(DVWorkflowPaletteItem item) {
    final _DVWorkflowKind kind =
        _DVWorkflowKind.of(item.label.toLowerCase().trim());
    final Widget face = _DVWorkflowTile(label: item.label, kind: kind);
    return Draggable<DVWorkflowPaletteItem>(
      data: item,
      feedback: DVStudioSurface(
        color: const Color(0x00000000),
        child: SizedBox(
          width: 160,
          child: _DVWorkflowTile(label: item.label, kind: kind, lifted: true),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.45, child: face),
      child: DVStudioStyle.tooltip(
        kind.hint,
        MouseRegion(cursor: SystemMouseCursors.grab, child: face),
      ),
    );
  }
}

class _DVWorkflowTile extends StatelessWidget {
  final String label;
  final _DVWorkflowKind kind;
  final bool lifted;

  const _DVWorkflowTile({
    required this.label,
    required this.kind,
    this.lifted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: DVStudioStyle.surface,
        border: Border.all(
          color: lifted ? DVStudioStyle.accent : DVStudioStyle.lineStrong,
        ),
        borderRadius: BorderRadius.circular(DVStudioStyle.radius),
        boxShadow: lifted ? DVStudioStyle.shadowLarge : null,
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: kind.tone.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(DVStudioStyle.radiusSmall),
            ),
            child: Icon(kind.icon, size: 13, color: kind.tone),
          ),
          const SizedBox(width: DVStudioStyle.space2),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: DVStudioStyle.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The workflow canvas: steps as cards in execution order on a dot-grid
/// workspace, joined by connectors, with a condition's two branches side by
/// side under it as their own drop targets.
///
/// Top to bottom rather than freely placed, because that is what a workflow
/// document is: an ordered list whose conditions nest lists. A canvas that let
/// cards be dragged anywhere would be drawing positions the document has no
/// field to keep.
class DVWorkflowCanvas extends StatefulWidget {
  final DVWorkflowEditorController controller;

  const DVWorkflowCanvas({super.key, required this.controller});

  @override
  State<DVWorkflowCanvas> createState() => _DVWorkflowCanvasState();
}

class _DVWorkflowCanvasState extends State<DVWorkflowCanvas> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(DVWorkflowCanvas oldWidget) {
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
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        children: <Widget>[
          const Positioned.fill(child: CustomPaint(painter: _DVDotGrid())),
          Positioned.fill(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                vertical: DVStudioStyle.space6,
                horizontal: DVStudioStyle.space4,
              ),
              child: Align(
                alignment: Alignment.topCenter,
                // Scaled down rather than scrolled sideways when a deeply
                // branched workflow is wider than the pane: a sideways scroll
                // view would compete with dragging a card for the same gesture.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topCenter,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _start(),
                      _connector(),
                      _buildBranch(
                        widget.controller.document.steps,
                        DVWorkflowDocumentEditor.rootParent,
                        root: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _start() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: DVStudioStyle.ink,
        borderRadius: BorderRadius.circular(999),
        boxShadow: DVStudioStyle.shadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.play_arrow_rounded,
              size: 14, color: Color(0xFFFFFFFF)),
          const SizedBox(width: 4),
          Text(
            'When ${widget.controller.document.name} runs',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFFFFFFFF),
            ),
          ),
        ],
      ),
    );
  }

  Widget _connector() {
    return SizedBox(
      height: 22,
      child: Column(
        children: <Widget>[
          Expanded(child: Container(width: 2, color: DVStudioStyle.lineStrong)),
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: DVStudioStyle.lineStrong,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBranch(
    List<DVWorkflowStep> steps,
    String parent, {
    bool root = false,
  }) {
    return _DVWorkflowDropZone(
      parent: parent,
      controller: widget.controller,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (int i = 0; i < steps.length; i++) ...<Widget>[
            if (i > 0) _connector(),
            _buildStep(steps[i]),
          ],
          if (steps.isEmpty) _emptyZone(parent, root: root),
        ],
      ),
    );
  }

  Widget _emptyZone(String parent, {required bool root}) {
    return SizedBox(
      width: root ? 280 : 210,
      child: Stack(
        children: <Widget>[
          // The zone's own name — the parent a drop lands in — kept as text
          // of its own, because tooling and tests address a drop zone by it.
          // Drawn invisibly: what a person reads is the sentence beside it,
          // and an id is not something a person should have to read.
          Positioned.fill(
            child: Opacity(
              opacity: 0,
              child: Text(
                'drop here: $parent',
                maxLines: 1,
                overflow: TextOverflow.clip,
              ),
            ),
          ),
          // The full width of the zone's slot. A Stack lays its children out
          // loosely, so without this the box shrank to its sentence and sat
          // against the left edge of a slot twice its width, off-centre under
          // the connector it hangs from.
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              vertical: root ? 26 : 16,
              horizontal: DVStudioStyle.space3,
            ),
            decoration: BoxDecoration(
              color: DVStudioStyle.surface.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(DVStudioStyle.radius),
              border: Border.all(color: DVStudioStyle.lineStrong),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.add_circle_outline,
                    size: 18, color: DVStudioStyle.faint),
                const SizedBox(height: 6),
                const Text(
                  'Drop a step here',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: DVStudioStyle.muted,
                  ),
                ),
                if (root) ...<Widget>[
                  const SizedBox(height: 2),
                  const Text(
                    'Drag one in from Steps',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11.5, color: DVStudioStyle.faint),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep(DVWorkflowStep step) {
    final bool selected = widget.controller.selectedId == step.id;
    final _DVWorkflowKind kind = _DVWorkflowKind.of(step.type);
    final Widget card = _ports(_card(step, kind, selected: selected), kind);

    final Widget tappable = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.controller.select(step.id),
      child: MouseRegion(cursor: SystemMouseCursors.click, child: card),
    );

    final Widget draggable = Draggable<String>(
      data: step.id,
      feedback: DVStudioSurface(
        color: const Color(0x00000000),
        child: Opacity(
          opacity: 0.92,
          child: _card(step, kind, selected: true),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: card),
      child: tappable,
    );

    if (step.type != 'condition') return draggable;
    // A condition's branches are their own drop zones, so a step can be
    // dragged into the arm it belongs to.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        draggable,
        _connector(),
        Container(
          padding: const EdgeInsets.all(DVStudioStyle.space3),
          decoration: BoxDecoration(
            color: DVStudioStyle.surface.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(DVStudioStyle.radiusLarge),
            border: Border.all(color: DVStudioStyle.line),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _arm(step, 'then', DVStudioStyle.success),
              const SizedBox(width: DVStudioStyle.space4),
              _arm(step, 'else', DVStudioStyle.muted),
            ],
          ),
        ),
      ],
    );
  }

  Widget _arm(DVWorkflowStep step, String name, Color tone) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        DVStudioStyle.badge(name, tone: tone),
        const SizedBox(height: DVStudioStyle.space2),
        _buildBranch(
          step.branches[name] ?? const <DVWorkflowStep>[],
          '${step.id}/$name',
        ),
      ],
    );
  }

  Widget _card(
    DVWorkflowStep step,
    _DVWorkflowKind kind, {
    required bool selected,
  }) {
    final String? detail = _detail(step);
    return Container(
      width: 248,
      decoration: BoxDecoration(
        color: DVStudioStyle.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected ? DVStudioStyle.accent : DVStudioStyle.line,
          width: selected ? 2 : 1,
        ),
        boxShadow: selected ? DVStudioStyle.shadowLarge : DVStudioStyle.shadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // The type stripe: which kind of step this is, readable before
              // any of the text on the card is.
              Container(width: 4, color: kind.tone),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 9, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Icon(kind.icon, size: 13, color: kind.tone),
                          const SizedBox(width: 5),
                          Text(
                            kind.label,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                              color: kind.tone,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _label(step),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: DVStudioStyle.ink,
                        ),
                      ),
                      if (detail != null) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, color: DVStudioStyle.muted),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The ports: where a step is entered and where it hands on to the next.
  Widget _ports(Widget card, _DVWorkflowKind kind) {
    Widget port() => Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: DVStudioStyle.surface,
            shape: BoxShape.circle,
            border: Border.all(color: kind.tone, width: 1.5),
          ),
        );
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        card,
        Positioned(top: -4, left: 0, right: 0, child: Center(child: port())),
        Positioned(
            bottom: -4, left: 0, right: 0, child: Center(child: port())),
      ],
    );
  }

  static String? _detail(DVWorkflowStep step) {
    final List<String> parts = <String>[
      if (step.assignTo != null) '→ ${step.assignTo}',
      if (step.arguments.isNotEmpty)
        step.arguments.length == 1
            ? '1 argument'
            : '${step.arguments.length} arguments',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  static String _label(DVWorkflowStep step) => switch (step.type) {
        'call' => 'call ${step.name ?? ''}'.trim(),
        'set' => 'set ${step.name ?? ''}'.trim(),
        'condition' => 'if',
        'return' => 'return',
        _ => step.type,
      };
}

/// The workspace behind the cards: a quiet dot grid, so the canvas reads as a
/// surface things are placed on rather than a blank panel.
class _DVDotGrid extends CustomPainter {
  const _DVDotGrid();

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = const Color(0xFFD3D3DE);
    const double step = 18;
    for (double y = step / 2; y < size.height; y += step) {
      for (double x = step / 2; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), 0.9, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DVDotGrid oldDelegate) => false;
}

class _DVWorkflowDropZone extends StatelessWidget {
  final String parent;
  final DVWorkflowEditorController controller;
  final Widget child;

  const _DVWorkflowDropZone({
    required this.parent,
    required this.controller,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<Object>(
      onWillAcceptWithDetails: (DragTargetDetails<Object> details) =>
          details.data is DVWorkflowPaletteItem || details.data is String,
      onAcceptWithDetails: (DragTargetDetails<Object> details) {
        final data = details.data;
        if (data is DVWorkflowPaletteItem) {
          controller.insert(data.create(), parent: parent);
        } else if (data is String) {
          // Dropping a condition into its own branch is refused by the
          // editor; swallowing it keeps a mis-drop out of the gesture system.
          try {
            controller.move(data, parent: parent);
          } on ArgumentError {
            return;
          }
        }
      },
      builder: (BuildContext context, List<Object?> candidates, List<dynamic> _) {
        if (candidates.isEmpty) return child;
        // Where the step would land, while it is over the spot.
        return DecoratedBox(
          decoration: BoxDecoration(
            color: DVStudioStyle.accentSoft.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(DVStudioStyle.radiusLarge),
            border: Border.all(color: DVStudioStyle.accent, width: 1.5),
          ),
          child: child,
        );
      },
    );
  }
}

/// Edits the selected step: its action, arguments and result variable.
class DVWorkflowInspector extends StatelessWidget {
  final DVWorkflowEditorController controller;

  const DVWorkflowInspector({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) {
        final DVWorkflowStep? step = controller.selectedStep;
        if (step == null) return _DVWorkflowSignature(controller: controller);
        final _DVWorkflowKind kind = _DVWorkflowKind.of(step.type);
        return ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(DVStudioStyle.space4),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: DVStudioStyle.line)),
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: kind.tone.withValues(alpha: 0.12),
                      borderRadius:
                          BorderRadius.circular(DVStudioStyle.radius),
                    ),
                    child: Icon(kind.icon, size: 17, color: kind.tone),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        DVStudioStyle.heading('${kind.title} step'),
                        DVStudioStyle.caption(kind.hint,
                            color: DVStudioStyle.faint),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (step.type == 'call' || step.type == 'set')
              DVStudioStyle.group(
                label: step.type == 'call' ? 'Action' : 'Variable',
                children: <Widget>[
                  _field(
                    step,
                    label: step.type == 'call' ? 'action' : 'variable',
                    value: step.name ?? '',
                    placeholder: step.type == 'call' ? 'sendMail' : 'total',
                    onChanged: (String value) => controller.update(
                      step.id,
                      (DVWorkflowStep s) => s.withName(value),
                    ),
                  ),
                  if (step.type == 'call')
                    _field(
                      step,
                      label: 'assign to',
                      value: step.assignTo ?? '',
                      placeholder: 'result',
                      onChanged: (String value) => controller.update(
                        step.id,
                        (DVWorkflowStep s) =>
                            s.withAssignTo(value.isEmpty ? null : value),
                      ),
                    ),
                ],
              ),
            if (step.arguments.isNotEmpty)
              DVStudioStyle.group(
                label: 'Arguments',
                children: <Widget>[
                  for (final MapEntry<String, DVWorkflowValue> entry
                      in step.arguments.entries)
                    _field(
                      step,
                      label: entry.key,
                      value:
                          '${entry.value.variable ?? entry.value.literal ?? ''}',
                      // A leading $ means "read this variable"; anything else
                      // is the literal, so a value is never accidentally a
                      // reference.
                      onChanged: (String value) => controller.update(
                        step.id,
                        (DVWorkflowStep s) => s.withArgument(
                          entry.key,
                          value.startsWith(r'$')
                              ? DVWorkflowValue.reference(value.substring(1))
                              : DVWorkflowValue.literal(value),
                        ),
                      ),
                    ),
                  DVStudioStyle.caption(
                    r'Start a value with $ to read a variable instead.',
                    color: DVStudioStyle.faint,
                  ),
                ],
              ),
          ],
        );
      },
    );
  }

  Widget _field(
    DVWorkflowStep step, {
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
    String? placeholder,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        DVStudioStyle.caption(label),
        const SizedBox(height: DVStudioStyle.space1),
        // Keyed by the step and the field rather than by the value: keyed by
        // value, every keystroke replaced the field and threw the caret away.
        DVStudioTextInput(
          key: ValueKey<String>('dv-workflow-field-${step.id}-$label'),
          value: value,
          placeholder: placeholder,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// The function itself, shown when no step is selected: what it takes and
/// what it returns, each with a type a site owner picks by name.
class _DVWorkflowSignature extends StatelessWidget {
  const _DVWorkflowSignature({required this.controller});

  final DVWorkflowEditorController controller;

  static const TextStyle _choice = TextStyle(
    fontSize: 13,
    color: DVStudioStyle.ink,
  );

  Widget _box(Widget child) => Container(
    height: 34,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(
      border: Border.all(color: DVStudioStyle.line),
      borderRadius: BorderRadius.circular(DVStudioStyle.radiusSmall),
    ),
    child: DropdownButtonHideUnderline(child: child),
  );

  Widget _input(int index, DVWorkflowParameter input) {
    return Padding(
      key: ValueKey<String>('dv-workflow-input-$index'),
      padding: const EdgeInsets.only(bottom: DVStudioStyle.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: DVStudioTextInput(
                  value: input.name,
                  placeholder: 'name',
                  onChanged: (String name) {
                    final String trimmed = name.trim();
                    if (trimmed.isEmpty || trimmed == input.name) return;
                    controller.setInput(index, input.copyWith(name: trimmed));
                  },
                ),
              ),
              DVStudioIconButton(
                icon: Icons.close,
                tooltip: 'Remove ${input.name}',
                onTap: () => controller.removeInput(index),
              ),
            ],
          ),
          const SizedBox(height: DVStudioStyle.space2),
          _box(
            DropdownButton<DVWorkflowType>(
              value: input.type,
              isExpanded: true,
              hint: const Text(
                'Choose a type',
                style: TextStyle(fontSize: 13, color: DVStudioStyle.danger),
              ),
              items: <DropdownMenuItem<DVWorkflowType>>[
                for (final DVWorkflowType type in DVWorkflowType.values)
                  DropdownMenuItem<DVWorkflowType>(
                    value: type,
                    child: Text(type.label, style: _choice),
                  ),
              ],
              onChanged: (DVWorkflowType? type) {
                if (type != null) {
                  controller.setInput(
                    index,
                    DVWorkflowParameter(
                      input.name,
                      type,
                      optional: input.optional,
                    ),
                  );
                }
              },
            ),
          ),
          const SizedBox(height: DVStudioStyle.space1),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => controller.setInput(
              index,
              input.copyWith(optional: !input.optional),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  input.optional
                      ? Icons.check_box
                      : Icons.check_box_outline_blank,
                  size: 18,
                  color: input.optional
                      ? DVStudioStyle.accent
                      : DVStudioStyle.muted,
                ),
                const SizedBox(width: 6),
                Flexible(child: DVStudioStyle.caption('Can be left out')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final DVWorkflowDocument document = controller.document;
    // Its own Material, for the dropdowns: the inspector is not always
    // placed under one.
    return Material(
      type: MaterialType.transparency,
      child: ListView(
        padding: const EdgeInsets.all(DVStudioStyle.space4),
        children: <Widget>[
          DVStudioStyle.heading(document.name),
          const SizedBox(height: 2),
          DVStudioStyle.caption(
            'Select a step on the canvas to edit it. Here, say what this '
            'function takes and what it gives back.',
          ),
          const SizedBox(height: DVStudioStyle.space5),
          DVStudioStyle.overline('Inputs'),
          const SizedBox(height: DVStudioStyle.space2),
          for (int i = 0; i < document.parameters.length; i++)
            _input(i, document.parameters[i]),
          GestureDetector(
            key: const ValueKey<String>('dv-workflow-add-input'),
            onTap: controller.addInput,
            child: DVStudioStyle.control(
              'Add input',
              enabled: true,
              icon: Icons.add,
            ),
          ),
          const SizedBox(height: DVStudioStyle.space6),
          DVStudioStyle.overline('Returns'),
          const SizedBox(height: DVStudioStyle.space2),
          _box(
            DropdownButton<DVWorkflowType?>(
              value: document.returns,
              isExpanded: true,
              items: <DropdownMenuItem<DVWorkflowType?>>[
                const DropdownMenuItem<DVWorkflowType?>(
                  value: null,
                  child: Text('Nothing', style: _choice),
                ),
                for (final DVWorkflowType type in DVWorkflowType.values)
                  DropdownMenuItem<DVWorkflowType?>(
                    value: type,
                    child: Text(type.label, style: _choice),
                  ),
              ],
              onChanged: controller.setReturns,
            ),
          ),
        ],
      ),
    );
  }
}
