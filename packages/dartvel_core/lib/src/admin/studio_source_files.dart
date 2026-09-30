/// Studio's documents as files of the project, during development.
///
/// A page, a component or the set of shortcuts saved in Studio lives in the
/// server's database. On a development server -- `dartvel dev`, which has the
/// project's source beside it -- each is also written to the project:
///
///     studio/pages/<route>.json        a page ("/" is index.json)
///     studio/components/<Name>.json    a component
///     studio/shortcuts.json            the application's shortcuts
///
/// so a commit carries what was made in Studio, and the next build ships it.
/// A file changed in code is read back into Studio. Which side changed is
/// told by the hash of what Studio last wrote, kept beside the documents:
/// when the file no longer has it, code changed it, and Studio neither
/// writes over it nor deletes it without being told to.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;

import '../database/records.dart';
import 'studio_site.dart' show dvStudioComponentsPrefix;

/// Where the project keeps Studio's documents.
const String dvStudioSourceDirectory = 'studio';

const String _shortcutsRoute = '/_dartvel/shortcuts';

/// The file, relative to the project, that the document at [route] is kept
/// in; null for a route that would name a file outside [dvStudioSourceDirectory].
String? dvStudioSourcePath(String route) {
  if (!route.startsWith('/') ||
      route.split('/').any((String part) => part == '..' || part == '.')) {
    return null;
  }
  if (route == _shortcutsRoute) return '$dvStudioSourceDirectory/shortcuts.json';
  if (route.startsWith(dvStudioComponentsPrefix)) {
    final String name = route.substring(dvStudioComponentsPrefix.length);
    if (name.isEmpty || name.contains('/')) return null;
    return '$dvStudioSourceDirectory/components/$name.json';
  }
  if (route.startsWith('/_dartvel/')) return null;
  final String path = route == '/' ? 'index' : route.substring(1);
  if (path.isEmpty || path.endsWith('/')) return null;
  return '$dvStudioSourceDirectory/pages/$path.json';
}

