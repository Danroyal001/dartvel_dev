/// Shared HTTP seam for Dartvel's outbound provider adapters.
///
/// Adapters take a [DVHttpSend] rather than reaching for a client directly, so
/// tests drive the exact wire format without network access.
library dartvel_core.http.transport;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class DVHttpRequest {
  final Uri url;
  final String method;
  final Map<String, String> headers;
  final List<int> body;

  const DVHttpRequest({
    required this.url,
    this.method = 'POST',
    this.headers = const <String, String>{},
    this.body = const <int>[],
  });
}

class DVHttpResponse {
  final int statusCode;
  final String body;
  final List<int>? _bytes;

  const DVHttpResponse({
    required this.statusCode,
    required this.body,
    List<int>? bytes,
  }) : _bytes = bytes;

  /// The raw response body. Falls back to encoding [body] when the transport
  /// only captured text, so binary-aware callers work with either.
  List<int> get bodyBytes => _bytes ?? utf8.encode(body);

  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  /// The body decoded as JSON, or the text when it is not JSON.
  ///
  /// Callers that expect JSON should not have to decide whether an error page
  /// or an empty body is decodable; this returns what is there either way.
  Object? get data {
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } on FormatException {
      return body;
    }
  }
}

/// A response whose body is still arriving.
class DVHttpStreamedResponse {
  final int statusCode;
  final Map<String, String> headers;

  /// The body as it arrives. Listening to it is what keeps the connection
  /// open; the underlying client closes when the stream completes.
  final Stream<List<int>> body;

  const DVHttpStreamedResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
  });

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}

typedef DVHttpSend = Future<DVHttpResponse> Function(DVHttpRequest request);

Future<DVHttpResponse> dvSendHttpRequest(DVHttpRequest request) async {
  final client = http.Client();
  try {
    final outgoing = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..bodyBytes = request.body;
    final streamed = await client.send(outgoing);
    final bytes = await streamed.stream.toBytes();
    return DVHttpResponse(
      statusCode: streamed.statusCode,
      // Binary bodies are kept verbatim; the text view tolerates non-UTF-8.
      body: utf8.decode(bytes, allowMalformed: true),
      bytes: bytes,
    );
  } finally {
    client.close();
  }
}

/// Sends [request] and yields the body as it arrives.
///
/// Server-sent events and long-running responses cannot go through
/// [dvSendHttpRequest], which waits for the whole body: a stream that never
/// ends would never return. The client stays open until the body completes,
/// so a caller that abandons the stream must cancel its subscription.
Future<DVHttpStreamedResponse> dvStreamHttpRequest(DVHttpRequest request) async {
  final client = http.Client();
  try {
    final outgoing = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..bodyBytes = request.body;
    final streamed = await client.send(outgoing);
    // Closing the client mid-body would truncate the stream, so it is closed
    // when the body ends rather than when this function returns.
    final controller = StreamController<List<int>>();
    late StreamSubscription<List<int>> subscription;
    subscription = streamed.stream.listen(
      controller.add,
      onError: controller.addError,
      onDone: () {
        client.close();
        unawaited(controller.close());
      },
      cancelOnError: false,
    );
    controller.onCancel = () async {
      await subscription.cancel();
      client.close();
    };
    return DVHttpStreamedResponse(
      statusCode: streamed.statusCode,
      headers: streamed.headers,
      body: controller.stream,
    );
  } catch (_) {
    client.close();
    rethrow;
  }
}

// ---------------------------------------------------------------------------
// Body encoding helpers
// ---------------------------------------------------------------------------

String dvGenerateMultipartBoundary([Random? random]) {
  final source = random ?? Random();
  final suffix = List<int>.generate(16, (_) => source.nextInt(36))
      .map((value) => value.toRadixString(36))
      .join();
  return '----dartvel$suffix';
}

List<int> dvEncodeMultipartBody({
  required String boundary,
  required Map<String, String> fields,
  required String fileField,
  required String fileName,
  required String fileContentType,
  required List<int> fileBytes,
}) {
  final builder = BytesBuilder();
  void writeLine(String text) => builder.add(utf8.encode('$text\r\n'));

  for (final entry in fields.entries) {
    writeLine('--$boundary');
    writeLine('content-disposition: form-data; name="${entry.key}"');
    writeLine('');
    writeLine(entry.value);
  }

  writeLine('--$boundary');
  writeLine(
    'content-disposition: form-data; name="$fileField"; '
    'filename="$fileName"',
  );
  writeLine('content-type: $fileContentType');
  writeLine('');
  builder.add(fileBytes);
  writeLine('');
  writeLine('--$boundary--');

  return builder.takeBytes();
}

/// A `multipart/form-data` body of plain fields, with no file part.
///
/// [dvEncodeMultipartBody] always writes a file; a generated form post
/// usually has none, and an empty file part is not the same message.
List<int> dvEncodeMultipartFields({
  required String boundary,
  required Map<String, String> fields,
}) {
  final builder = BytesBuilder();
  void writeLine(String text) => builder.add(utf8.encode('$text\r\n'));

  for (final entry in fields.entries) {
    writeLine('--$boundary');
    writeLine('content-disposition: form-data; name="${entry.key}"');
    writeLine('');
    writeLine(entry.value);
  }
  writeLine('--$boundary--');
  return builder.takeBytes();
}

/// `application/x-www-form-urlencoded` body. Repeated keys are supported
/// because several mail APIs express multiple recipients that way.
List<int> dvEncodeFormBody(List<(String, String)> fields) => utf8.encode(
      fields
          .map((field) =>
              '${Uri.encodeQueryComponent(field.$1)}='
              '${Uri.encodeQueryComponent(field.$2)}')
          .join('&'),
    );
