library dartvel_core;

import 'dart:async';
import 'dart:convert';
import 'package:dartvel_shelf/dartvel_shelf.dart' as dv;

// Re-export common types so backends can import only dartvel_core.
export 'package:dartvel_shelf/dartvel_shelf.dart' show Request, Response, Headers;

typedef RequestType = dv.Request;
typedef ResponseType = dv.Response;

class Res {
  static dv.Response json(Object data,
          {int status = 200, Map<String, String>? headers}) =>
      dv.Response(status,
          headers: dv.Headers({
            'content-type': 'application/json; charset=utf-8',
            ...?headers
          }),
          body: Stream<List<int>>.value(utf8.encode(jsonEncode(data))));

  static dv.Response text(String data,
          {int status = 200, Map<String, String>? headers}) =>
      dv.Response.text(data,
          status: status, headers: dv.Headers(headers ?? const {}));

  static dv.Response bytes(List<int> data,
          {int status = 200, Map<String, String>? headers}) =>
      dv.Response(status,
          headers: dv.Headers(headers ?? const {}),
          body: Stream<List<int>>.value(data));

  static dv.Response notFound([String message = 'Not found']) =>
      text(message, status: 404);

  static dv.Response sse(Stream<String> events,
      {int status = 200, Map<String, String>? headers}) {
    final stream = events
        .map((e) => 'data: ' + e.replaceAll('\n', '\ndata: ') + '\n\n')
        .map(utf8.encode);
    return dv.Response(status,
        headers: dv.Headers({
          'content-type': 'text/event-stream; charset=utf-8',
          'cache-control': 'no-cache',
          'connection': 'keep-alive',
          ...?headers,
        }),
        body: stream);
  }
}

// Middleware hints for dartvel_shelf (string-identifiable)
class _CorsMw {
  @override
  String toString() => 'cors';
}

Object cors() => _CorsMw();
