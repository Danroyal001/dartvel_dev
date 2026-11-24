/// The browser's timers, not a Dart one: a Dart timer still pending when a
/// widget test of a page ends fails the test. See backfill.dart.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// How much of an idle period a step needs, in milliseconds.
const double _enough = 10;

/// After [milliseconds], once the browser is idle: [callback] hears whether
/// the idle period has room for a step. Where requestIdleCallback is missing
/// (Safari before 18), after the timer alone. A browser that is never idle
/// within two seconds is busy: the step waits for another idle moment.
void dvBackfillLater(int milliseconds, void Function(bool idle) callback) {
  web.window.setTimeout(
    (() {
      if (!web.window.has('requestIdleCallback')) {
        callback(true);
        return;
      }
      web.window.requestIdleCallback(
        ((web.IdleDeadline deadline) => callback(!deadline.didTimeout && deadline.timeRemaining() >= _enough)).toJS,
        web.IdleRequestOptions(timeout: 2000),
      );
    }).toJS,
    milliseconds.toJS,
  );
}
