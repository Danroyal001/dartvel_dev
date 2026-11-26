import 'dart:async';
import 'dart:js_interop';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import 'ssr_fields.dart';

/// How long the handover waits for the app's own field when the visitor
/// typed into the server-rendered document and the app has not built that
/// field yet (see [dvHandOverSsrFields]). The document is the page all that
/// time -- readable, and still taking typing -- so the wait strands nobody;
/// after it the app takes the page whether or not the field came.
const Duration dvSsrFieldHold = Duration(seconds: 6);

/// How often the held handover looks for the app's field again.
const Duration _retryEvery = Duration(milliseconds: 50);

/// Reads the server-rendered document's fields and carries what the visitor
/// typed into the app's (see ssr_fields.dart). Called just before the app
/// tells the page it has drawn, while the document is still the page: the
/// SSR-first head leaves a field the visitor is typing in focused, and each
/// keystroke that still lands there follows into the app's field until the
/// app's field has the keyboard.
///
/// An app often builds its form after its first frame: a sign-in page shows
/// once the session check says nobody is signed in, a form once its data
/// has loaded. When a field the visitor typed in (or is in) has no app
/// field yet, the handover waits -- the returned future completes and the
/// app takes the page only once every such field has one, the app has gone
/// to another address (a visitor already signed in), or [hold] has passed.
/// Meanwhile the document stays the page and the visitor keeps typing; what
/// is in the field when the app's field arrives is what is carried, with
/// the caret and the focus. With nothing typed there is no wait.
Future<void> dvHandOverSsrFields({Duration hold = dvSsrFieldHold}) {
  final _Document? now = _readDocument();
  if (now == null || !now.wanted) return Future<void>.value();
  if (dvSsrFieldsHaveTargets(now.fields)) {
    _carry(now);
    return Future<void>.value();
  }
  final Completer<void> handed = Completer<void>();
  final String address = web.window.location.href;
  bool expired = false;
  final Timer deadline = Timer(hold, () => expired = true);
  void retry() {
    final _Document? document = _readDocument();
    if (document == null || !document.wanted) {
      deadline.cancel();
      handed.complete();
      return;
    }
    if (!expired && web.window.location.href == address && !dvSsrFieldsHaveTargets(document.fields)) {
      Timer(_retryEvery, retry);
      return;
    }
    deadline.cancel();
    _carry(document);
    handed.complete();
  }

  Timer(_retryEvery, retry);
  return handed.future;
}

/// The document's fields as they are now, each beside its element.
typedef _Document = ({List<web.Element> elements, List<DVSsrField> fields, bool wanted});

_Document? _readDocument() {
  final web.Element? root = web.document.documentElement;
  if (root == null || root.hasAttribute('data-dv-app')) return null;
  final web.Element? document = web.document.querySelector('.dv-fallback');
  if (document == null) return null;
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
  return (
    elements: elements,
    fields: fields,
    wanted: fields.any((DVSsrField field) => field.edited || field.focused),
  );
}

void _carry(_Document document) {
  final List<web.Element> elements = document.elements;
  final List<DVSsrField> fields = document.fields;
  // From here the app moves the keyboard (to its own field, or to the page
  // while a key is bridged over); the head script stops handing it back to
  // the document field when the app focuses its view.
  web.document.documentElement?.setAttribute('data-dv-carried', '');
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
  // The app's field took the focus: the keyboard goes to the app's view
  // (the engine then gives it to the field's own input). The document
  // field's blur above follows the last keystroke and bridges the moment
  // in between. The head script gave the keyboard back to the document
  // field when the app's first frame focused the view, so the engine may
  // still count the view as focused and would not move it on its own.
  final EditableTextState? target = carry.targetOf(typing);
  if (target == null) return;
  // After the focus change the carry asked for has been applied.
  scheduleMicrotask(() {
    if (!target.mounted || !target.widget.focusNode.hasFocus) return;
    final ui.FlutterView? view = View.maybeOf(target.context);
    if (view == null) return;
    WidgetsBinding.instance.platformDispatcher.requestViewFocusChange(
      viewId: view.viewId,
      state: ui.ViewFocusState.focused,
      direction: ui.ViewFocusDirection.forward,
    );
  });
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
