/// The files a server reads to build its pages: the shell, the manifest, the
/// route preloads, a route's prerendered metadata.
///
/// Read through the source registered for the site's root, so a web-server
/// binary reads them from its pack. Each is decoded and parsed once per
/// version of its content -- keyed by the content hash, which a directory
/// recomputes only when a file's size or modification time changes -- rather
/// than on every request: the manifest of a documentation site is a
/// megabyte of JSON.
library;

import 'dart:convert';

import 'package:dartvel_core/framework.dart' show DVAssetFile, DVAssetSources;

final Map<String, (String, Object)> _parsed = <String, (String, Object)>{};

/// The file at [path] under [root] as text, or null when there is none.
String? dvSiteText(String root, String path) {
  final DVAssetFile? file = DVAssetSources.at(root).file(path);
  if (file == null) return null;
  return _once(root, path, 'text', file, () => utf8.decode(file.bytes(), allowMalformed: true)) as String;
}

/// The file at [path] under [root] parsed as JSON, or null when there is
/// none. Throws [FormatException] for one that is not JSON.
Object? dvSiteJson(String root, String path) {
  final DVAssetFile? file = DVAssetSources.at(root).file(path);
  if (file == null) return null;
  return _once(root, path, 'json', file, () => jsonDecode(utf8.decode(file.bytes())) as Object);
}

/// The content hash of the file at [path] under [root], or null.
String? dvSiteHash(String root, String path) => DVAssetSources.at(root).file(path)?.hash;

Object _once(String root, String path, String kind, DVAssetFile file, Object Function() make) {
  final String key = '$kind|$root|$path';
  final String hash = file.hash;
  final (String, Object)? kept = _parsed[key];
  if (kept != null && kept.$1 == hash) return kept.$2;
  final Object made = make();
  _parsed[key] = (hash, made);
  return made;
}
