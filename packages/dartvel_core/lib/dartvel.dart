
library dartvel_core;

import 'dart:convert';
import 'package:shelf/shelf.dart';

// Re-export common Shelf types so backends can import only dartvel_core.
export 'package:shelf/shelf.dart' show Request, Response, Middleware;

typedef RequestType = Request;
typedef ResponseType = Response;

class Res {
  static Response json(Object data, {int status = 200, Map<String, String>? headers}) =>
      Response(status,
          body: jsonEncode(data),
          headers: {'content-type': 'application/json; charset=utf-8', ...?headers});

  static Response text(String data, {int status = 200, Map<String, String>? headers}) =>
      Response(status, body: data, headers: {'content-type': 'text/plain; charset=utf-8', ...?headers});

  static Response bytes(List<int> data, {int status = 200, Map<String, String>? headers}) =>
      Response(status, body: data, headers: headers);

  static Response notFound([String message = 'Not found']) => text(message, status: 404);
}

Middleware cors({
  String allowOrigin = '*',
  String allowHeaders = 'Origin, X-Requested-With, Content-Type, Accept, Authorization',
  String allowMethods = 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
}) {
  return (inner) {
    return (Request req) async {
      if (req.method == 'OPTIONS') {
        return Response.ok('',
            headers: {
              'access-control-allow-origin': allowOrigin,
              'access-control-allow-headers': allowHeaders,
              'access-control-allow-methods': allowMethods,
            });
      }
      final res = await inner(req);
      return res.change(headers: {
        'access-control-allow-origin': allowOrigin,
        'access-control-allow-headers': allowHeaders,
        'access-control-allow-methods': allowMethods,
        ...res.headers,
      });
    };
  };
}
