// The browser's click count, read from pointer events whose coordinates are
// fractions of a pixel.
//
// sigmadev.digital (Dartvel 3.47.11, wasm): every mouse press on a button
// threw `Exception: Exception` from a document listener. Chrome gives a
// pointer event's clientX and clientY as fractions of a pixel (a press at
// 683.5, 412.25), package:web declares them `int`, and dart2wasm refuses a
// fraction where an int is declared: dvInstallBrowserClicks' pointerdown
// listener threw on the press, before the app saw the click. Under dart2js
// the same read passes the fraction through, so this test matters under
// --wasm.
//
// Run with: flutter test --platform chrome --wasm test/browser_clicks_fraction_browser_test.dart
@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:dartvel_flutter/src/accessibility/browser_clicks_web.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

void main() {
  test('a press and a double click at fractions of a pixel are read, and nothing throws', () {
    final List<String> errors = <String>[];
    final JSFunction onError = ((web.ErrorEvent event) {
      errors.add(event.message);
      event.preventDefault();
    }).toJS;
    web.window.addEventListener('error', onError);
    addTearDown(() => web.window.removeEventListener('error', onError));

    final List<(int, Offset)> reported = <(int, Offset)>[];
    dvInstallBrowserClicks((int count, Offset position) => reported.add((count, position)));

    final web.Element target = web.document.createElement('div');
    web.document.body!.append(target);
    addTearDown(() => target.remove());
    // The init dictionaries declare the coordinates as int too, so the
    // fractions go in as a plain object, as a browser's own event has them.
    JSObject init(double x, double y, {int detail = 0}) => JSObject()
      ..setProperty('bubbles'.toJS, true.toJS)
      ..setProperty('clientX'.toJS, x.toJS)
      ..setProperty('clientY'.toJS, y.toJS)
      ..setProperty('detail'.toJS, detail.toJS);
    target.dispatchEvent(web.PointerEvent('pointerdown', init(683.5, 412.25) as web.PointerEventInit));
    // Chrome sends a click as a PointerEvent too.
    target.dispatchEvent(web.PointerEvent('click', init(684.75, 412.5, detail: 2) as web.PointerEventInit));

    expect(errors, isEmpty);
    expect(reported, hasLength(1));
    expect(reported.single.$1, 2);
    // Where the browser says the click was (Chrome keeps a synthetic click's
    // fraction or not depending on the event type).
    expect(reported.single.$2.dx, closeTo(684.75, 1));
    expect(reported.single.$2.dy, closeTo(412.5, 1));
  });
}
