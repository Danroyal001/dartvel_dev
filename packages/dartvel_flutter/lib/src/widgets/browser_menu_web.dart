/// Shift+right-click for the browser's menu, and putting Flutter's back after
/// any right-click the browser was given.
library;

import 'dart:js_interop';

import 'package:web/web.dart' as web;

void dvListenForNativeMenu({
  required void Function() arm,
  required void Function() disarm,
}) {
  // mousedown comes before contextmenu, so turning the browser's menu on
  // here is in time for the menu this click opens. Captured on the document,
  // ahead of anything Flutter listens for on its own element.
  void down(web.Event event) {
    final web.MouseEvent mouse = event as web.MouseEvent;
    if (mouse.button == 2 && mouse.shiftKey) arm();
  }

  // After the browser has had its menu, the next right-click is Flutter's
  // again: a timer, so the menu this event opens is not the one turned off.
  void menu(web.Event event) {
    web.window.setTimeout((() => disarm()).toJS, 0.toJS);
  }

  web.document.addEventListener('mousedown', down.toJS, true.toJS);
  web.document.addEventListener('contextmenu', menu.toJS, true.toJS);
}
