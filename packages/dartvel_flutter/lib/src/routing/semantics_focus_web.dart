/// Web only: the browser's own focus chrome on the semantics DOM.
library dartvel_flutter.routing.semantics_focus.web;

import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Hide the browser's focus ring and tap highlight on the semantics DOM,
/// except while the user is navigating with the keyboard.
///
/// dvEnsureSemantics builds the semantics tree on every page, so buttons are
/// real focusable elements. Chrome painted its own ring around them on click
/// and a blue tap highlight on touch, around the text rather than the button
/// Flutter drew: chrome a plain Flutter app never shows, because Flutter
/// builds that tree only for a screen reader. Flutter's own widgets already
/// show focus in the app's theme.
///
/// The ring stays for the keyboard. A Tab, arrow or Enter switches the page to
/// keyboard mode, where the browser's ring is shown as before; the next
/// pointer or touch switches it back. Idempotent.
void dvInstallSemanticsFocusStyle() {
  final web.Document document = web.document;
  if (document.querySelector('style[data-dv-focus]') != null) return;
  final web.HTMLStyleElement style =
      document.createElement('style') as web.HTMLStyleElement
        ..setAttribute('data-dv-focus', '')
        ..textContent = 'flt-semantics,flt-semantics *,flt-semantics-host,'
            'flt-semantics-host *{-webkit-tap-highlight-color:transparent}'
            'html:not([data-dv-keyboard]) flt-semantics:focus,'
            'html:not([data-dv-keyboard]) flt-semantics *:focus'
            '{outline:none}';
  (document.head ?? document.documentElement!).append(style);

  final web.Element root = document.documentElement!;
  document.addEventListener(
    'keydown',
    ((web.KeyboardEvent event) {
      if (event.ctrlKey || event.metaKey || event.altKey) return;
      root.setAttribute('data-dv-keyboard', '');
    }).toJS,
    true.toJS,
  );
  for (final String type in const <String>['pointerdown', 'mousedown', 'touchstart']) {
    document.addEventListener(
      type,
      ((web.Event _) => root.removeAttribute('data-dv-keyboard')).toJS,
      true.toJS,
    );
  }
}
