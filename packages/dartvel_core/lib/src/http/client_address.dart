/// Who a request came from, for everything that counts or decides per source:
/// velocity limits on sign-in and sign-up, the rate limit, the WAF's trust in
/// a proxy-set header.
///
/// One resolver, because each of those used to derive the address its own way
/// and all of them took the first `X-Forwarded-For` entry -- which is whatever
/// the client wrote. A client escaped every per-source limit by writing a new
/// one per request, and every request that wrote none shared one bucket.
///
/// The rule:
///
/// * the connection's peer address is the client, unless
/// * the peer is a proxy the application trusts, in which case the forwarded
///   chain is walked from the right -- the entry the nearest proxy appended --
///   and the first hop that is not itself a trusted proxy is the client;
/// * a hop that does not parse stops the walk, and nothing to its left is
///   read: a proxy that appends writes a valid address, so garbage can only
///   have come from the client;
/// * no peer address is no client address. Never a header instead.
library dartvel_core.http.client_address;

import 'peer_address.dart';
import 'wintercg.dart';

/// Which forwarding header the trusted proxies write.
///
/// One, deliberately. A proxy that writes one passes the other through as the
/// client sent it -- Caddy overwrites `X-Forwarded-For` and leaves
/// `Forwarded` alone -- so a resolver that read both would read the client's.
enum DVForwardedHeader {
  /// `X-Forwarded-For: client, proxy1, proxy2`. What Caddy, nginx, HAProxy,
  /// and the major load balancers and CDNs write.
  xForwardedFor('x-forwarded-for'),

  /// RFC 7239 `Forwarded: for=client, for=proxy1`.
  forwarded('forwarded');

  const DVForwardedHeader(this.headerName);

  final String headerName;

  /// The configuration spelling: `x-forwarded-for` or `forwarded`.
  static DVForwardedHeader parse(String text) {
    final String name = text.trim().toLowerCase();
    for (final DVForwardedHeader header in values) {
      if (header.headerName == name) return header;
    }
    throw FormatException(
      'forwardedHeader must be x-forwarded-for or forwarded, not "$text". '
      'A trusted proxy writes one of the two, and any other header is one a '
      'client can set.',
    );
  }
}

/// An address range: `10.0.0.0/8`, `2001:db8::/32`, or a bare address as the
/// single host it names.
final class DVCidr {
  DVCidr._(this.network, this.prefixLength);

  final DVIpAddress network;
  final int prefixLength;

  /// Parses [text], refusing anything that is not exactly a range.
  ///
  /// A range with bits set past its prefix (`10.0.0.1/8`) is refused rather
  /// than masked: it is almost always a single host somebody meant to write
  /// as `/32`, and trusting the whole /8 instead is the mistake that makes a
  /// client a proxy.
  static DVCidr parse(String text) {
    FormatException refuse(String why) => FormatException(
          '"$text" is not an address range: $why. Write one as 10.0.0.0/8, '
          '2001:db8::/32, or a single address.',
        );
    final List<String> parts = text.split('/');
    if (parts.length > 2) throw refuse('it has more than one /');
    final String host = parts.first;
    // An IPv4-mapped IPv6 range is written against 128 bits; the address
    // parses to its four, so the prefix moves with it.
    final bool writtenAsV6 = host.contains(':');
    final DVIpAddress? address = DVIpAddress.tryParse(host);
    if (address == null) throw refuse('"$host" is not an IPv4 or IPv6 address');
    final int writtenBits = writtenAsV6 ? 128 : 32;
    int prefix = writtenBits;
    if (parts.length == 2) {
      final String bits = parts[1];
      if (bits.isEmpty ||
          bits.length > 3 ||
          (bits.length > 1 && bits.startsWith('0')) ||
          bits.codeUnits.any((int u) => u < 0x30 || u > 0x39)) {
        throw refuse('"$bits" is not a prefix length');
      }
      prefix = int.parse(bits);
      if (prefix > writtenBits) {
        throw refuse('the prefix is longer than $writtenBits bits');
      }
    }
    if (writtenAsV6 && address.isIPv4) {
      if (prefix < 96) {
        throw refuse('an IPv4-mapped range needs a prefix of at least 96');
      }
      prefix -= 96;
    }
    final List<int> bytes = address.bytes;
    for (int bit = prefix; bit < bytes.length * 8; bit++) {
      if ((bytes[bit >> 3] >> (7 - (bit & 7))) & 1 == 1) {
        throw refuse('it has address bits set past /$prefix');
      }
    }
    return DVCidr._(address, prefix);
  }

