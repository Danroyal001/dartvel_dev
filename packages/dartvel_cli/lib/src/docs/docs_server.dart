import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

import 'docs_site.dart';

/// [output] resolved against the project, as `--output` means it.
String dvDocsOutputPath(String root, String output) =>
    p.normalize(p.isAbsolute(output) ? output : p.join(root, output));

/// Builds the site for [root], writes it to [directory] and reports what the
/// build found. Throws [StateError] when the directory is not the build's to
/// write, or when a declaration the generators refuse is found.
Future<DVDocsSite> dvDocsBuildInto(
  String root,
  String directory, {
  void Function(String line) out = print,
}) async {
  final DVDocsSite site = await DVDocsSite.build(root: root);
  site.writeTo(directory);
  for (final DVDocsFinding finding in site.findings) {
    out('warning  $finding');
  }
  final String shown = p.isWithin(root, directory)
      ? p.relative(directory, from: root).replaceAll(r'\', '/')
      : directory;
  out(
    'dartvel docs: ${site.files.length} files in $shown'
    '${site.findings.isEmpty ? '' : ', ${site.findings.length} warning(s)'}',
  );
  return site;
}

/// Serves the documentation site and rebuilds it when the project changes.
///
/// Bound to loopback. This is the server for writing against; the site the
/// team reads is mounted inside the application, behind its authentication,
/// and internal documentation served on every interface of a laptop is a
/// copy of the schema handed to the coffee shop.
class DVDocsServer {
  DVDocsServer._(this._server, this._root, this._directory, this._out);

  final HttpServer _server;
  final String _root;
  final String _directory;
  final void Function(String line) _out;

  StreamSubscription<WatchEvent>? _watch;
  Timer? _debounce;
  Future<void>? _building;
  bool _again = false;

  Uri get url =>
      Uri.parse('http://${_server.address.address}:${_server.port}/');

  static Future<DVDocsServer> start({
    required String root,
    String output = 'build/docs',
    int port = 4180,
    void Function(String line) out = print,
  }) async {
    final String directory = dvDocsOutputPath(root, output);
    await dvDocsBuildInto(root, directory, out: out);
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      port,
    );
    final DVDocsServer docs = DVDocsServer._(server, root, directory, out);
    server.listen(docs._handle);
    final DirectoryWatcher watcher = DirectoryWatcher(root);
    docs._watch = watcher.events.listen(docs._changed);
    // A change made before the watcher is ready would be missed, and the
    // first edit after starting is the one somebody is looking for.
    await watcher.ready;
    out('dartvel docs: serving ${docs.url} (watching for changes)');
    return docs;
  }

  Future<void> close() async {
    _debounce?.cancel();
    await _watch?.cancel();
    await _building;
    await _server.close(force: true);
  }

  void _changed(WatchEvent event) {
    final String path = p.normalize(event.path);
    if (p.equals(path, _directory) || p.isWithin(_directory, path)) return;
    final List<String> parts = p.split(p.relative(path, from: _root));
    // Tool caches, version control and anything else hidden, and build
    // output, none of which is documentation input.
    if (parts.any((String s) => s.startsWith('.') || s == 'build')) return;
    if (!RegExp(r'\.(dart|md|ya?ml)$').hasMatch(path)) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), _rebuild);
  }

  void _rebuild() {
    if (_building != null) {
      _again = true;
      return;
    }
    _building =
        () async {
          try {
            await dvDocsBuildInto(_root, _directory, out: _out);
          } on Object catch (error) {
            // A half-typed file is the normal state of a project being written
            // against; report it and keep serving the last good build.
            _out('dartvel docs: rebuild failed: $error');
          }
        }().whenComplete(() {
          _building = null;
          if (_again) {
            _again = false;
            _rebuild();
          }
        });
  }

  Future<void> _handle(HttpRequest request) async {
    final HttpResponse response = request.response;
    try {
      if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        return;
      }
      final List<String> segments = request.uri.pathSegments
          .where((String s) => s.isNotEmpty)
          .toList();
      // Each segment is already decoded, so an encoded slash arrives inside
      // one. Refusing those, dot segments and hidden names keeps every
      // request inside the site -- and off the build's own marker file.
      final bool safe = segments.every(
        (String s) =>
            !s.contains('/') && !s.contains(r'\') && !s.startsWith('.'),
      );
      String? path;
      if (safe) {
        path = p.joinAll(<String>[_directory, ...segments]);
        if (FileSystemEntity.isDirectorySync(path)) {
          path = p.join(path, 'index.html');
        }
      }
      if (path == null ||
          !p.isWithin(_directory, path) ||
          !File(path).existsSync()) {
        response
          ..statusCode = HttpStatus.notFound
          ..write('Not found');
        return;
      }
      response.headers.contentType = switch (p.extension(path)) {
        '.html' => ContentType.html,
        '.json' => ContentType.json,
        _ => ContentType.binary,
      };
      response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      if (request.method == 'GET') response.add(File(path).readAsBytesSync());
    } finally {
      await response.close();
    }
  }
}
