// The document half of the selection mirror, in a browser.
//
// selection_mirror_test.dart proves the page shell hands each selection to
// DVSelectionMirror. This proves what the browser then sees: the selected
// text is the document's selection, so window.getSelection(), the browser's
// copy and anything else that reads the selection get it; clearing it clears
// the document's; and a text field the reader is typing in keeps its caret.
//
// The browser's own Copy reading that selection needs a real user gesture,
// which a test cannot give; it is checked in a real browser on a web-server
// build instead.
//
// Run with: flutter test --platform chrome test/selection_mirror_browser_test.dart
@TestOn('browser')
library;

import 'package:dartvel_flutter/src/accessibility/selection_mirror.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

String documentSelection() => web.window.getSelection()?.toString() ?? '';

void main() {
  tearDown(() => DVSelectionMirror.write(null));

  test('the selected text is the document selection', () {
    DVSelectionMirror.write('Records are deleted after seven years.');
    expect(documentSelection(), 'Records are deleted after seven years.');
  });

  test('a selection over several paragraphs keeps its line breaks', () {
    DVSelectionMirror.write('First paragraph.\nSecond paragraph.');
    expect(documentSelection(), 'First paragraph.\nSecond paragraph.');
  });

  test('clearing the selection clears the document selection', () {
    DVSelectionMirror.write('Gone soon');
    DVSelectionMirror.write(null);
    expect(documentSelection(), '');
  });

  test('the mirror is invisible and not read twice by a screen reader', () {
    DVSelectionMirror.write('Hidden');
    final web.Element mirror = web.document.querySelector('[data-dv-selection]')!;
    expect(mirror.getAttribute('aria-hidden'), 'true');
    final web.DOMRect rect = mirror.getBoundingClientRect();
    expect(rect.width <= 1 && rect.height <= 1, isTrue, reason: 'clipped to a pixel: ${rect.width}x${rect.height}');
  });

  test('a text field being typed in keeps its caret', () {
    final web.HTMLInputElement input = web.document.createElement('input') as web.HTMLInputElement
      ..value = 'typing here';
    web.document.body!.append(input);
    input.focus();
    input.setSelectionRange(3, 3);
    DVSelectionMirror.write('Something selected elsewhere');
    expect(web.document.activeElement, input);
    expect(input.selectionStart, 3);
    input.remove();
  });

  test('clearing leaves alone a selection the mirror did not make', () {
    final web.Element paragraph = web.document.createElement('p')..textContent = 'Page text';
    // The test page, like an app's, turns selection off on the body.
    paragraph.setAttribute('style', 'user-select:text;-webkit-user-select:text');
    web.document.body!.append(paragraph);
    web.window.getSelection()!.selectAllChildren(paragraph);
    DVSelectionMirror.write(null);
    expect(documentSelection(), 'Page text');
    paragraph.remove();
  });
}
