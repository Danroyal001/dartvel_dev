/// Wire-protocol vocabulary for Dartvel's outbound HTTP.
///
/// Split from `transport.dart` because these types are the contract several
/// transports implement, not an implementation detail of any one of them.
library dartvel_core.http.protocol;

/// An HTTP wire protocol, identified by its ALPN token.
///
/// The token is the identifier that matters: protocol selection happens during
/// the TLS handshake, so this is what a transport actually negotiates with,
/// not a label attached afterwards.
enum DVHttpProtocol {
  /// HTTP/3 over QUIC. UDP, so a network that blocks or throttles UDP fails
  /// here and nowhere else — which is the reason fallback exists.
  http3('h3'),

  /// HTTP/2 over TLS. Multiplexed, and what APNS requires.
  http2('h2'),

  /// HTTP/1.1. Always reachable, and the floor of every fallback chain.
  http11('http/1.1');

  const DVHttpProtocol(this.alpn);

  /// The ALPN protocol identifier, as sent in the TLS handshake.
  final String alpn;

  /// The protocol for an ALPN token, or null when it is not one Dartvel
  /// speaks. Tolerates the `h3-29`-style draft tokens some servers still
  /// advertise.
  static DVHttpProtocol? fromAlpn(String token) {
    final normalized = token.trim().toLowerCase();
    if (normalized.startsWith('h3')) return DVHttpProtocol.http3;
    if (normalized == 'h2' || normalized == 'h2c') return DVHttpProtocol.http2;
    if (normalized == 'http/1.1' || normalized == 'http/1.0') {
      return DVHttpProtocol.http11;
    }
    return null;
  }
}

/// The order protocols are attempted in, best first.
///
/// A chain is a preference, not a requirement: a transport that cannot speak
/// an entry skips it, and one that connects stops the walk. The last entry is
/// what the request falls back to, so a chain whose floor is unreachable is a
/// chain that can fail entirely — [standard] ends at HTTP/1.1 deliberately.
class DVHttpProtocolChain {
  final List<DVHttpProtocol> protocols;

  const DVHttpProtocolChain(this.protocols);

  /// Try HTTP/3, then HTTP/2, then HTTP/1.1.
  ///
  /// The default for ordinary requests. HTTP/3 first is worth the attempt
  /// because a failed QUIC probe is cheap and a successful one avoids
  /// head-of-line blocking for the rest of the connection's life.
  static const DVHttpProtocolChain standard = DVHttpProtocolChain(
    <DVHttpProtocol>[
      DVHttpProtocol.http3,
      DVHttpProtocol.http2,
      DVHttpProtocol.http11,
    ],
  );

  /// HTTP/2 only, with no fallback.
  ///
  /// For peers that require it. APNS is the case Dartvel has: Apple's provider
  /// API is HTTP/2-only, and silently falling back to 1.1 would turn a
  /// misconfiguration into a connection error at a layer that cannot explain
  /// itself.
  static const DVHttpProtocolChain http2Only =
      DVHttpProtocolChain(<DVHttpProtocol>[DVHttpProtocol.http2]);

  /// HTTP/2 then HTTP/1.1, skipping the QUIC probe.
  ///
  /// For hosts known not to offer HTTP/3, and for networks where the UDP
  /// attempt is a measured waste rather than a cheap one.
  static const DVHttpProtocolChain noQuic = DVHttpProtocolChain(
    <DVHttpProtocol>[DVHttpProtocol.http2, DVHttpProtocol.http11],
  );

  /// HTTP/1.1 only.
  static const DVHttpProtocolChain http11Only =
      DVHttpProtocolChain(<DVHttpProtocol>[DVHttpProtocol.http11]);

  bool get isEmpty => protocols.isEmpty;

  /// This chain limited to what a transport can actually speak, in the
  /// chain's own order of preference.
  ///
  /// Preference belongs to the caller and capability to the transport, so
  /// intersecting them is how a request expresses "HTTP/3 if you have it"
  /// without asking what the transport is.
  DVHttpProtocolChain supportedBy(Set<DVHttpProtocol> capabilities) =>
      DVHttpProtocolChain(
        protocols.where(capabilities.contains).toList(growable: false),
      );

  @override
  String toString() =>
      'DVHttpProtocolChain(${protocols.map((p) => p.alpn).join(' > ')})';
}

/// One `Link` header from a 103 Early Hints response.
class DVEarlyHintLink {
  /// The linked URL, as written by the server. Relative references are kept
  /// verbatim; resolving them needs the request URL, which a link does not
  /// carry.
  final String uri;

  /// The `rel` parameter — `preload`, `preconnect`, `modulepreload`.
  final String rel;

  /// The `as` parameter, when present: `script`, `style`, `font`, `image`.
  final String? asType;

  /// Remaining parameters, lowercased keys, quotes stripped.
  final Map<String, String> parameters;

  const DVEarlyHintLink({
    required this.uri,
    required this.rel,
    this.asType,
    this.parameters = const <String, String>{},
  });

  @override
  String toString() => 'DVEarlyHintLink($uri, rel: $rel, as: $asType)';
}

/// A 103 Early Hints informational response (RFC 8297).
///
/// A server may send several of these before the final response, and may send
/// none. They carry no body: the point is to name resources the client can
/// start fetching while the origin is still deciding what the real response
/// is.
class DVEarlyHints {
  /// Headers of the informational response, lowercased keys.
  final Map<String, String> headers;

