/// Where the documentation document comes from.
///
/// `dartvel docs` writes `docs.json` beside the site; the application reads it
/// and draws it. The reading is a parameter rather than a call inside the app,
/// because the tests hand it a document and the built site fetches one, and
/// an app that is not the docs app -- an embedder, a test harness, a page that
/// mounts the documentation under a prefix -- has to be able to say where its
/// copy is without the site knowing.
library dartvel_flutter.docs.source;

import 'dart:convert';

import 'package:dartvel_core/dartvel.dart'
    show DVDocsDocument, dvDocsPayloadFile;

import 'docs_source_stub.dart'
    if (dart.library.js_interop) 'docs_source_web.dart'
    as platform;

/// Reads the document. A future that fails is reported by the site rather than
/// swallowed, so a payload that is not a document says so instead of drawing
/// an empty one.
typedef DVDocsSource = Future<DVDocsDocument> Function();

/// The document [payload] holds, or a [FormatException] naming what is wrong
/// with it.
///
/// Checked rather than cast: a payload that is not a document is a stale
/// `index.html` left in the directory the site is served from, and the failure
/// that says so is worth more than a cast error three frames deep.
DVDocsDocument dvDocsDecode(String payload) {
  final Object? decoded = jsonDecode(payload);
  if (decoded is! Map<Object?, Object?>) {
    throw FormatException(
      'the documentation payload is not a document',
      payload,
      0,
    );
  }
  final Map<String, Object?> json = decoded.cast<String, Object?>();
  for (final String key in const <String>[
    'application',
    'graphVersion',
    'navigation',
    'pages',
    'findings',
  ]) {
    if (!json.containsKey(key)) {
      throw FormatException(
        'the documentation payload has no $key',
        payload,
        0,
      );
    }
  }
  return DVDocsDocument.fromJson(json);
}

/// The document the build wrote, fetched from [base] beside it.
///
/// [base] is where the site is mounted rather than where the document is: the
/// mount is the project's to move, and `/docs/` or `/__docs` should both work
/// without this repeating either.
DVDocsSource dvDocsBrowserSource({String base = '/'}) => () async =>
    dvDocsDecode(await platform.dvDocsReadPayload(dvDocsAt(base)));

/// The address of the document, for [base].
///
/// A base with or without its trailing slash, so `dvDocsBrowserSource(base:
/// '/docs/')` and `base: '/docs'` are the same site rather than a request for
/// `/docs/docs.json`.
String dvDocsAt(String base) {
  final String path = base.endsWith('/')
      ? base.substring(0, base.length - 1)
      : base;
  return '$path/$dvDocsPayloadFile';
}
