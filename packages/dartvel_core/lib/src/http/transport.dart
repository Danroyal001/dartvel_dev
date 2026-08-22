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

import 'protocol.dart';

export 'protocol.dart';

class DVHttpRequest {
  final Uri url;
  final String method;
  final Map<String, String> headers;
  final List<int> body;

  /// Protocols to attempt, best first.
  ///
  /// A preference rather than a demand: a transport that cannot speak an entry
  /// skips it. Use [DVHttpProtocolChain.http2Only] where a peer requires a
  /// specific protocol and falling back would be wrong.
  final DVHttpProtocolChain protocols;

  /// Called for each 103 Early Hints response that arrives before the final
  /// one. Never called after the response returns.
  final DVEarlyHintsCallback? onEarlyHints;

  const DVHttpRequest({
    required this.url,
    this.method = 'POST',
    this.headers = const <String, String>{},
    this.body = const <int>[],
    this.protocols = DVHttpProtocolChain.standard,
    this.onEarlyHints,
  });

  /// A copy of this request pinned to [protocol].
  ///
  /// What the fallback driver hands a transport, so a transport is never
  /// asked to do its own negotiation across protocols.
  DVHttpRequest forProtocol(DVHttpProtocol protocol) => DVHttpRequest(
        url: url,
        method: method,
        headers: headers,
        body: body,
        protocols: DVHttpProtocolChain(<DVHttpProtocol>[protocol]),
        onEarlyHints: onEarlyHints,
      );
}

class DVHttpResponse {
  final int statusCode;
  final String body;
  final List<int>? _bytes;

  /// The protocol the response actually arrived over.
  ///
  /// Null when the transport does not report it. Worth surfacing because
  /// "HTTP/3 was requested" and "HTTP/3 was used" are different facts, and
  /// only the second one is evidence.
  final DVHttpProtocol? protocol;

  /// Early hints received before this response, in arrival order.
  final List<DVEarlyHints> earlyHints;

  const DVHttpResponse({
    required this.statusCode,
    required this.body,
    List<int>? bytes,
    this.protocol,
    this.earlyHints = const <DVEarlyHints>[],
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

  /// The protocol the response arrived over, when the transport reports it.
  final DVHttpProtocol? protocol;

  /// Early hints received before the final response, in arrival order.
  final List<DVEarlyHints> earlyHints;

  /// The body as it arrives. Listening to it is what keeps the connection
  /// open; the underlying client closes when the stream completes.
  final Stream<List<int>> body;

  const DVHttpStreamedResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
    this.protocol,
    this.earlyHints = const <DVEarlyHints>[],
  });

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}

typedef DVHttpSend = Future<DVHttpResponse> Function(DVHttpRequest request);

/// A thing that can put a request on the wire over one specific protocol.
///
/// Implementations do not negotiate across protocols; [DVHttpFallbackClient]
/// does that by calling them in order. Keeping the two apart means a new
/// transport only has to answer "can you speak this, and what happened", and
/// the fallback rules stay in one place instead of once per backend.
abstract class DVHttpTransport {
  /// Protocols this transport can actually speak here — which depends on the
  /// platform, not only on the implementation.
  Set<DVHttpProtocol> get supportedProtocols;

  /// A name for diagnostics: `package:http`, `rust`, `fetch`.
  String get name;

  /// Sends [request], which is already pinned to a single protocol.
  Future<DVHttpResponse> send(DVHttpRequest request);

  /// Sends [request] and yields the body as it arrives.
  Future<DVHttpStreamedResponse> stream(DVHttpRequest request);
}

/// Walks a request's protocol chain until one succeeds.
///
/// The chain is first narrowed to what the transport can speak, so asking for
/// HTTP/3 on a transport without QUIC costs nothing and is not an error. If
/// nothing in the chain is supported, that *is* an error — a request pinned to
/// HTTP/2 must not quietly go out over HTTP/1.1.
class DVHttpFallbackClient {
  final DVHttpTransport transport;

  const DVHttpFallbackClient(this.transport);

  Future<DVHttpResponse> send(DVHttpRequest request) =>
      _attempt(request, (r) => transport.send(r));

  Future<DVHttpStreamedResponse> stream(DVHttpRequest request) =>
      _attempt(request, (r) => transport.stream(r));

