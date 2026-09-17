/// Studio's transport in the browser: fetch(), relative to the page, which
/// is served at the admin mount.
///
/// Relative because the mount is the project's to move. The document's base
/// is the mount, so `api/models` resolves to `<mount>/api/models` wherever
/// that is, and nothing here repeats the path.
library;

import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'studio_server.dart' show DVStudioReply;

Future<DVStudioReply> dvStudioSend(
  String method,
  String path, {
  Object? body,
  required String csrf,
}) async {
  final web.Headers headers = web.Headers()
    ..set('accept', 'application/json')
    ..set('x-dartvel-csrf-token', csrf);
  if (body != null) headers.set('content-type', 'application/json');
  final web.Response response = await web.window
      .fetch(
        path.toJS,
        web.RequestInit(
          method: method,
          headers: headers,
          // The session cookie, and only to this origin.
          credentials: 'same-origin',
          cache: 'no-store',
          body: body == null ? null : jsonEncode(body).toJS,
        ),
      )
      .toDart;
  final String text = (await response.text().toDart).toDart;
  Object? decoded;
  try {
    decoded = text.isEmpty ? null : jsonDecode(text);
  } on FormatException {
    decoded = <String, Object?>{'message': text};
  }
  return DVStudioReply(response.status, decoded);
}
