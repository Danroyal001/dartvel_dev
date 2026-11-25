/// SSR-first: the fields of the server-rendered page and the app's own,
/// at the handover (`dartvel.web.ssrFirst`).
///
/// Before Flutter takes over -- 8 to 15 seconds and more on a phone on
/// mobile data -- the page is the server-rendered document, and its fields
/// are real inputs a visitor types into (dvSsrFirstLayout in dartvel_core
/// places each over the box the app paints for it). At the handover
/// [dvCarrySsrFields] puts what was typed into the app's field of the same
/// name, with its caret or selection, and moves focus there when the visitor
/// was typing; [DVSsrFieldCarry.follow] carries each keystroke that still
/// lands in the document's field until the app's field has the keyboard, so
/// nothing typed mid-word is lost and typing never waits for the app.
///
/// A document field and an app field match by name: the field's semantics
/// label, which the build wrote into the document as `data-dv-field` (the
/// app's `Semantics` label round the field, or its decoration's label or
/// hint). Where no name matches and both pages have the same number of
/// fields, they match by order. A field the visitor never touched keeps the
/// app's own value.
library;

import 'package:flutter/material.dart';

/// One field of the server-rendered document at the handover.
class DVSsrField {
  const DVSsrField({
    required this.name,
    required this.value,
    this.edited = false,
    this.focused = false,
    this.selectionStart,
    this.selectionEnd,
  });

  /// Its name: the `data-dv-field` the build wrote, the app field's
  /// semantics label.
  final String name;

  /// What is in it now.
  final String value;

  /// Whether the visitor changed it: only then does its value replace the
  /// app's.
  final bool edited;

  /// Whether the visitor is typing in it.
  final bool focused;

  final int? selectionStart;
  final int? selectionEnd;
}

/// The result of a carry: which document field went to which app field.
class DVSsrFieldCarry {
  DVSsrFieldCarry._(this._targets);

  /// Per document field, in the order given: the app field it went to, or
  /// null.
  final List<EditableTextState?> _targets;

  /// How many document fields found an app field.
  int get matched => _targets.where((EditableTextState? state) => state != null).length;

  /// What the visitor typed into document field [index] after the carry,
  /// before the app's field had the keyboard: the app's field takes the same
  /// text and caret, and the app hears it as typing.
  void follow(int index, String value, {int? selectionStart, int? selectionEnd}) {
    if (index < 0 || index >= _targets.length) return;
    final EditableTextState? state = _targets[index];
    if (state == null || !state.mounted) return;
    _apply(state, value, selectionStart, selectionEnd);
  }

  /// A key typed for document field [index] after it let go of the keyboard
  /// and before the app's field has it (the page itself has focus for that
  /// moment): [text] replaces the app field's selection, as typing does.
  void typeText(int index, String text) => _edit(index, (String value, int start, int end) =>
      (value.replaceRange(start, end, text), start + text.length));

  /// Backspace in that same moment: the selection, or the character before
  /// the caret, goes.
  void deleteBackward(int index) => _edit(index, (String value, int start, int end) {
        if (start != end) return (value.replaceRange(start, end, ''), start);
        if (start == 0) return (value, 0);
        final int from = value.characters.take(value.substring(0, start).characters.length - 1).string.length;
        return (value.replaceRange(from, start, ''), from);
      });

  void _edit(int index, (String, int) Function(String value, int start, int end) change) {
    if (index < 0 || index >= _targets.length) return;
    final EditableTextState? state = _targets[index];
    if (state == null || !state.mounted) return;
    final TextEditingValue current = state.textEditingValue;
    final String value = current.text;
    final TextSelection selection = current.selection;
    final int start = selection.isValid ? selection.start.clamp(0, value.length) : value.length;
    final int end = selection.isValid ? selection.end.clamp(0, value.length) : value.length;
    final (String next, int caret) = change(value, start, end);
    _apply(state, next, caret, caret);
  }
}

