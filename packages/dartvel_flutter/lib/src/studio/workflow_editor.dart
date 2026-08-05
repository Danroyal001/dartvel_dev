import 'package:flutter/widgets.dart';

import '../../dartvel_flutter.dart';

/// Editing state for one workflow: selection and undo/redo, the same bargain
/// the page editor makes.
class DVWorkflowEditorController extends ChangeNotifier {
  DVWorkflowDocument _document;

  final List<Map<String, Object?>> _undo = <Map<String, Object?>>[];
  final List<Map<String, Object?>> _redo = <Map<String, Object?>>[];

  String? _selectedId;

  final int historyLimit;

  DVWorkflowEditorController(
    DVWorkflowDocument document, {
    this.historyLimit = 100,
  }) : _document = document;

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
  Future<void> save() => const DVWorkflowStore().save(_document);

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

/// The draggable step palette.
class DVWorkflowPalette extends StatelessWidget {
  final List<DVWorkflowPaletteItem> items;

  const DVWorkflowPalette({
    super.key,
    this.items = const <DVWorkflowPaletteItem>[],
  });

  @override
  Widget build(BuildContext context) {
    final entries = items.isEmpty ? DVWorkflowPaletteItem.defaults : items;
    return DVBox.list(<Widget>[
      for (final item in entries)
        Draggable<DVWorkflowPaletteItem>(
          data: item,
          feedback: DVText(item.label),
          child: DVText(item.label),
        ),
    ]);
  }
}

/// The workflow canvas: steps in execution order, with a condition's branches
/// nested under it as their own drop targets.
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
  Widget build(BuildContext context) => _buildBranch(
        widget.controller.document.steps,
        DVWorkflowDocumentEditor.rootParent,
      );

  Widget _buildBranch(List<DVWorkflowStep> steps, String parent) {
    return _DVWorkflowDropZone(
      parent: parent,
      controller: widget.controller,
      child: DVBox.list(<Widget>[
        for (final step in steps) _buildStep(step),
        if (steps.isEmpty) DVText('drop here: $parent'),
      ]),
    );
  }

  Widget _buildStep(DVWorkflowStep step) {
    final selected = widget.controller.selectedId == step.id;
    final header = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.controller.select(step.id),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? const Color(0xFF6C4BF4) : const Color(0x22000000),
            width: selected ? 2 : 1,
          ),
        ),
        child: DVText(_label(step)),
      ),
    );

    final draggable = Draggable<String>(
      data: step.id,
      feedback: DVText(_label(step)),
      childWhenDragging: Opacity(opacity: 0.4, child: header),
      child: header,
    );

    if (step.type != 'condition') return draggable;
    // A condition's branches are their own drop zones, so a step can be
    // dragged into the arm it belongs to.
    return DVBox.list(<Widget>[
      draggable,
      const DVText('then'),
      _buildBranch(
        step.branches['then'] ?? const <DVWorkflowStep>[],
        '${step.id}/then',
      ),
      const DVText('else'),
      _buildBranch(
        step.branches['else'] ?? const <DVWorkflowStep>[],
        '${step.id}/else',
      ),
    ]);
  }

  static String _label(DVWorkflowStep step) => switch (step.type) {
        'call' => 'call ${step.name ?? ''}'.trim(),
        'set' => 'set ${step.name ?? ''}'.trim(),
        'condition' => 'if',
        'return' => 'return',
        _ => step.type,
      };
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
      builder: (BuildContext context, List<Object?> _, List<dynamic> __) =>
          child,
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
        final step = controller.selectedStep;
        if (step == null) return const DVText('No step selected');
        return DVBox.list(<Widget>[
          DVText(step.type),
          if (step.type == 'call' || step.type == 'set')
            _DVWorkflowField(
              label: step.type == 'call' ? 'action' : 'variable',
              value: step.name ?? '',
              onChanged: (String value) => controller.update(
                step.id,
                (DVWorkflowStep s) => s.withName(value),
              ),
            ),
          if (step.type == 'call')
            _DVWorkflowField(
              label: 'assign to',
              value: step.assignTo ?? '',
              onChanged: (String value) => controller.update(
                step.id,
                (DVWorkflowStep s) =>
                    s.withAssignTo(value.isEmpty ? null : value),
              ),
            ),
          for (final entry in step.arguments.entries)
            _DVWorkflowField(
              label: entry.key,
              value: '${entry.value.variable ?? entry.value.literal ?? ''}',
              // A leading $ means "read this variable"; anything else is the
              // literal, so a value is never accidentally a reference.
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
        ]);
      },
    );
  }
}

class _DVWorkflowField extends StatelessWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  const _DVWorkflowField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DVBox.row(<Widget>[
      DVText(label),
      Expanded(
        child: EditableText(
          key: ValueKey<String>('dv-workflow-field-$label-$value'),
          controller: TextEditingController(text: value),
          focusNode: FocusNode(),
          style: const TextStyle(fontSize: 14, color: Color(0xFF111111)),
          cursorColor: const Color(0xFF6C4BF4),
          backgroundCursorColor: const Color(0xFFCCCCCC),
          onChanged: onChanged,
        ),
      ),
    ]);
  }
}
