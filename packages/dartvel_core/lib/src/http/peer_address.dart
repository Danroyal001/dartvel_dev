/// Addresses as values: an IP address, and the socket address a connection
/// came from.
///
/// Every per-source limit compares these, so equality is by meaning rather
/// than by spelling. An IPv4 client of a dual-stack socket arrives as
/// `::ffff:a.b.c.d`; kept in that form it compares unequal to `a.b.c.d` in a
/// trusted-proxy list and in every limit, which is a limit that silently
/// counts one host as two. So an IPv4-mapped address is its IPv4 address here,
/// and an IPv6 address prints one way whatever way it was written.
///
/// Pure Dart, no `dart:io`: the request type lives on both sides of the wire.
library dartvel_core.http.peer_address;

import 'dart:typed_data';

/// An IPv4 or IPv6 address.
final class DVIpAddress {
  DVIpAddress._(this._bytes);

  /// Four bytes for IPv4, sixteen for IPv6. An IPv4-mapped IPv6 address is
  /// stored as its four.
  final Uint8List _bytes;

  /// Parses [text] as a bare address: dotted-quad IPv4 or RFC 4291 IPv6, with
  /// no port, brackets, zone or surrounding space.
  ///
  /// Strict on purpose. IPv4 with a leading zero is refused, because some
  /// parsers read `010` as octal and one address written two ways is one
  /// source counted as two.
  static DVIpAddress? tryParse(String text) {
    if (text.isEmpty || text.length > 45) return null;
    if (text.contains(':')) {
      final Uint8List? bytes = _parseIPv6(text);
      return bytes == null ? null : DVIpAddress._(_canonical(bytes));
    }
    final Uint8List? bytes = _parseIPv4(text);
    return bytes == null ? null : DVIpAddress._(bytes);
  }

  /// [tryParse], throwing a [FormatException] naming [text].
  static DVIpAddress parse(String text) =>
      tryParse(text) ??
      (throw FormatException('"$text" is not an IPv4 or IPv6 address'));

  /// The address from its bytes: four for IPv4, sixteen for IPv6.
  static DVIpAddress fromBytes(List<int> bytes) {
    if ((bytes.length != 4 && bytes.length != 16) ||
        bytes.any((int b) => b < 0 || b > 255)) {
      throw ArgumentError.value(bytes, 'bytes', 'is not 4 or 16 octets');
    }
    return DVIpAddress._(_canonical(Uint8List.fromList(bytes)));
  }

  bool get isIPv4 => _bytes.length == 4;

  /// The address's octets, most significant first.
  List<int> get bytes => List<int>.unmodifiable(_bytes);

