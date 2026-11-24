/// The document half of browser_clicks.dart: the browser's click count, read
/// as the button comes up.
library;

import 'dart:js_interop';
import 'dart:ui' show Offset;

import 'package:web/web.dart' as web;

bool _installed = false;
double? _downX;
double? _downY;

/// How far the pointer may move between press and release for the click to
/// still be a click rather than a drag, which extends a selection instead.
const double _slop = 4;

void dvInstallBrowserClicks(void Function(int count, Offset position) report) {
  if (_installed) return;
  _installed = true;
  // Captured on the document, after Flutter has had the pointer events: the
  // mouse events follow the pointer events they belong to.
  web.document.addEventListener(
    'mousedown',
    ((web.MouseEvent event) {
      _downX = event.clientX.toDouble();
      _downY = event.clientY.toDouble();
    }).toJS,
    true.toJS,
  );
  web.document.addEventListener(
    'mouseup',
    ((web.MouseEvent event) {
      final double? downX = _downX;
      final double? downY = _downY;
      _downX = _downY = null;
      if (event.button != 0 || event.detail < 2 || downX == null || downY == null) return;
      final double x = event.clientX.toDouble();
      final double y = event.clientY.toDouble();
      if ((x - downX).abs() > _slop || (y - downY).abs() > _slop) return;
      report(event.detail, Offset(x, y));
    }).toJS,
    true.toJS,
  );
}
