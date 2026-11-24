/// The document half of the selection mirror. See selection_mirror.dart.
library;

import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Marks the element holding the mirrored text.
const String _attribute = 'data-dv-selection';

web.HTMLElement? _mirror;

/// Clipped to one pixel and drawn nowhere, but selectable: an element with
/// `display: none` or `visibility: hidden` cannot hold the selection.
const String _style = 'position:fixed;left:0;top:0;width:1px;height:1px;'
    'overflow:hidden;clip-path:inset(50%);white-space:pre-wrap;'
    'opacity:0;pointer-events:none;'
    'user-select:text;-webkit-user-select:text;z-index:-1';

web.HTMLElement _element() {
  final web.HTMLElement? existing = _mirror;
  if (existing != null && existing.isConnected) return existing;
  final web.HTMLElement created = (web.document.createElement('div') as web.HTMLElement)
    ..setAttribute(_attribute, '')
    ..setAttribute('aria-hidden', 'true')
    ..setAttribute('style', _style);
  web.document.body?.append(created);
  return _mirror = created;
}

/// Whether the reader is typing somewhere: a text field's caret is its
/// selection, and taking it would move what they type.
bool _typing() {
  final web.Element? active = web.document.activeElement;
  if (active == null) return false;
  if (active.isA<web.HTMLInputElement>() || active.isA<web.HTMLTextAreaElement>()) return true;
  return active.isA<web.HTMLElement>() && (active as web.HTMLElement).isContentEditable;
}

/// Whether the document's selection is the mirror's own.
bool _ours(web.Selection selection) {
  final web.HTMLElement? mirror = _mirror;
  final web.Node? anchor = selection.anchorNode;
  return mirror != null && anchor != null && mirror.contains(anchor);
}

void dvMirrorSelection(String? text) {
  final web.Selection? selection = web.window.getSelection();
  if (selection == null) return;
  if (text == null || text.isEmpty) {
    if (selection.rangeCount > 0 && _ours(selection)) selection.removeAllRanges();
    _mirror?.textContent = '';
    return;
  }
  if (_typing()) return;
  final web.HTMLElement mirror = _element();
  if (mirror.textContent != text) mirror.textContent = text;
  if (_ours(selection) && selection.toString() == text) return;
  selection.selectAllChildren(mirror);
}