/// The route the file at [path] (relative to the project) is the document
/// for, or null for a file that is not one of Studio's.
String? dvStudioSourceRoute(String path) {
  final String p = path.replaceAll(r'\', '/');
  if (!p.endsWith('.json')) return null;
  if (p == '$dvStudioSourceDirectory/shortcuts.json') return _shortcutsRoute;
  const String components = '$dvStudioSourceDirectory/components/';
  if (p.startsWith(components)) {
    final String name = p.substring(components.length, p.length - 5);
    return name.contains('/') ? null : '$dvStudioComponentsPrefix$name';
  }
  const String pages = '$dvStudioSourceDirectory/pages/';
  if (!p.startsWith(pages)) return null;
  final String rest = p.substring(pages.length, p.length - 5);
  return rest == 'index' ? '/' : '/$rest';
}

/// The file at a route was changed in code since Studio last wrote it.
class DVStudioSourceConflict implements Exception {
  DVStudioSourceConflict(this.path, this.inCode);

  /// The file, relative to the project.
  final String path;

  /// What the file holds now, decoded when it is JSON.
  final Object? inCode;

  @override
  String toString() => '$path was changed in code since Studio last wrote it.';
}

/// The collection the hash of each file Studio wrote is kept in.
const String dvStudioSourcesTable = 'dartvel_studio_sources';

const DVRecordShape _shape = DVRecordShape(
  collection: dvStudioSourcesTable,
  key: 'path',
  fields: <String, DVFieldType>{
    'path': DVFieldType.text,
    'hash': DVFieldType.text,
  },
);

/// Studio's documents as files under [root], the project.
class DVStudioSourceFiles {
  DVStudioSourceFiles(this.root, this.records);

  /// The project's directory.
  final String root;

  /// Where the hash of what Studio last wrote is kept.
  final DVRecordAdapter records;

  File _file(String path) => File('$root/$path');

  static String _hash(String text) => sha256.convert(utf8.encode(text)).toString();

  Future<String?> _written(String path) async {
    await records.ensure(_shape);
    final List<Map<String, Object?>> rows = await records.find(
      dvStudioSourcesTable,
      where: DVFilter.equals('path', path),
    );
    return rows.isEmpty ? null : '${rows.first['hash']}';
  }

  Future<void> _remember(String path, String? hash) async {
    await records.ensure(_shape);
    await records.delete(dvStudioSourcesTable, where: DVFilter.equals('path', path));
    if (hash != null) {
      await records.insert(dvStudioSourcesTable, <String, Object?>{
        'path': path,
        'hash': hash,
      });
    }
  }

  /// Whether the file at [path] is as Studio last left it: absent and never
  /// written, or holding what Studio wrote.
  Future<bool> _untouched(String path) async {
    final File file = _file(path);
    final String? written = await _written(path);
    if (!file.existsSync()) return true;
    return written != null && _hash(file.readAsStringSync()) == written;
  }

  DVStudioSourceConflict _conflict(String path) {
    final String text = _file(path).readAsStringSync();
    Object? inCode;
    try {
      inCode = jsonDecode(text);
    } on FormatException {
      inCode = text;
    }
    return DVStudioSourceConflict(path, inCode);
  }

  /// Writes [document] to its file, unless code changed the file since
  /// Studio last wrote it and [force] is not given: then
  /// [DVStudioSourceConflict]. A file already holding [document] is left as
  /// it is.
  Future<void> write(
    String route,
    Map<Object?, Object?> document, {
    bool force = false,
  }) async {
    final String? path = dvStudioSourcePath(route);
    if (path == null) return;
    final String text =
        '${const JsonEncoder.withIndent('  ').convert(document)}\n';
    final File file = _file(path);
    if (file.existsSync() && file.readAsStringSync() == text) {
      await _remember(path, _hash(text));
      return;
    }
    if (!force && !await _untouched(path)) throw _conflict(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(text);
    await _remember(path, _hash(text));
  }

  /// Deletes the file of the document at [route], on the same terms as
  /// [write].
  Future<void> remove(String route, {bool force = false}) async {
    final String? path = dvStudioSourcePath(route);
    if (path == null) return;
    final File file = _file(path);
    if (!file.existsSync()) {
      await _remember(path, null);
      return;
    }
    if (!force && !await _untouched(path)) throw _conflict(path);
    file.deleteSync();
    await _remember(path, null);
  }

  /// The documents whose files changed in code since Studio last wrote them
  /// -- new, edited or deleted -- as route to document, null for deleted.
  /// Each is remembered as read, so it is reported once.
  Future<Map<String, Map<String, Object?>?>> changedInCode() async {
    final Map<String, Map<String, Object?>?> changed =
        <String, Map<String, Object?>?>{};
    final Directory directory = Directory('$root/$dvStudioSourceDirectory');
    final Set<String> seen = <String>{};
    if (directory.existsSync()) {
      for (final FileSystemEntity entity in directory.listSync(recursive: true)) {
        if (entity is! File) continue;
        final String path = entity.path
            .substring(root.length + 1)
            .replaceAll(r'\', '/');
        final String? route = dvStudioSourceRoute(path);
        if (route == null) continue;
        seen.add(path);
        final String text = entity.readAsStringSync();
        final String hash = _hash(text);
        if (hash == await _written(path)) continue;
        final Object? decoded;
        try {
          decoded = jsonDecode(text);
        } on FormatException {
          continue;
        }
        if (decoded is! Map) continue;
        // The route is the file's: a document copied to a new file is the
        // page at the new file's address.
        changed[route] = <String, Object?>{
          ...decoded.cast<String, Object?>(),
          'route': route,
        };
        await _remember(path, hash);
      }
    }
    await records.ensure(_shape);
    for (final Map<String, Object?> row in await records.find(dvStudioSourcesTable)) {
      final String path = '${row['path']}';
      if (seen.contains(path)) continue;
      final String? route = dvStudioSourceRoute(path);
      if (route != null) changed[route] = null;
      await _remember(path, null);
    }
    return changed;
  }
}
