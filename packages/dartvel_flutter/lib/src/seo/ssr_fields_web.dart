import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'ssr_fields.dart';

/// Reads the server-rendered document's fields and carries what the visitor
/// typed into the app's (see ssr_fields.dart). Called just before the app
/// tells the page it has drawn, while the document is still the page: the
/// SSR-first head leaves a field the visitor is typing in focused, and each
/// keystroke that still lands there follows into the app's field until the
/// app's field has the keyboard.
void dvHandOverSsrFields() {
  final web.Element? root = web.document.documentElement;
  if (root == null || root.hasAttribute('data-dv-app')) return;
  final web.Element? document = web.document.querySelector('.dv-fallback');
  if (document == null) return;
  final web.NodeList found = document.querySelectorAll('[data-dv-field]');
  final List<web.Element> elements = <web.Element>[];
  final List<DVSsrField> fields = <DVSsrField>[];
  for (int index = 0; index < found.length; index++) {
    final web.Element element = found.item(index)! as web.Element;
    final _Read? read = _read(element);
    if (read == null) continue;
    elements.add(element);
    fields.add(DVSsrField(
      name: element.getAttribute('data-dv-field') ?? '',
      value: read.value,
      edited: read.value != read.initial,
      focused: web.document.activeElement == element,
      selectionStart: read.start,
      selectionEnd: read.end,
    ));
  }
  if (!fields.any((DVSsrField field) => field.edited || field.focused)) return;
  final DVSsrFieldCarry carry = dvCarrySsrFields(fields);
  final int typing = fields.indexWhere((DVSsrField field) => field.focused);
  if (typing < 0) return;
  final web.Element element = elements[typing];
  late final JSFunction onInput;
  late final JSFunction onBlur;
  void follow() {
    final _Read? read = _read(element);
    if (read != null) carry.follow(typing, read.value, selectionStart: read.start, selectionEnd: read.end);
  }

  onInput = ((web.Event _) => follow()).toJS;
  onBlur = ((web.Event _) {
    follow();
    element
      ..removeEventListener('input', onInput)
      ..removeEventListener('blur', onBlur);
    _bridge(carry, typing);
  }).toJS;
  element
    ..addEventListener('input', onInput)
    ..addEventListener('blur', onBlur);
}

/// The moment after the document's field lets go of the keyboard and
/// before the app's own text input has it: focus is on the page (Flutter's
/// view), where a key types nothing. Each key typed then goes into the app's
/// field, until a text input has focus again (or two seconds pass).
void _bridge(DVSsrFieldCarry carry, int index) {
  final int until = DateTime.now().millisecondsSinceEpoch + 2000;
  late final JSFunction onKey;
  void stop() => web.document.removeEventListener('keydown', onKey, true.toJS);
  onKey = ((web.KeyboardEvent event) {
    final web.Element? active = web.document.activeElement;
    final String tag = active?.tagName.toUpperCase() ?? '';
    if (tag == 'INPUT' || tag == 'TEXTAREA' || DateTime.now().millisecondsSinceEpoch > until) {
      stop();
      return;
    }
    if (event.ctrlKey || event.metaKey || event.altKey || event.isComposing) return;
    if (event.key == 'Backspace') {
      carry.deleteBackward(index);
    } else if (event.key == 'Enter') {
      carry.typeText(index, '\n');
    } else if (event.key.length == 1 || event.key.runes.length == 1) {
      carry.typeText(index, event.key);
    } else {
      return;
    }
    event.preventDefault();
  }).toJS;
  web.document.addEventListener('keydown', onKey, true.toJS);
}

typedef _Read = ({String value, String initial, int? start, int? end});

_Read? _read(web.Element element) {
  switch (element.tagName.toUpperCase()) {
    case 'TEXTAREA':
      final web.HTMLTextAreaElement area = element as web.HTMLTextAreaElement;
      return (value: area.value, initial: area.defaultValue, start: area.selectionStart, end: area.selectionEnd);
    case 'INPUT':
      final web.HTMLInputElement input = element as web.HTMLInputElement;
      int? start;
      int? end;
      try {
        start = input.selectionStart;
        end = input.selectionEnd;
      } catch (_) {
        // A kind of input with no caret (a number in some browsers).
      }
      return (value: input.value, initial: input.defaultValue, start: start, end: end);
  }
  return null;
}
