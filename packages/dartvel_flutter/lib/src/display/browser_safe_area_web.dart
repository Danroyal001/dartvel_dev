import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

web.HTMLElement? _probe;

/// Reads `env(safe-area-inset-*)` through a hidden element padded by them,
/// now and whenever the viewport changes (a rotation, the browser's bars
/// sliding away, the PWA window resizing).
void dvWatchBrowserSafeArea(void Function(EdgeInsets insets) onChange) {
  final web.HTMLElement? body = web.document.body;
  if (body == null) return;
  final web.HTMLElement probe = _probe ??= () {
    final web.HTMLElement element =
        web.document.createElement('div') as web.HTMLElement;
    element.setAttribute('aria-hidden', 'true');
    element.setAttribute('data-dv-safe-area', '');
    element.style.cssText = 'position:fixed;top:0;left:0;width:0;height:0;'
        'visibility:hidden;pointer-events:none;'
        'padding:env(safe-area-inset-top,0px) env(safe-area-inset-right,0px) '
        'env(safe-area-inset-bottom,0px) env(safe-area-inset-left,0px)';
    body.appendChild(element);
    return element;
  }();
  void read() {
    final web.CSSStyleDeclaration style = web.window.getComputedStyle(probe);
    double side(String value) => double.tryParse(value.replaceAll('px', '').trim()) ?? 0;
    onChange(EdgeInsets.fromLTRB(
      side(style.paddingLeft),
      side(style.paddingTop),
      side(style.paddingRight),
      side(style.paddingBottom),
    ));
  }

  read();
  final JSFunction listener = ((web.Event _) => read()).toJS;
  web.window.addEventListener('resize', listener);
  web.window.addEventListener('orientationchange', listener);
  web.window.visualViewport?.addEventListener('resize', listener);
}