  /// [parse], or null.
  static DVCidr? tryParse(String text) {
    try {
      return parse(text);
    } on FormatException {
      return null;
    }
  }

  /// Whether [address] is in this range. An IPv4 range never contains an IPv6
  /// address or the reverse; an IPv4-mapped address is IPv4.
  bool contains(DVIpAddress address) {
    if (address.isIPv4 != network.isIPv4) return false;
    final List<int> a = address.bytes;
    final List<int> n = network.bytes;
    final int whole = prefixLength >> 3;
    for (int i = 0; i < whole; i++) {
      if (a[i] != n[i]) return false;
    }
    final int rest = prefixLength & 7;
    if (rest == 0) return true;
    final int mask = (0xff << (8 - rest)) & 0xff;
    return (a[whole] & mask) == (n[whole] & mask);
  }

  @override
  bool operator ==(Object other) =>
      other is DVCidr &&
      other.network == network &&
      other.prefixLength == prefixLength;

  @override
  int get hashCode => Object.hash(network, prefixLength);

  @override
  String toString() => '$network/$prefixLength';
}

/// Resolves the client address of a request. See the library documentation
/// for the rule.
final class DVClientAddress {
  const DVClientAddress({
    this.trustedProxies = const <DVCidr>[],
    this.forwardedHeader = DVForwardedHeader.xForwardedFor,
  });

  /// From configuration text, refusing a range or header name that does not
  /// parse. Nothing is skipped: a trusted proxy that silently is not one
  /// sends every client into the proxy's bucket.
  factory DVClientAddress.parse(
    Iterable<String> trustedProxies, {
    String? forwardedHeader,
  }) =>
      DVClientAddress(
        trustedProxies: List<DVCidr>.unmodifiable(
            trustedProxies.map((String c) => DVCidr.parse(c.trim()))),
        forwardedHeader: forwardedHeader == null
            ? DVForwardedHeader.xForwardedFor
            : DVForwardedHeader.parse(forwardedHeader),
      );

  /// What the generated backend starts with: `dartvel.server.trustedProxies`
  /// and `dartvel.server.forwardedHeader` from the pubspec, plus the ranges in
  /// [trustedProxiesVariable] -- which is how a provisioned host names the
  /// proxy it put in front of the process.
  factory DVClientAddress.fromConfiguration({
    Iterable<String> trustedProxies = const <String>[],
    String? forwardedHeader,
    Map<String, String> environment = const <String, String>{},
  }) {
    final String? fromEnvironment = environment[trustedProxiesVariable];
    final List<String> all = <String>[
      ...trustedProxies,
      if (fromEnvironment != null)
        for (final String c in fromEnvironment.split(','))
          if (c.trim().isNotEmpty) c.trim(),
    ];
    try {
      return DVClientAddress.parse(all, forwardedHeader: forwardedHeader);
    } on FormatException catch (error) {
      throw FormatException(
        'dartvel.server.trustedProxies, or $trustedProxiesVariable: '
        '${error.message}',
      );
    }
  }

  /// The environment variable a deployment adds trusted proxy ranges with,
  /// comma-separated.
  static const String trustedProxiesVariable = 'DARTVEL_TRUSTED_PROXIES';

  /// The source of a request that has no peer address. One bucket for all of
  /// them, rather than any header's say.
  static const String unknownSource = 'unknown';

  /// The most forwarded hops walked. A longer chain is not a real one.
  static const int maxHops = 32;

  final List<DVCidr> trustedProxies;
  final DVForwardedHeader forwardedHeader;

  static DVClientAddress _installed = const DVClientAddress();

  /// The resolver this process uses. Trusts no proxy until one is installed,
  /// which is the only safe default: an unconfigured server behind a proxy
  /// counts the proxy, and one without a proxy counts its clients.
  static DVClientAddress get current => _installed;

  static void install(DVClientAddress resolver) => _installed = resolver;

