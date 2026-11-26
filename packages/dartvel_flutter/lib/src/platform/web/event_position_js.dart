/// Where a mouse, pointer or drag event happened, as the browser says it.
///
/// package:web declares `MouseEvent.clientX` and `clientY` as `int`, but a
/// browser gives them as fractions of a pixel (Chrome: every pointer event on
/// a screen that is zoomed or not 1:1, and synthetic presses at a box's
/// centre). Under dart2js the fraction passes through an `int` unchecked;
/// dart2wasm refuses it and throws, and a listener that read them threw out
/// of the browser's event dispatch (`Exception: Exception` on every mouse
/// press on sigmadev.digital, Dartvel 3.47.11). Read here as the numbers
/// they are.
library;

import 'dart:js_interop';

extension type _Position(JSObject _) implements JSObject {
  external double get clientX;
  external double get clientY;
}

/// The event's `clientX`, fractions kept.
double dvEventClientX(JSObject event) => _Position(event).clientX;

/// The event's `clientY`, fractions kept.
double dvEventClientY(JSObject event) => _Position(event).clientY;
