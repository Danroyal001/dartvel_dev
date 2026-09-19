/// Reads the pages Studio deployed from the app's own backend, for an app
/// installed on a device: a phone, a desktop, a TV or a board.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dartvel_core/dartvel.dart' show dvPublishedPagesPath;

import '../../dartvel_flutter.dart' show DV;
import 'page_document.dart' show DVPageDocument;

/// The deployed documents, from `DV.baseUrl` + `/_dartvel/pages`.
///
/// Throws when the backend does not answer, which the page store reads as
/// "serve the compiled pages": a phone on a train still opens.
Future<List<DVPageDocument>> dvDeployedPagesFromBackend() async {
  final Uri uri = Uri.parse(DV.baseUrl).resolve(dvPublishedPagesPath);
  final HttpClient client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 5);
  try {
    final HttpClientRequest request =
        await client.getUrl(uri).timeout(const Duration(seconds: 5));
    final HttpClientResponse response =
        await request.close().timeout(const Duration(seconds: 5));
    final String text = await response
        .transform(utf8.decoder)
        .join()
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw HttpException('${response.statusCode} from $uri', uri: uri);
    }
    final Object? body = jsonDecode(text);
    if (body is! Map || body['pages'] is! List) {
      throw FormatException('No pages list from $uri');
    }
    return <DVPageDocument>[
      for (final Object? page in body['pages']! as List)
        if (page is Map && page['document'] is Map)
          DVPageDocument.fromJson(
              (page['document']! as Map).cast<String, Object?>()),
    ];
  } finally {
    client.close(force: true);
  }
}