  /// Back to trusting no proxy, for tests.
  static void reset() => _installed = const DVClientAddress();

  /// The installed resolver's answer as a key: the canonical address, or
  /// [unknownSource].
  static String sourceOf(Object? request) =>
      current.resolve(request)?.toString() ?? unknownSource;

  bool trusts(DVIpAddress address) =>
      trustedProxies.any((DVCidr range) => range.contains(address));

  /// Whether [request] arrived directly from a trusted proxy, so a header that
  /// proxy sets can be believed.
  bool peerIsTrusted(Object? request) {
    final DVIpAddress? peer = peerOf(request)?.address;
    return peer != null && trusts(peer);
  }

  /// The client address of [request], or null when it has no peer address.
  DVIpAddress? resolve(Object? request) {
    final DVIpAddress? peer = peerOf(request)?.address;
    if (peer == null) return null;
    if (!trusts(peer)) return peer;

    final List<DVIpAddress?> hops = _hops(_headerValues(request));
    DVIpAddress client = peer;
    final int stop = hops.length > maxHops ? hops.length - maxHops : 0;
    for (int i = hops.length - 1; i >= stop; i--) {
      final DVIpAddress? hop = hops[i];
      if (hop == null) return client;
      client = hop;
      if (!trusts(hop)) return hop;
    }
    return client;
  }

  /// The peer address a request carries: [Request.peerAddress], or a map's
  /// `peerAddress`. Nothing else is a peer address.
  static DVPeerAddress? peerOf(Object? request) {
    if (request is Request) return request.peerAddress;
    if (request is Map) {
      final Object? peer = request['peerAddress'];
      if (peer is DVPeerAddress) return peer;
      if (peer is String) return DVPeerAddress.tryParse(peer.trim());
    }
    return null;
  }

  List<String> _headerValues(Object? request) {
    final String name = forwardedHeader.headerName;
    if (request is Request) return request.headers.getAll(name).toList();
    if (request is Map) {
      final Object? headers = request['headers'];
      if (headers is Map) {
        final List<String> out = <String>[];
        for (final MapEntry<Object?, Object?> entry in headers.entries) {
          if ('${entry.key}'.toLowerCase() != name) continue;
          final Object? value = entry.value;
          if (value is Iterable) {
            out.addAll(value.map((Object? v) => '$v'));
          } else if (value != null) {
            out.add('$value');
          }
        }
        return out;
      }
    }
    return const <String>[];
  }

  /// Every hop, left to right; null where one does not parse.
  List<DVIpAddress?> _hops(List<String> values) {
    final List<DVIpAddress?> out = <DVIpAddress?>[];
    for (final String value in values) {
      for (final String element in _splitList(value)) {
        out.add(switch (forwardedHeader) {
          DVForwardedHeader.xForwardedFor =>
            DVPeerAddress.tryParse(element.trim())?.address,
          DVForwardedHeader.forwarded => _forwardedFor(element),
        });
      }
    }
    return out;
  }

  /// A header list split on commas outside quoted strings. An empty element
  /// is kept, and parses as nothing.
  static List<String> _splitList(String value) {
    final List<String> out = <String>[];
    final StringBuffer current = StringBuffer();
    bool quoted = false;
    for (int i = 0; i < value.length; i++) {
      final String c = value[i];
      if (c == '"') quoted = !quoted;
      if (c == ',' && !quoted) {
        out.add(current.toString());
        current.clear();
      } else {
        current.write(c);
      }
    }
    out.add(current.toString());
    return out;
  }

  /// The address in one `Forwarded` element's `for=`, or null for a missing,
  /// obfuscated, `unknown` or malformed node.
  static DVIpAddress? _forwardedFor(String element) {
    DVIpAddress? found;
    for (final String pair in element.split(';')) {
      final int eq = pair.indexOf('=');
      if (eq < 0) continue;
      if (pair.substring(0, eq).trim().toLowerCase() != 'for') continue;
      if (found != null) return null;
      String node = pair.substring(eq + 1).trim();
      if (node.startsWith('"')) {
        if (node.length < 2 || !node.endsWith('"')) return null;
        node = node.substring(1, node.length - 1);
      }
      found = DVPeerAddress.tryParse(node)?.address;
      if (found == null) return null;
    }
    return found;
  }
}
