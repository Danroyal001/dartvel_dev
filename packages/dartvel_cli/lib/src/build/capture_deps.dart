/// What a route's semantics capture depends on, so it is read again only
/// when something it could have read has changed.
///
/// A capture used to be keyed by the whole web output. An edit to one line of
/// one page (sigmadev.digital's about page) changed `main.dart.js`, six of its
/// parts and one wasm module of 370, and not `main.dart.wasm`, yet all 225
/// routes were read again, eleven minutes of a 23-minute build.
///
/// A route now depends on two things:
///
/// * every file of the web output except the app's code files
///   ([dvCaptureStaticHash]): the shell, the bootstrap, the engine, fonts,
///   images, manifests. Any of them can change any page, so a change to one
///   reads every route again, as before;
/// * the app's code files the route's browser tab actually fetched, from the
///   tab's boot to the end of the route's read ([dvAppCodeHashes]), including
///   what the routes read before it in the same tab ran, since their code
///   left its state in the app.
///
/// A route whose code files are all byte-identical runs the same code on the
/// same files and draws the same tree; one whose code changed, or which never
/// fetched any code at all, is read again. When in doubt it is read.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'build_cache.dart' show dvCaptureInputHash;

/// The app's own compiled code at the top of the web output: dart2js's
/// `main.dart.js` and its deferred parts, and dart2wasm's `main.dart.wasm`,
/// `main.dart.mjs` and deferred modules. Each is fetched by the page itself
/// (never by a worker), so the read sees every one a route loads.
final RegExp _appCode = RegExp(r'^main\.dart(\.js|\.js_\d+\.part\.js|\.wasm|\.mjs|_module\d+\.wasm)$');

/// Whether [relative] (a path in the web output) is one of the app's code
/// files.
bool dvIsAppCodeFile(String relative) => _appCode.hasMatch(relative);

/// The web-output path of [url] when it is one of the app's code files
/// fetched from [base] (the capture's own server); null otherwise.
String? dvAppCodePathOf(String url, String base) {
  final Uri? uri = Uri.tryParse(url);
  final Uri? origin = Uri.tryParse(base);
  if (uri == null || origin == null) return null;
  if (uri.scheme != origin.scheme || uri.host != origin.host || uri.port != origin.port) return null;
  final String path = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
  return dvIsAppCodeFile(path) ? path : null;
}

/// The content hash of every file of [web] but the app's code files (and
/// [skip]), with Flutter's per-compile service worker version left out as
/// [dvCaptureInputHash] leaves it out.
String dvCaptureStaticHash(Directory web, {Set<String> skip = const <String>{}}) {
  final Set<String> code = <String>{...skip};
  if (web.existsSync()) {
    for (final FileSystemEntity entity in web.listSync(followLinks: false)) {
      if (entity is File && dvIsAppCodeFile(p.basename(entity.path))) code.add(p.basename(entity.path));
    }
  }
  return dvCaptureInputHash(web, skip: code);
}

/// Each of [paths] in [web] with the SHA-256 of its content, or `<missing>`.
Map<String, String> dvAppCodeHashes(Directory web, Iterable<String> paths) {
  final List<String> sorted = paths.toSet().toList()..sort();
  return <String, String>{
    for (final String path in sorted) path: _hashOf(web, path),
  };
}

/// Whether every code file in [recorded] (from [dvAppCodeHashes] when the
/// route was read) is still what it was in [web]. A record naming no code
/// file, or a path that is not a code file, never holds.
bool dvCaptureDepsHold(Map<String, String> recorded, Directory web) {
  if (recorded.isEmpty) return false;
  for (final MapEntry<String, String> file in recorded.entries) {
    if (!dvIsAppCodeFile(file.key)) return false;
    if (_hashOf(web, file.key) != file.value) return false;
  }
  return true;
}

/// [recorded] as the file a cache entry keeps it in, and back.
String dvEncodeCaptureDeps(Map<String, String> recorded) => jsonEncode(recorded);

Map<String, String>? dvDecodeCaptureDeps(String source) {
  try {
    final Object? decoded = jsonDecode(source);
    if (decoded is! Map) return null;
    return <String, String>{
      for (final MapEntry<Object?, Object?> entry in decoded.entries)
        if (entry.key is String && entry.value is String) entry.key! as String: entry.value! as String,
    };
  } on FormatException {
    return null;
  }
}

String _hashOf(Directory web, String path) {
  final File file = File(p.join(web.path, path));
  return file.existsSync() ? sha256.convert(file.readAsBytesSync()).toString() : '<missing>';
}
