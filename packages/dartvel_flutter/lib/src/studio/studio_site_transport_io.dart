/// Where there is no browser: the application's own server, at `DV.baseUrl`.
library;

import 'dart:convert';
import 'dart:io';

import '../../dartvel_flutter.dart' show DV;
import 'studio_server.dart' show DVStudioReply;

Future<DVStudioReply> dvSiteSend(String method, String path, {Object? body}) async {
  final Uri uri = Uri.parse(DV.baseUrl).resolve(path);
  final HttpClient client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5);
  try {
    final HttpClientRequest request =
        await client.openUrl(method, uri).timeout(const Duration(seconds: 5));
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final HttpClientResponse response =
        await request.close().timeout(const Duration(seconds: 10));
    final String text = await response
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 10));
    Object? decoded;
    try {
      decoded = text.isEmpty ? null : jsonDecode(text);
    } on FormatException {
      decoded = <String, Object?>{'message': 'The server answered ${response.statusCode}.'};
    }
    return DVStudioReply(response.statusCode, decoded);
  } finally {
    client.close(force: true);
  }
}
