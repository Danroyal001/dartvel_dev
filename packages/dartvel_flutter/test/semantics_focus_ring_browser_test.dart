// Pointer focus on the semantics DOM draws nothing; keyboard focus does.
//
// Dartvel builds the semantics tree on every page (dvEnsureSemantics), so its
// buttons are real focusable elements. Chrome then painted its own focus ring
// around them on click and, on Android, a blue tap highlight on touch: chrome
// a plain Flutter app never shows, because Flutter builds that tree only for a
// screen reader. A keyboard user still needs to see where focus is.
//
// Run with: flutter test --platform chrome test/semantics_focus_ring_browser_test.dart
@TestOn('browser')
library;

import 'package:dartvel_flutter/src/routing/semantics_focus_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

web.HTMLElement semanticsButton() {
  final web.HTMLElement button =
      web.document.createElement('flt-semantics') as web.HTMLElement
        ..setAttribute('role', 'button')
        ..setAttribute('tabindex', '0')
        ..textContent = 'Sign in';
  web.document.body!.append(button);
  return button;
}

String outlineOf(web.HTMLElement element) =>
    web.window.getComputedStyle(element).outlineStyle;

void main() {
  setUpAll(dvInstallSemanticsFocusStyle);

  test('installs the style once', () {
    dvInstallSemanticsFocusStyle();
    expect(web.document.querySelectorAll('style[data-dv-focus]').length, 1);
  });

  test('no tap highlight on semantics elements', () {
    final web.HTMLElement button = semanticsButton();
    expect(
      web.window
          .getComputedStyle(button)
          .getPropertyValue('-webkit-tap-highlight-color'),
      'rgba(0, 0, 0, 0)',
    );
    button.remove();
  });

  test('pointer focus draws no outline', () {
    final web.HTMLElement button = semanticsButton();
    web.document.dispatchEvent(web.PointerEvent('pointerdown'));
    button.focus();
    expect(outlineOf(button), 'none');
    button.remove();
  });

  test('keyboard focus keeps a visible outline', () {
    final web.HTMLElement button = semanticsButton();
    web.document.dispatchEvent(web.KeyboardEvent('keydown',
        web.KeyboardEventInit(key: 'Tab')));
    button.focus();
    expect(outlineOf(button), isNot('none'));
    button.remove();
  });

  test('keyboard mode survives a handler that stops the key event', () {
    // Flutter's keyboard handling stops keydown on the window before it
    // reaches the document; a document listener never saw a real Tab.
    final JSFunction stop = ((web.Event event) => event.stopPropagation()).toJS;
    web.window.addEventListener('keydown', stop, true.toJS);
    final web.HTMLElement button = semanticsButton();
    web.document.dispatchEvent(web.PointerEvent('pointerdown'));
    web.document.body!.dispatchEvent(web.KeyboardEvent('keydown',
        web.KeyboardEventInit(key: 'Tab', bubbles: true)));
    button.focus();
    expect(outlineOf(button), isNot('none'));
    web.window.removeEventListener('keydown', stop, true.toJS);
    button.remove();
  });
}
