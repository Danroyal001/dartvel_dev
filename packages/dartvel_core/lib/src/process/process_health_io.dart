/// [DVProcessHealth] over a `dart:io` server.
library;

import 'dart:convert';
import 'dart:io';

import 'process_configuration.dart';
import 'process_health.dart';

Future<DVProcessHealth> dvServeProcessHealth({
  required String host,
  required int port,
  required DVProcessRole role,
}) async {
  final HttpServer server = await HttpServer.bind(host, port);
  final String body = jsonEncode(<String, Object?>{
    'status': 'ok',
    'role': role.name,
  });
  server.listen((HttpRequest request) async {
    final HttpResponse response = request.response;
    try {
      if (request.uri.path != '/healthz') {
        response.statusCode = HttpStatus.notFound;
      } else if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        response.headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
      } else {
        response.statusCode = HttpStatus.ok;
        response.headers
          ..contentType = ContentType.json
          ..set(HttpHeaders.cacheControlHeader, 'no-store');
        // dart:io sends no body for HEAD.
        response.write(body);
      }
      await response.close();
    } on Object {
      // A client that went away mid-response is not the process's health.
    }
  });
  return _IoProcessHealth(server);
}

final class _IoProcessHealth implements DVProcessHealth {
  _IoProcessHealth(this._server);

  final HttpServer _server;
  bool _closed = false;

  @override
  int get port => _server.port;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _server.close(force: true);
  }
}
