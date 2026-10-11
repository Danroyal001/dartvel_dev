/// The HTTP route for symbols: `PUT <api>/_dartvel/symbols/<release>/<file>`.
///
/// Kept apart from [DVSymbolIngest] so the policy (who may write, what may be
/// written) is tested without HTTP, and the HTTP (a method, a path, a body
/// cap, an answer that never echoes what it was sent) is tested without the
/// policy.
library;

import 'dart:convert';

import '../http/client_address.dart';
import '../http/wintercg.dart';
import '../middleware/body_limit.dart';
import 'symbol_ingest.dart';

abstract final class DVSymbolEndpoints {
  /// The route pattern, under the API base path.
  static const String pattern = '${DVSymbolIngest.path}/:release/:name';

  static Response _answer(DVSymbolIngestResult result) => Response(
        result.status,
        headers: Headers(<String, String>{
          'content-type': 'application/json; charset=utf-8',
        }),
        body: Stream<List<int>>.value(utf8.encode(jsonEncode(result.toJson()))),
      );

  /// Handles one upload. The caller is turned away before any of the body is
  /// read, and the body is read only up to what the ingest accepts.
  static Future<Response> put(Request request, DVSymbolIngest ingest) async {
    if (request.method != 'PUT') {
      return Response(405, headers: Headers(<String, String>{'allow': 'PUT'}));
    }
    final String source = DVClientAddress.sourceOf(request);
    final String? authorization = request.headers.get('authorization');

    final DVSymbolIngestResult? refused =
        await ingest.authorize(authorization: authorization, source: source);
    if (refused != null) return _answer(refused);

    final String release;
    final String name;
    try {
      release = Uri.decodeComponent(request.params['release'] ?? '');
      name = Uri.decodeComponent(request.params['name'] ?? '');
    } on ArgumentError {
      return _answer(const DVSymbolIngestResult(DVSymbolIngestOutcome.invalid));
    }

    if (dvDeclaredTooLarge(
        contentLength: request.headers.get('content-length'),
        limit: ingest.maxFileBytes)) {
      return _answer(const DVSymbolIngestResult(DVSymbolIngestOutcome.tooLarge));
    }
    final List<int>? body =
        await dvReadCapped(request.body.stream, ingest.maxFileBytes);
    if (body == null) {
      return _answer(const DVSymbolIngestResult(DVSymbolIngestOutcome.tooLarge));
    }
    return _answer(await ingest.accept(
      release: release,
      name: name,
      body: body,
      authorization: authorization,
      sha256: request.headers.get(DVSymbolIngest.checksumHeader),
      source: source,
    ));
  }
}
