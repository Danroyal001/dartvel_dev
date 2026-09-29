/// Reading the documentation payload in the browser.
///
/// `fetch()` relative to the document, which is what makes the mount the
/// project's to move: the payload is a sibling of `main.dart.js` on the web,
/// and a site served at `/docs/` and one served at `/` are the same build.
library dartvel_flutter.docs.source.web;

import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// [url], or a [FormatException] naming what answered.
///
/// The body is read as text whatever the status was: a 404 that served
/// `index.html`, or a 200 that served the old hand-written page, is precisely
/// the failure worth reporting by name rather than an empty document.
Future<String> dvDocsReadPayload(String url) async {
  final web.Response response = await web.window
      .fetch(
        url.toJS,
        web.RequestInit(
          // The payload is a build artefact beside the bundle and is not
          // behind a session, but credentials are sent anyway: a site behind
          // basic auth serves the same document to the same reader.
          credentials: 'same-origin',
          cache: 'no-store',
        ),
      )
      .toDart;
  final String body = (await response.text().toDart).toDart;
  if (!response.ok) {
    throw FormatException(
      'the documentation payload answered ${response.status}',
      body.isEmpty ? null : body,
      0,
    );
  }
  return body;
}
