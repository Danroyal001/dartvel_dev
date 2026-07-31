/// Shared HTTP seam for Dartvel's outbound provider adapters.
///
/// Adapters take a [DVHttpSend] rather than reaching for a client directly, so
/// tests drive the exact wire format without network access.
library dartvel_core.http.transport;

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

  const DVHttpResponse({required this.statusCode, required this.body});

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
    return DVHttpResponse(
      statusCode: streamed.statusCode,
      body: await streamed.stream.bytesToString(),
    );
  } finally {
    client.close();
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

/// `application/x-www-form-urlencoded` body. Repeated keys are supported
/// because several mail APIs express multiple recipients that way.
List<int> dvEncodeFormBody(List<(String, String)> fields) => utf8.encode(
      fields
          .map((field) =>
              '${Uri.encodeQueryComponent(field.$1)}='
              '${Uri.encodeQueryComponent(field.$2)}')
          .join('&'),
    );