String _norm(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

/// The names an app field answers to, nearest first: the closest
/// `Semantics` label round it, and its decoration's label and hint.
List<String> _namesOf(Element editable) {
  final List<String> names = <String>[];
  void add(String? name) {
    if (name == null) return;
    final String normal = _norm(name);
    if (normal.isNotEmpty && !names.contains(normal)) names.add(normal);
  }

  int depth = 0;
  editable.visitAncestorElements((Element ancestor) {
    final Widget widget = ancestor.widget;
    if (widget is TextField) {
      add(widget.decoration?.labelText);
      add(widget.decoration?.hintText);
    } else if (widget is InputDecorator) {
      add(widget.decoration.labelText);
      add(widget.decoration.hintText);
    } else if (widget is Semantics && widget.properties.label != null &&
        widget.properties.label!.trim().isNotEmpty) {
      add(widget.properties.label);
      return false;
    }
    // A field's own wrapping is a few dozen elements deep; further out is
    // the page, whose labels name something else.
    return ++depth < 40;
  });
  return names;
}

/// Whether document field [name] is the app field answering to [names]:
/// the same name, or the name followed by more (Flutter's web semantics
/// names a field by its label and then its hint).
bool _answers(String name, List<String> names) {
  final String wanted = _norm(name);
  if (wanted.isEmpty) return false;
  for (final String own in names) {
    if (wanted == own) return true;
    if (wanted.startsWith(own) &&
        wanted.length > own.length &&
        RegExp(r'[\s,.;:]').hasMatch(wanted[own.length])) {
      return true;
    }
  }
  return false;
}

void _apply(EditableTextState state, String value, int? start, int? end) {
  final int length = value.length;
  final int base = (start ?? length).clamp(0, length);
  final int extent = (end ?? base).clamp(0, length);
  final TextEditingValue next = TextEditingValue(
    text: value,
    selection: TextSelection(baseOffset: base, extentOffset: extent),
  );
  if (state.textEditingValue == next) return;
  // As typing, so the app's onChanged, formatters and listeners all run.
  state.userUpdateTextEditingValue(next, null);
}

/// Carries [fields] -- the server-rendered document's, in document order --
/// into the app's text fields now on screen. See the library comment.
DVSsrFieldCarry dvCarrySsrFields(List<DVSsrField> fields, {Element? root}) {
  final List<(EditableTextState, List<String>)> appFields = <(EditableTextState, List<String>)>[];
  void visit(Element element) {
    if (element is StatefulElement && element.state is EditableTextState) {
      appFields.add((element.state as EditableTextState, _namesOf(element)));
    }
    element.visitChildElements(visit);
  }

  final Element? start = root ?? WidgetsBinding.instance.rootElement;
  if (start != null) visit(start);

  final List<EditableTextState?> targets = List<EditableTextState?>.filled(fields.length, null);
  final Set<EditableTextState> taken = <EditableTextState>{};
  for (int index = 0; index < fields.length; index++) {
    for (final (EditableTextState state, List<String> names) in appFields) {
      if (taken.contains(state) || !_answers(fields[index].name, names)) continue;
      targets[index] = state;
      taken.add(state);
      break;
    }
  }
  // The same fields on both pages and names that did not say: by order.
  if (fields.length == appFields.length) {
    final List<EditableTextState> left = <EditableTextState>[
      for (final (EditableTextState state, List<String> _) in appFields)
        if (!taken.contains(state)) state,
    ];
    int next = 0;
    for (int index = 0; index < fields.length; index++) {
      if (targets[index] == null && next < left.length) targets[index] = left[next++];
    }
  }

  EditableTextState? focus;
  for (int index = 0; index < fields.length; index++) {
    final EditableTextState? state = targets[index];
    if (state == null) continue;
    final DVSsrField field = fields[index];
    // The app's field never shows a password's text twice, and a field the
    // visitor never touched keeps the app's own value.
    if (field.edited && !state.widget.readOnly) {
      _apply(state, field.value, field.selectionStart, field.selectionEnd);
    }
    if (field.focused) focus = state;
  }
  if (focus != null && focus.mounted) {
    final FocusNode node = focus.widget.focusNode;
    final DVSsrField field = fields[targets.indexOf(focus)];
    node.requestFocus();
    // Focusing keeps a selection the field already has; the visitor's caret
    // is the one in the document.
    if (!field.edited) {
      _apply(focus, focus.textEditingValue.text, field.selectionStart, field.selectionEnd);
    }
  }
  return DVSsrFieldCarry._(targets);
}
