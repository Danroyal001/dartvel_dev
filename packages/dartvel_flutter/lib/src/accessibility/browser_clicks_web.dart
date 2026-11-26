/// The document half of browser_clicks.dart: the browser's click count, read
/// from the click that ends each press.
library;

import 'dart:js_interop';
import 'dart:ui' show Offset;

import 'package:web/web.dart' as web;

import '../platform/web/event_position_js.dart';

bool _installed = false;
double? _downX;
double? _downY;

/// How far the pointer may move between press and release for the click to
/// still be a click rather than a drag, which extends a selection instead.
const double _slop = 4;

void dvInstallBrowserClicks(void Function(int count, Offset position) report) {
  if (_installed) return;
  _installed = true;
  // The pointer events and the click, not mousedown and mouseup: Flutter
  // cancels the pointer's press, and a browser then sends no mousedown or
  // mouseup at all. The click still comes, after Flutter has had the press
  // and the release, and carries the browser's count in `detail`. Captured
  // on the document, where Flutter knows nothing of it.
  web.document.addEventListener(
    'pointerdown',
    ((web.PointerEvent event) {
      _downX = dvEventClientX(event);
      _downY = dvEventClientY(event);
    }).toJS,
    true.toJS,
  );
  web.document.addEventListener(
    'click',
    ((web.MouseEvent event) {
      final double? downX = _downX;
      final double? downY = _downY;
      _downX = _downY = null;
      if (event.button != 0 || event.detail < 2 || downX == null || downY == null) return;
      final double x = dvEventClientX(event);
      final double y = dvEventClientY(event);
      if ((x - downX).abs() > _slop || (y - downY).abs() > _slop) return;
      report(event.detail, Offset(x, y));
    }).toJS,
    true.toJS,
  );
}
