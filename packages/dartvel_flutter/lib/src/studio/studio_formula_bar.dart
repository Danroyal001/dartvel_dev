/// The formula bar: one line across the top of the editor where the selected
/// element's fields are read and written as formulas.
///
/// The name box on the left picks the field -- the element's text first,
/// then its layout, its style and its action -- and the line shows that
/// field as a formula, highlighted by kind. Typing offers completions; Enter
/// applies (Ctrl or Cmd+Enter when the bar is expanded to several lines);
/// Esc puts back what was there. A formula that is wrong is refused where it
/// is wrong and nothing is written.
///
/// An accepted formula goes through the editor controller's own
/// `setProperty` or `setAction`, so it is one entry in the same undo history
/// the canvas and the inspector use, it is broadcast to collaborators, and
/// the page's exported code is written from it the same way. The bar keeps
/// no copy of the document.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'page_document.dart';
import 'studio_editor.dart';
import 'studio_formula.dart';

/// A text controller that paints a formula in its kinds.
class DVFormulaTextController extends TextEditingController {
  DVFormulaTextController({super.text});

  static const Map<DVFormulaTokenKind, Color> _colours =
      <DVFormulaTokenKind, Color>{
        DVFormulaTokenKind.string: Color(0xFF0F7B3F),
        DVFormulaTokenKind.number: Color(0xFF1D4ED8),
        DVFormulaTokenKind.colour: Color(0xFFB45309),
        DVFormulaTokenKind.function: Color(0xFF7C3AED),
        DVFormulaTokenKind.keyword: Color(0xFFBE185D),
        DVFormulaTokenKind.identifier: Color(0xFF0E7490),
        DVFormulaTokenKind.operator: Color(0xFF6B7280),
        DVFormulaTokenKind.punctuation: Color(0xFF6B7280),
        DVFormulaTokenKind.unknown: Color(0xFFB91C1C),
      };

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final List<InlineSpan> runs = <InlineSpan>[];
    int at = 0;
    for (final DVFormulaToken t in dvFormulaTokens(text)) {
      if (t.start > at) runs.add(TextSpan(text: text.substring(at, t.start)));
      runs.add(
        TextSpan(
          text: text.substring(t.start, t.end),
          style: TextStyle(color: _colours[t.kind]),
        ),
      );
      at = t.end;
    }
    if (at < text.length) runs.add(TextSpan(text: text.substring(at)));
    return TextSpan(style: style, children: runs);
  }
}

class DVStudioFormulaBar extends StatefulWidget {
  const DVStudioFormulaBar({
    super.key,
    required this.controller,
    this.vocabulary = const DVFormulaVocabulary(),
  });

  final DVStudioEditorController controller;

  /// The routes, data models and functions a formula may name.
  final DVFormulaVocabulary vocabulary;

  static const Key inputKey = ValueKey<String>('dv-studio-formula-input');
  static const Key fieldKey = ValueKey<String>('dv-studio-formula-field');
  static const Key errorKey = ValueKey<String>('dv-studio-formula-error');
  static const Key expandKey = ValueKey<String>('dv-studio-formula-expand');

  @override
  State<DVStudioFormulaBar> createState() => _DVStudioFormulaBarState();
}

class _DVStudioFormulaBarState extends State<DVStudioFormulaBar> {
  final DVFormulaTextController _text = DVFormulaTextController();
  late final FocusNode _focus = FocusNode(onKeyEvent: _onKey);
  String? _nodeId;
  String _fieldName = '';
  String? _error;
  bool _expanded = false;

