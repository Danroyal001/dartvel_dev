/// Run existing Shelf handlers on Dartvel's native HTTP server.
library;
import 'package:dartvel_core/http.dart' as dv;
import 'package:shelf/shelf.dart' as shelf;

/// Adapts a complete Shelf pipeline, preserving its streaming bodies and
/// repeated headers. Shelf owns change(), context, encoding and middleware
/// semantics inside the pipeline. Arbitrary socket hijacking is unsupported.
Future<dv.Response> Function(dv.Request) fromShelf(shelf.Handler handler) =>
    (request) async {
      final response = await handler(shelf.Request(
        request.method,
        request.url,
        headers: request.headers.multiValueMap,
        body: request.body.stream,
        context: {
          if (request.peerAddress != null)
            'dartvel.peerAddress': request.peerAddress!,
        },
      ));
      return dv.Response(response.statusCode,
        headers: dv.Headers(response.headersAll), body: response.read());
    };
