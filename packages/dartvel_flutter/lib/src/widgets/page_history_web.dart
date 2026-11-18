/// The browser half of page scroll restoration.
///
/// Flutter's web router rebuilds a page when the reader goes back or forward
/// to it, so its scroll position would start at the top, where every browser
/// returns the reader to where they were. This tells the page shell that a
/// back or forward happened and which history entry is on screen, so the
/// shell can put the position back. It also hands over how far the
/// server-rendered document was scrolled before the app took over.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

bool _installed = false;
String? _popped;
DateTime? _poppedAt;
bool _takeoverRead = false;

void dvPageHistoryInstall() {
  if (_installed) return;
  _installed = true;
  web.window.addEventListener(
    'popstate',
    ((web.Event _) {
      _popped = web.window.location.href;
      _poppedAt = DateTime.now();
    }).toJS,
  );
}

String? dvTakeHistoryNavigation() {
  final String? popped = _popped;
  final DateTime? at = _poppedAt;
  _popped = null;
  _poppedAt = null;
  if (popped == null || at == null) return null;
  // A back from long ago is not the navigation this page came from.
  if (DateTime.now().difference(at) > const Duration(seconds: 3)) return null;
  return popped;
}

Object? dvHistoryEntryKey() {
  try {
    final Object? state = web.window.history.state?.dartify();
    if (state is Map) return state['serialCount'];
  } catch (_) {}
  return null;
}

/// Lets the next page shown take the document's position again, for tests:
/// in a browser it is taken once per page load.
void dvRearmTakeoverScroll() => _takeoverRead = false;

double dvTakeTakeoverScroll() {
  if (_takeoverRead) return 0;
  _takeoverRead = true;
  try {
    // A pre-app document may record where its reader was (window.__dvScrollY)
    // before the engine fixes the body in place; otherwise the window's own.
    double offset = 0;
    if (globalContext.has('__dvScrollY')) {
      final Object? recorded = globalContext['__dvScrollY'].dartify();
      if (recorded is num) offset = recorded.toDouble();
    }
    if (offset <= 0) offset = web.window.scrollY;
    if (offset > 0) web.window.scrollTo(0.toJS, 0);
    return offset > 0 ? offset : 0;
  } catch (_) {
    return 0;
  }
}

bool? _touch;

bool dvPrimaryPointerIsTouch() {
  try {
    return _touch ??= web.window.matchMedia('(pointer: coarse)').matches;
  } catch (_) {
    return false;
  }
}