  const DVEarlyHints(this.headers);

  /// The `Link` headers, parsed.
  ///
  /// A malformed link is skipped rather than thrown, because early hints are
  /// an optimisation: failing a request over an unparseable hint would make
  /// the feature worse than not having it.
  List<DVEarlyHintLink> get links {
    final raw = headers['link'];
    if (raw == null || raw.isEmpty) return const <DVEarlyHintLink>[];
    return parseLinkHeader(raw);
  }
}

/// Parses a `Link` header field value into its entries.
///
/// Splits on commas that are outside angle brackets and quoted strings, since
/// a URL may contain a comma and so may a quoted parameter — splitting on
/// every comma is the obvious implementation and the wrong one.
List<DVEarlyHintLink> parseLinkHeader(String value) {
  final entries = <DVEarlyHintLink>[];
  for (final entry in _splitTopLevel(value, ',')) {
    final trimmed = entry.trim();
    if (trimmed.isEmpty) continue;

    final open = trimmed.indexOf('<');
    final close = trimmed.indexOf('>', open + 1);
    if (open != 0 || close < 0) continue;

    final uri = trimmed.substring(1, close);
    if (uri.isEmpty) continue;

    var rel = '';
    String? asType;
    final parameters = <String, String>{};
    for (final part in _splitTopLevel(trimmed.substring(close + 1), ';')) {
      final piece = part.trim();
      if (piece.isEmpty) continue;
      final eq = piece.indexOf('=');
      if (eq < 0) continue;
      final key = piece.substring(0, eq).trim().toLowerCase();
      var raw = piece.substring(eq + 1).trim();
      if (raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')) {
        raw = raw.substring(1, raw.length - 1);
      }
      switch (key) {
        case 'rel':
          rel = raw;
        case 'as':
          asType = raw;
        default:
          parameters[key] = raw;
      }
    }
    if (rel.isEmpty) continue;
    entries.add(DVEarlyHintLink(
      uri: uri,
      rel: rel,
      asType: asType,
      parameters: Map<String, String>.unmodifiable(parameters),
    ));
  }
  return List<DVEarlyHintLink>.unmodifiable(entries);
}

/// Splits on [separator] at nesting depth zero, ignoring separators inside
/// `<...>` and inside double-quoted strings.
List<String> _splitTopLevel(String value, String separator) {
  final parts = <String>[];
  final buffer = StringBuffer();
  var inAngle = false;
  var inQuote = false;
  var escaped = false;

  for (var i = 0; i < value.length; i++) {
    final char = value[i];
    if (escaped) {
      buffer.write(char);
      escaped = false;
      continue;
    }
    if (inQuote && char == r'\') {
      buffer.write(char);
      escaped = true;
      continue;
    }
    if (char == '"') {
      inQuote = !inQuote;
      buffer.write(char);
      continue;
    }
    if (!inQuote && char == '<') inAngle = true;
    if (!inQuote && char == '>') inAngle = false;
    if (char == separator && !inAngle && !inQuote) {
      parts.add(buffer.toString());
      buffer.clear();
      continue;
    }
    buffer.write(char);
  }
  parts.add(buffer.toString());
  return parts;
}

/// Called for each 103 response received before the final one.
typedef DVEarlyHintsCallback = void Function(DVEarlyHints hints);

/// Why a protocol attempt failed, so the fallback driver can tell a
/// "try the next one" from a "stop".
class DVHttpNegotiationFailure implements Exception {
  final DVHttpProtocol protocol;
  final Object cause;

  /// Whether a different protocol could plausibly succeed.
  ///
  /// A refused QUIC handshake is retryable — the peer may still speak
  /// HTTP/2. A 404 is not: the request reached the origin and was answered,
  /// so retrying on another protocol would just ask again.
  final bool retryable;

  const DVHttpNegotiationFailure(
    this.protocol,
    this.cause, {
    this.retryable = true,
  });

  @override
  String toString() =>
      'DVHttpNegotiationFailure(${protocol.alpn}, retryable: $retryable, '
      'cause: $cause)';
}

/// Raised when every protocol in a chain failed.
///
/// Carries each attempt rather than only the last, because "HTTP/3 timed out
/// and then HTTP/2 was refused" and "the host does not resolve" look identical
/// from the final error alone.
class DVHttpProtocolExhausted implements Exception {
  final Uri url;
  final List<DVHttpNegotiationFailure> attempts;

  const DVHttpProtocolExhausted(this.url, this.attempts);

  @override
  String toString() {
    final detail = attempts
        .map((a) => '  ${a.protocol.alpn}: ${a.cause}')
        .join('\n');
    final hint = dvHttpTransportHint;
    final suffix = hint == null ? '' : '\n$hint';
    return 'DVHttpProtocolExhausted: no protocol succeeded for $url\n$detail'
        '$suffix';
  }
}

/// Why the faster transport is not available, when something knows.
///
/// "http cannot speak h2" is accurate and tells a caller nothing they can act
/// on. Only a prebuilt Linux library is committed, so on macOS and Windows
/// without a Rust toolchain the native transport does not load and
/// `package:http` is what remains — and APNS, which requires HTTP/2, then fails
/// with a message that never mentions a library.
///
/// Set by whatever tried and failed to load a transport; null when nothing did,
/// so a machine with a working library never sees a hint about a missing one.
String? dvHttpTransportHint;