  @override
  bool operator ==(Object other) {
    if (other is! DVIpAddress || other._bytes.length != _bytes.length) {
      return false;
    }
    for (int i = 0; i < _bytes.length; i++) {
      if (other._bytes[i] != _bytes[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_bytes);

  /// Dotted quad for IPv4; RFC 5952 form for IPv6.
  @override
  String toString() {
    if (isIPv4) return _bytes.join('.');
    final List<int> groups = <int>[
      for (int i = 0; i < 16; i += 2) (_bytes[i] << 8) | _bytes[i + 1],
    ];
    // The longest run of two or more zero groups, the first on a tie.
    int bestStart = -1;
    int bestLength = 1;
    for (int i = 0; i < 8;) {
      if (groups[i] != 0) {
        i++;
        continue;
      }
      int j = i;
      while (j < 8 && groups[j] == 0) {
        j++;
      }
      if (j - i > bestLength) {
        bestStart = i;
        bestLength = j - i;
      }
      i = j;
    }
    String hex(Iterable<int> part) =>
        part.map((int g) => g.toRadixString(16)).join(':');
    if (bestStart < 0) return hex(groups);
    return '${hex(groups.take(bestStart))}::'
        '${hex(groups.skip(bestStart + bestLength))}';
  }

  static Uint8List? _parseIPv4(String text) {
    final List<String> parts = text.split('.');
    if (parts.length != 4) return null;
    final Uint8List out = Uint8List(4);
    for (int i = 0; i < 4; i++) {
      final String part = parts[i];
      if (part.isEmpty || part.length > 3) return null;
      if (part.length > 1 && part.startsWith('0')) return null;
      int value = 0;
      for (final int unit in part.codeUnits) {
        if (unit < 0x30 || unit > 0x39) return null;
        value = value * 10 + (unit - 0x30);
      }
      if (value > 255) return null;
      out[i] = value;
    }
    return out;
  }

  static Uint8List? _parseIPv6(String text) {
    // A zone is not part of the address; a caller that has one strips it.
    if (text.contains('%') || text.contains('[') || text.contains(']')) {
      return null;
    }
    final int gap = text.indexOf('::');
    if (gap >= 0 && text.indexOf('::', gap + 1) >= 0) return null;

    List<int>? groups(String side) {
      if (side.isEmpty) return <int>[];
      final List<String> pieces = side.split(':');
      final List<int> out = <int>[];
      for (int i = 0; i < pieces.length; i++) {
        final String piece = pieces[i];
        if (i == pieces.length - 1 && piece.contains('.')) {
          final Uint8List? v4 = _parseIPv4(piece);
          if (v4 == null) return null;
          out
            ..add((v4[0] << 8) | v4[1])
            ..add((v4[2] << 8) | v4[3]);
          continue;
        }
        if (piece.isEmpty || piece.length > 4) return null;
        final int? value = int.tryParse(piece, radix: 16);
        if (value == null || piece.contains(RegExp('[^0-9a-fA-F]'))) {
          return null;
        }
        out.add(value);
      }
      return out;
    }

    final List<int> all;
    if (gap < 0) {
      final List<int>? whole = groups(text);
      if (whole == null || whole.length != 8) return null;
      all = whole;
    } else {
      final List<int>? head = groups(text.substring(0, gap));
      final List<int>? tail = groups(text.substring(gap + 2));
      if (head == null || tail == null) return null;
      // `::` stands for at least one zero group.
      if (head.length + tail.length > 7) return null;
      all = <int>[
        ...head,
        for (int i = head.length + tail.length; i < 8; i++) 0,
        ...tail,
      ];
    }
    final Uint8List out = Uint8List(16);
    for (int i = 0; i < 8; i++) {
      out[i * 2] = all[i] >> 8;
      out[i * 2 + 1] = all[i] & 0xff;
    }
    return out;
  }

  /// `::ffff:a.b.c.d` as `a.b.c.d`; anything else unchanged.
  static Uint8List _canonical(Uint8List bytes) {
    if (bytes.length != 16) return bytes;
    for (int i = 0; i < 10; i++) {
      if (bytes[i] != 0) return bytes;
    }
    if (bytes[10] != 0xff || bytes[11] != 0xff) return bytes;
    return Uint8List.fromList(bytes.sublist(12));
  }
}

/// The address and, when known, the port at the other end of a connection.
///
/// A server sets it from the socket. Nothing a client sends can change it,
/// which is the whole of its value: every header is something the client
/// chose.
final class DVPeerAddress {
  const DVPeerAddress(this.address, {this.port});

  final DVIpAddress address;

  /// The peer's port, 0-65535, or null when the server did not say.
  final int? port;

  /// Reads `1.2.3.4`, `1.2.3.4:80`, `2001:db8::1`, `[2001:db8::1]` and
  /// `[2001:db8::1]:80`. A zone on an IPv6 address (`[fe80::1%2]:80`) is
  /// dropped: it names an interface on this host, not a different peer.
  static DVPeerAddress? tryParse(String text) {
    if (text.isEmpty || text.length > 64) return null;
    String host;
    String? port;
    if (text.startsWith('[')) {
      final int close = text.indexOf(']');
      if (close < 0) return null;
      host = text.substring(1, close);
      final String rest = text.substring(close + 1);
      if (rest.isNotEmpty) {
        if (!rest.startsWith(':')) return null;
        port = rest.substring(1);
      }
    } else {
      final int first = text.indexOf(':');
      if (first >= 0 && first == text.lastIndexOf(':')) {
        // One colon: IPv4 with a port. Two or more is a bare IPv6 address.
        host = text.substring(0, first);
        port = text.substring(first + 1);
      } else {
        host = text;
      }
    }
    final int zone = host.indexOf('%');
    if (zone >= 0 && host.contains(':')) host = host.substring(0, zone);
    final DVIpAddress? address = DVIpAddress.tryParse(host);
    if (address == null) return null;
    if (port == null) return DVPeerAddress(address);
    if (port.isEmpty ||
        port.length > 5 ||
        port.codeUnits.any((int u) => u < 0x30 || u > 0x39)) {
      return null;
    }
    final int value = int.parse(port);
    if (value > 65535) return null;
    return DVPeerAddress(address, port: value);
  }

  /// [tryParse], throwing a [FormatException] naming [text].
  static DVPeerAddress parse(String text) =>
      tryParse(text) ??
      (throw FormatException('"$text" is not a socket address'));

  @override
  bool operator ==(Object other) =>
      other is DVPeerAddress && other.address == address && other.port == port;

  @override
  int get hashCode => Object.hash(address, port);

  @override
  String toString() {
    if (port == null) return address.toString();
    return address.isIPv4 ? '$address:$port' : '[$address]:$port';
  }
}
