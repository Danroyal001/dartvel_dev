/// The browser's timer, not a Dart one: a Dart timer still pending when a
/// widget test of a page ends fails the test. See backfill.dart.
library;

import 'dart:js_interop';

import 'package:web/web.dart' as web;

void dvBackfillLater(int milliseconds, void Function() callback) {
  web.window.setTimeout(callback.toJS, milliseconds.toJS);
}
