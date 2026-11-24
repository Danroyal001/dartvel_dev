/// The browser's timers, not a Dart one: a Dart timer still pending when a
/// widget test of a page ends fails the test. See backfill.dart.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// How much of an idle period a step needs, in milliseconds.
const double _enough = 6;

/// What a step leaves of the idle period, in milliseconds: a row read runs
/// to its end, so the step stops a little early.
const double _margin = 2;

/// A step's budget where the browser cannot say how idle it is (Safari
/// before 18): about half a frame.
const double _blind = 8;

/// After [milliseconds], once the browser is idle: [callback] hears how many
/// milliseconds of the idle period a step may spend, or 0 when there is no
/// room. Where requestIdleCallback is missing, after the timer alone. A
/// browser that is never idle within two seconds is busy: 0, and the step
/// waits for another idle moment.
void dvBackfillLater(int milliseconds, void Function(double budgetMs) callback) {
  void whenIdle() {
    if (!web.window.has('requestIdleCallback')) {
      callback(_blind);
      return;
    }
    web.window.requestIdleCallback(
      ((web.IdleDeadline deadline) {
        final double left = deadline.didTimeout ? 0 : deadline.timeRemaining();
        callback(left >= _enough ? left - _margin : 0);
      }).toJS,
      web.IdleRequestOptions(timeout: 2000),
    );
  }

  if (milliseconds <= 0) {
    whenIdle();
    return;
  }
  web.window.setTimeout(whenIdle.toJS, milliseconds.toJS);
}