  Future<T> _attempt<T>(
    DVHttpRequest request,
    Future<T> Function(DVHttpRequest) run,
  ) async {
    final usable = request.protocols.supportedBy(transport.supportedProtocols);
    if (usable.isEmpty) {
      throw DVHttpProtocolExhausted(
        request.url,
        request.protocols.protocols
            .map((p) => DVHttpNegotiationFailure(
                  p,
                  '${transport.name} cannot speak ${p.alpn}',
                  retryable: false,
                ))
            .toList(growable: false),
      );
    }

    final failures = <DVHttpNegotiationFailure>[];
    for (final protocol in usable.protocols) {
      try {
        return await run(request.forProtocol(protocol));
      } on DVHttpNegotiationFailure catch (failure) {
        failures.add(failure);
        // A transport that says "this is not worth retrying" is reporting
        // something a different protocol cannot fix. Continuing would send the
        // same doomed request again with a different handshake.
        if (!failure.retryable) break;
      } catch (error) {
        failures.add(DVHttpNegotiationFailure(protocol, error));
      }
    }
    throw DVHttpProtocolExhausted(request.url, failures);
  }
}

/// The `package:http` transport: HTTP/1.1 everywhere, and nothing more.
///
/// `package:http` speaks neither HTTP/2 nor HTTP/3 — on native it is
/// `dart:io`'s HttpClient, which is 1.1-only. Declaring that honestly is what
/// lets the fallback driver skip the higher protocols instead of pretending to
/// have tried them.
///
/// On the web it delegates to the browser, which does negotiate HTTP/2 and
/// HTTP/3 by itself; [DVBrowserHttpTransport] is that case, stated separately
/// because the capability set genuinely differs.
class DVPackageHttpTransport implements DVHttpTransport {
  const DVPackageHttpTransport();

  @override
  String get name => 'package:http';

  @override
  Set<DVHttpProtocol> get supportedProtocols =>
      const <DVHttpProtocol>{DVHttpProtocol.http11};

  @override
  Future<DVHttpResponse> send(DVHttpRequest request) =>
      _sendWithPackageHttp(request);

  @override
  Future<DVHttpStreamedResponse> stream(DVHttpRequest request) =>
      _streamWithPackageHttp(request);
}

/// The browser's own stack, reached through `package:http` on web.
///
/// The browser negotiates HTTP/2 and HTTP/3 without being asked and acts on
/// 103 Early Hints itself, starting the preloads before the page is told
/// anything. Neither the negotiated protocol nor the hints are visible to
/// script, so this reports the capability and leaves [DVHttpResponse.protocol]
/// null: claiming a protocol it cannot observe would be a guess dressed as a
/// measurement.
class DVBrowserHttpTransport implements DVHttpTransport {
  const DVBrowserHttpTransport();

  @override
  String get name => 'fetch';

  @override
  Set<DVHttpProtocol> get supportedProtocols => const <DVHttpProtocol>{
        DVHttpProtocol.http3,
        DVHttpProtocol.http2,
        DVHttpProtocol.http11,
      };

  @override
  Future<DVHttpResponse> send(DVHttpRequest request) =>
      _sendWithPackageHttp(request);

  @override
  Future<DVHttpStreamedResponse> stream(DVHttpRequest request) =>
      _streamWithPackageHttp(request);
}

Future<DVHttpResponse> _sendWithPackageHttp(DVHttpRequest request) async {
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
Future<DVHttpStreamedResponse> _streamWithPackageHttp(
    DVHttpRequest request) async {
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

// ---------------------------------------------------------------------------
// Default transport selection
// ---------------------------------------------------------------------------

/// True when running on the web.
///
/// On the web every number is a double, so `1` and `1.0` are the same object.
/// This is the standard Dart test for it and needs no platform import, which
/// matters here because `dartvel_core` is plain Dart with no `dart:io`.
const bool dvIsWeb = identical(1, 1.0);

DVHttpTransport? _transportOverride;

/// The transport outbound requests use.
///
/// On the web this is the browser, which already negotiates HTTP/2 and HTTP/3.
/// Everywhere else it is `package:http`, which is HTTP/1.1 only — until the
/// native runtime registers a transport that can do better, at which point
/// HTTP/2 and HTTP/3 become available to native targets without a single
/// caller changing.
DVHttpTransport get dvHttpTransport =>
    _transportOverride ??
    (dvIsWeb
        ? const DVBrowserHttpTransport()
        : const DVPackageHttpTransport());

/// Installs [transport] as the default, returning the previous one.
///
/// This is the seam the Rust client attaches through, and the seam a test uses
/// to assert what was negotiated without a network.
DVHttpTransport? dvUseHttpTransport(DVHttpTransport? transport) {
  final previous = _transportOverride;
  _transportOverride = transport;
  return previous;
}

/// Sends [request], walking its protocol chain until one succeeds.
Future<DVHttpResponse> dvSendHttpRequest(DVHttpRequest request) =>
    DVHttpFallbackClient(dvHttpTransport).send(request);

/// Sends [request] and yields the body as it arrives.
///
/// Server-sent events and long-running responses cannot go through
/// [dvSendHttpRequest], which waits for the whole body: a stream that never
/// ends would never return.
Future<DVHttpStreamedResponse> dvStreamHttpRequest(DVHttpRequest request) =>
    DVHttpFallbackClient(dvHttpTransport).stream(request);