  /// What the field held when it was last read from the document, so a
  /// change from elsewhere -- an undo, a collaborator -- replaces the line
  /// only when nobody has typed into it.
  String _shown = '';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
    _text.addListener(_typed);
    _sync();
  }

  @override
  void didUpdateWidget(DVStudioFormulaBar old) {
    super.didUpdateWidget(old);
    if (!identical(old.controller, widget.controller)) {
      old.controller.removeListener(_sync);
      widget.controller.addListener(_sync);
      _sync();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  DVPageNode? get _node => widget.controller.selectedNode;

  List<DVFormulaField> get _fields {
    final DVPageNode? node = _node;
    return node == null ? const <DVFormulaField>[] : dvFormulaFields(node);
  }

  DVFormulaField? get _field {
    for (final DVFormulaField f in _fields) {
      if (f.name == _fieldName) return f;
    }
    return _fields.isEmpty ? null : _fields.first;
  }

  /// Reads the selected field from the document.
  void _sync() {
    final DVPageNode? node = _node;
    if (node?.id != _nodeId) {
      _nodeId = node?.id;
      _fieldName = _fields.isEmpty ? '' : _fields.first.name;
      _error = null;
      _show(node == null ? '' : dvFormulaOf(node, _field!));
    } else if (node != null) {
      final String now = dvFormulaOf(node, _field!);
      // Someone else changed it, and the line still shows the old value.
      if (now != _shown && _text.text == _shown) _show(now);
      _shown = now;
    }
    if (mounted) setState(() {});
  }

  void _show(String formula) {
    _shown = formula;
    _text.value = TextEditingValue(
      text: formula,
      selection: TextSelection.collapsed(offset: formula.length),
    );
  }

  void _typed() {
    if (_error != null) setState(() => _error = null);
  }

  void _pick(String? name) {
    if (name == null) return;
    setState(() {
      _fieldName = name;
      _error = null;
    });
    _show(dvFormulaOf(_node!, _field!));
  }

  void _apply() {
    final DVPageNode? node = _node;
    final DVFormulaField? field = _field;
    if (node == null || field == null) return;
    final DVFormulaResult result = dvParseFormula(
      _text.text,
      field,
      widget.vocabulary,
    );
    if (!result.ok) {
      setState(
        () => _error = result.column == null
            ? result.error
            : '${result.error} (at ${result.column! + 1})',
      );
      return;
    }
    if (_text.text == _shown) return;
    if (field.kind == DVFormulaKind.action) {
      widget.controller.setAction(
        node.id,
        result.value as Map<String, Object?>?,
      );
    } else {
      widget.controller.setProperty(node.id, field.name, result.value);
    }
    _show(dvFormulaOf(widget.controller.selectedNode!, field));
    setState(() => _error = null);
  }

  void _cancel() {
    final DVPageNode? node = _node;
    setState(() => _error = null);
    _show(node == null ? '' : dvFormulaOf(node, _field!));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      _cancel();
      return KeyEventResult.handled;
    }
    final bool command =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (_expanded &&
        command &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
      _apply();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      final List<DVFormulaSuggestion> s = _suggestions;
      if (s.isNotEmpty) {
        _take(s.first);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  List<DVFormulaSuggestion> get _suggestions {
    final DVFormulaField? field = _field;
    if (field == null || !_focus.hasFocus || _text.text == _shown) {
      return const <DVFormulaSuggestion>[];
    }
    final int caret = _text.selection.baseOffset < 0
        ? _text.text.length
        : _text.selection.baseOffset;
    return dvFormulaSuggestions(
      _text.text,
      caret,
      field,
      widget.vocabulary,
    ).take(6).toList();
  }

  /// Replaces the word before the caret with [s].
  void _take(DVFormulaSuggestion s) {
    final String text = _text.text;
    final int caret = _text.selection.baseOffset < 0
        ? text.length
        : _text.selection.baseOffset;
    final String before = text.substring(0, caret);
    final RegExpMatch? route = RegExp(r'"([^"]*)$').firstMatch(before);
    final RegExpMatch? word = RegExp(r'[A-Za-z_]\w*$').firstMatch(before);
    final int start = route != null && s.insert.startsWith('/')
        ? route.start + 1
        : (word?.start ?? caret);
    final String next =
        text.substring(0, start) + s.insert + text.substring(caret);
    _text.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + s.insert.length),
    );
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final DVPageNode? node = _node;
    final DVFormulaField? field = _field;
    final bool enabled = node != null && !widget.controller.readOnly;
    final List<DVFormulaSuggestion> suggestions = _suggestions;
    final ThemeData theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const .symmetric(horizontal: 8, vertical: 4),
        child: Column(
          crossAxisAlignment: .stretch,
          mainAxisSize: .min,
          children: <Widget>[
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints box) {
                // On a phone the label and the expand button give their room
                // to the formula.
                final bool narrow = box.maxWidth < 480;
                return Row(
                  crossAxisAlignment: .start,
                  children: <Widget>[
                    if (!narrow)
                      Padding(
                        padding: const .only(top: 6, right: 6),
                        child: Text(
                          'fx',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontStyle: .italic,
                          ),
                        ),
                      ),
                    SizedBox(
                      width: narrow ? 96 : 150,
                      child: DropdownButton<String>(
                        key: DVStudioFormulaBar.fieldKey,
                        isExpanded: true,
                        isDense: true,
                        value: field?.name,
                        hint: const Text('Field'),
                        underline: const SizedBox.shrink(),
                        items: <DropdownMenuItem<String>>[
                          for (final DVFormulaField f in _fields)
                            DropdownMenuItem<String>(
                              value: f.name,
                              child: Text(f.name),
                            ),
                        ],
                        onChanged: enabled ? _pick : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        key: DVStudioFormulaBar.inputKey,
                        controller: _text,
                        focusNode: _focus,
                        enabled: enabled,
                        minLines: 1,
                        maxLines: _expanded ? 6 : 1,
                        keyboardType: _expanded
                            ? TextInputType.multiline
                            : TextInputType.text,
                        textInputAction: _expanded
                            ? TextInputAction.newline
                            : TextInputAction.done,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
                        onSubmitted: _expanded ? null : (_) => _apply(),
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          isDense: true,
                          border: const OutlineInputBorder(),
                          hintText: node == null
                              ? 'Select an element to edit it here'
                              : 'A formula for ${field?.name}',
                        ),
                      ),
                    ),
                    if (!narrow)
                      IconButton(
                        key: DVStudioFormulaBar.expandKey,
                        visualDensity: VisualDensity.compact,
                        iconSize: 18,
                        tooltip: _expanded ? 'One line' : 'Several lines',
                        icon: Icon(
                          _expanded ? Icons.unfold_less : Icons.unfold_more,
                        ),
                        onPressed: enabled
                            ? () => setState(() => _expanded = !_expanded)
                            : null,
                      ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      iconSize: 18,
                      tooltip: 'Apply (Enter)',
                      icon: const Icon(Icons.check),
                      onPressed: enabled ? _apply : null,
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      iconSize: 18,
                      tooltip: 'Cancel (Esc)',
                      icon: const Icon(Icons.close),
                      onPressed: enabled ? _cancel : null,
                    ),
                  ],
                );
              },
            ),
            if (_error != null)
              Padding(
                key: DVStudioFormulaBar.errorKey,
                padding: const .only(left: 190, top: 4),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
            if (suggestions.isNotEmpty)
              Padding(
                padding: const .only(left: 190, top: 4),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: <Widget>[
                    for (final DVFormulaSuggestion s in suggestions)
                      ActionChip(
                        label: Text(s.insert),
                        tooltip: s.detail,
                        onPressed: () => setState(() => _take(s)),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
