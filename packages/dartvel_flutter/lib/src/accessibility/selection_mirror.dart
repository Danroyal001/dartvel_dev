/// What the reader has selected on a page, told to the document.
///
/// Flutter draws a page's text on a canvas and keeps the selection to itself:
/// a reader could drag, double-click or triple-click and copy with Ctrl+C,
/// and the browser saw nothing selected. `window.getSelection()` was empty,
/// so a script reading the selection (a dictionary, a translator, a
/// highlighter, a test) got nothing, and the browser's own Copy, from its
/// menu, copied nothing (Tori and Learnacer, Dartvel 3.47.7).
///
/// The page shell hands every change of its selection here. On the web the
/// selected text goes into a one-pixel, clipped element of the document, kept
/// from screen readers (which read the page from its semantics tree), and
/// that element's text is made the document's selection. Flutter's own
/// selection, its handles and its menu are untouched: this follows them and
/// never leads. A text field the reader is typing in is never touched, and
/// clearing leaves alone any selection the mirror did not make. Elsewhere it
/// does nothing.
///
/// Not in the barrel: every selectable page has it, and there is nothing for
/// an application to call.
library;

import 'selection_mirror_stub.dart'
    if (dart.library.js_interop) 'selection_mirror_web.dart' as platform;

abstract final class DVSelectionMirror {
  /// Tells the document the reader's selection is [text]; null or empty when
  /// nothing is selected. Tests replace it.
  static void Function(String? text) write = platform.dvMirrorSelection;

  /// Puts the document's half back, for tests.
  static void reset() => write = platform.dvMirrorSelection;
}
