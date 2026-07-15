library dartvel_core;

import 'dart:async';
import 'dart:convert';
// import 'dart:io'; // Removed to avoid breaking web builds
import 'package:dartvel_shelf/dartvel_shelf.dart' as dv;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';

// Re-export common types so backends can import only dartvel_core.
export 'package:dartvel_shelf/dartvel_shelf.dart'
    show Request, Response, Headers;

export 'src/analytics/analytics.dart';
export 'src/annotations/annotations.dart';
export 'src/platform_config.dart';

typedef RequestType = dv.Request;
typedef ResponseType = dv.Response;

// Simple HeaderValue parser to avoid dart:io dependency
class _HeaderValue {
  final String value;
  final Map<String, String> parameters;

  _HeaderValue(this.value, this.parameters);

  static _HeaderValue parse(String headerValue) {
    final parts = headerValue.split(';');
    final value = parts.first.trim();
    final parameters = <String, String>{};
    for (var i = 1; i < parts.length; i++) {
      final part = parts[i].trim();
      final index = part.indexOf('=');
      if (index != -1) {
        final key = part.substring(0, index).trim();
        var val = part.substring(index + 1).trim();
        if (val.startsWith('"') && val.endsWith('"')) {
          val = val.substring(1, val.length - 1);
        }
        parameters[key] = val;
      }
    }
    return _HeaderValue(value, parameters);
  }
}

extension RequestFormData on dv.Request {
  Future<Map<String, dynamic>> formData() async {
    final contentType = headers.get('content-type');
    if (contentType == null) return {};

    final mediaType = MediaType.parse(contentType);
    if (mediaType.mimeType == 'application/x-www-form-urlencoded') {
      final text = await body.text();
      return Uri.splitQueryString(text);
    }

    if (mediaType.mimeType == 'multipart/form-data') {
      final boundary = mediaType.parameters['boundary'];
      if (boundary == null) return {};

      final transformer = MimeMultipartTransformer(boundary);
      final parts = body.stream.transform(transformer);

      final data = <String, dynamic>{};

      await for (final part in parts) {
        final contentDisposition = part.headers['content-disposition'];
        if (contentDisposition != null) {
          final header = _HeaderValue.parse(contentDisposition);
          final name = header.parameters['name'];
          final filename = header.parameters['filename'];

          if (name != null) {
            if (filename != null) {
              // It's a file
              final bytes =
                  await part.fold<List<int>>([], (p, e) => p..addAll(e));
              data[name] = MultipartFile(
                filename: filename,
                contentType: part.headers['content-type'],
                bytes: bytes,
              );
            } else {
              // It's a field
              final value = await utf8.decodeStream(part);
              data[name] = value;
            }
          }
        }
      }
      return data;
    }

    return {};
  }
}

class MultipartFile {
  final String filename;
  final String? contentType;
  final List<int> bytes;

  MultipartFile({
    required this.filename,
    this.contentType,
    required this.bytes,
  });

  @override
  String toString() =>
      'MultipartFile(filename: $filename, bytes: ${bytes.length})';
}

class Res {
  static dv.Response json(Object data,
          {int status = 200, Map<String, String>? headers}) =>
      dv.Response(status,
          headers: dv.Headers(
              {'content-type': 'application/json; charset=utf-8', ...?headers}),
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
        .map((e) => 'data: ${e.replaceAll('\n', '\ndata: ')}\n\n')
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
