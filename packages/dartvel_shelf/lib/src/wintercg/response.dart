import 'dart:async';
import 'dart:convert';
import 'body.dart';
import 'headers.dart';

class Response {
  final int status;
  final Headers headers;
  final Stream<List<int>>? _body;
  final bool _sseNative;
  Response(this.status,
      {Headers? headers,
      Stream<List<int>>? body,
      bool sseNative = false})
      : headers = headers ?? Headers(),
        _body = body,
        _sseNative = sseNative;
  Body? get body => _body == null ? null : Body(_body!);
  bool get isSseNative => _sseNative;
  // Thin convenience: construct a Response with utf8 body.
  // No implicit headers are set here; defaults are applied by the native layer.
  static Response text(String s, {int status = 200, Headers? headers}) {
    final c = StreamController<List<int>>();
    scheduleMicrotask(() => {c.add(utf8.encode(s)), c.close()});
    return Response(status, headers: headers ?? Headers(), body: c.stream);
  }

  static Response stream(void Function(StreamSink<List<int>>) fn,
      {int status = 200, Headers? headers}) {
    final c = StreamController<List<int>>();
    scheduleMicrotask(() => fn(c.sink));
    return Response(status, headers: headers ?? Headers(), body: c.stream);
  }

  static Response sseDone() => Response(200,
      headers: Headers({'content-type': 'text/event-stream'}), sseNative: true);
}
