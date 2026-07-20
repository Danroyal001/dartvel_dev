import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<bool> enterFullscreen() async {
  final root = web.document.documentElement;
  if (root == null) {
    throw StateError('The browser document has no root element.');
  }
  await root.requestFullscreen().toDart;
  return true;
}

Future<bool> exitFullscreen() async {
  if (web.document.fullscreenElement == null) return true;
  await web.document.exitFullscreen().toDart;
  return true;
}
