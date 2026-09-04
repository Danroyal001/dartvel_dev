/// A static file server, for the CI steps that need something to point a
/// browser at.
///
///     dart tool/ci/serve.dart 8080            # files as they are
///     dart tool/ci/serve.dart 8082 --spa      # unknown paths get index.html
///
/// The `--spa` form is what a path-URL application needs and what Dartvel's
/// own deploy configuration writes: a plain file server answers 404 for a
/// route with no file on disk, so a mounted module's page looks missing when
/// the only thing missing is the rewrite.
///
/// Only dart:io, so it runs from a checkout with nothing resolved.
library;

import 'dart:io';

Future<int> main(List<String> arguments) async {
  final int port =
      arguments.isEmpty ? 8080 : int.tryParse(arguments.first) ?? 8080;
  final bool spa = arguments.contains('--spa');
  final Directory root = Directory.current;

  final HttpServer server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  stdout.writeln('serving ${root.path} on $port${spa ? ' (spa)' : ''}');

  await for (final HttpRequest request in server) {
    File? file = _resolve(root, request.uri.path);
    if (file == null && spa) file = File('${root.path}/index.html');
    if (file == null || !file.existsSync()) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      continue;
    }
    request.response.headers.contentType = _typeOf(file.path);
    // Length set explicitly: a browser that gets a chunked response with no
    // length will still render, and a `curl -sI` in the step above reads it
    // to decide the server is up.
    request.response.headers.contentLength = file.lengthSync();
    await request.response.addStream(file.openRead());
    await request.response.close();
  }
  return 0;
}

/// The file [path] names, or null when there is none.
///
/// A path that escapes the directory being served is refused rather than
/// resolved: this serves a build output to a browser on the same machine,
/// and a server that answered `../../etc/passwd` in CI would answer it
/// anywhere it was copied to.
File? _resolve(Directory root, String path) {
  final String decoded = Uri.decodeComponent(path);
  final String full = Uri.file('${root.path}/').resolve('.$decoded').toFilePath();
  if (!full.startsWith(root.path)) return null;
  final Directory directory = Directory(full);
  if (directory.existsSync()) {
    final File index = File('$full/index.html');
    return index.existsSync() ? index : null;
  }
  final File file = File(full);
  return file.existsSync() ? file : null;
}

ContentType _typeOf(String path) => switch (path.split('.').last) {
      'html' => ContentType.html,
      'js' || 'mjs' => ContentType('application', 'javascript', charset: 'utf-8'),
      'json' => ContentType.json,
      'css' => ContentType('text', 'css', charset: 'utf-8'),
      'wasm' => ContentType('application', 'wasm'),
      'png' => ContentType('image', 'png'),
      'jpg' || 'jpeg' => ContentType('image', 'jpeg'),
      'svg' => ContentType('image', 'svg+xml'),
      'ico' => ContentType('image', 'x-icon'),
      'woff2' => ContentType('font', 'woff2'),
      'ttf' => ContentType('font', 'ttf'),
      'otf' => ContentType('font', 'otf'),
      'txt' => ContentType.text,
      _ => ContentType.binary,
    };
