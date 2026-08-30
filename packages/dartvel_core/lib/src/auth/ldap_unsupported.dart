/// The LDAP surface on platforms without a socket.
///
/// LDAP is a raw TCP protocol, so a browser cannot speak it: there is no
/// socket to open and no way to send BER. The types exist here so code that
/// mentions them still compiles for web, and every entry point throws rather
/// than returning a plausible answer.
///
/// The alternative -- exporting the real implementation everywhere -- is what
/// broke the web build when this was first added: `dart:io` is not available
/// there, and the failure surfaced as a cascade of unrelated type errors in a
/// different file.
library dartvel_core.auth.ldap_unsupported;

/// Thrown when a directory refuses or cannot be reached.
class DVLdapException implements Exception {
  const DVLdapException(this.message, {this.resultCode});

  final String message;
  final int? resultCode;

  @override
  String toString() => resultCode == null
      ? 'DVLdapException: $message'
      : 'DVLdapException($resultCode): $message';
}

/// A directory entry: its DN and the attributes that came back.
class DVLdapEntry {
  const DVLdapEntry(this.dn, this.attributes);

  final String dn;
  final Map<String, List<String>> attributes;

  String? first(String name) {
    for (final MapEntry<String, List<String>> entry in attributes.entries) {
      if (entry.key.toLowerCase() == name.toLowerCase()) {
        return entry.value.isEmpty ? null : entry.value.first;
      }
    }
    return null;
  }
}

/// BER encoding, which is pure arithmetic and works anywhere.
///
/// Kept identical rather than stubbed: nothing about encoding a length needs a
/// socket, and a caller inspecting a request on web should see the real bytes.
class DVBer {
  const DVBer._();

  static const int sequence = 0x30;
  static const int integer = 0x02;
  static const int octetString = 0x04;
  static const int enumerated = 0x0a;
  static const int boolean = 0x01;
  static const int set = 0x31;

  static const int bindRequest = 0x60;
  static const int bindResponse = 0x61;
  static const int unbindRequest = 0x42;
  static const int searchRequest = 0x63;
  static const int searchResultEntry = 0x64;
  static const int searchResultDone = 0x65;

  static List<int> length(int value) {
    if (value < 0x80) return <int>[value];
    final List<int> bytes = <int>[];
    int remaining = value;
    while (remaining > 0) {
      bytes.insert(0, remaining & 0xff);
      remaining >>= 8;
    }
    return <int>[0x80 | bytes.length, ...bytes];
  }

  static List<int> tlv(int tag, List<int> content) =>
      <int>[tag, ...length(content.length), ...content];

  static List<int> int32(int value) {
    final List<int> bytes = <int>[];
    int remaining = value;
    if (remaining == 0) return tlv(integer, <int>[0]);
    while (remaining > 0) {
      bytes.insert(0, remaining & 0xff);
      remaining >>= 8;
    }
    if (bytes.first & 0x80 != 0) bytes.insert(0, 0);
    return tlv(integer, bytes);
  }

  static List<int> string(String value) =>
      tlv(octetString, _utf8(value));

  /// UTF-8 without importing dart:convert's whole surface here.
  static List<int> _utf8(String value) {
    final List<int> out = <int>[];
    for (final int rune in value.runes) {
      if (rune < 0x80) {
        out.add(rune);
      } else if (rune < 0x800) {
        out..add(0xc0 | (rune >> 6))..add(0x80 | (rune & 0x3f));
      } else if (rune < 0x10000) {
        out
          ..add(0xe0 | (rune >> 12))
          ..add(0x80 | ((rune >> 6) & 0x3f))
          ..add(0x80 | (rune & 0x3f));
      } else {
        out
          ..add(0xf0 | (rune >> 18))
          ..add(0x80 | ((rune >> 12) & 0x3f))
          ..add(0x80 | ((rune >> 6) & 0x3f))
          ..add(0x80 | (rune & 0x3f));
      }
    }
    return out;
  }
}

const String _noSocket =
    'LDAP needs a TCP socket, which this platform does not have. Authenticate '
    'through a backend function instead of from the client.';

/// An LDAP connection, which cannot be opened here.
class DVLdapClient {
  DVLdapClient._();

  static Future<DVLdapClient> connect({
    required String host,
    int port = 389,
    bool useTls = false,
    Duration timeout = const Duration(seconds: 10),
    bool allowBadCertificate = false,
  }) =>
      throw UnsupportedError(_noSocket);

  Future<bool> bind(String dn, String password) =>
      throw UnsupportedError(_noSocket);

  Future<List<DVLdapEntry>> search({
    required String baseDn,
    required String filter,
    List<String> attributes = const <String>[],
    int scope = 2,
    int sizeLimit = 10,
  }) =>
      throw UnsupportedError(_noSocket);

  Future<void> close() async {}
}

/// Authentication against a directory, which cannot happen here.
class DVLdapAuthenticator {
  const DVLdapAuthenticator({
    required this.host,
    required this.baseDn,
    this.port = 389,
    this.useTls = false,
    this.bindDn,
    this.bindPassword,
    this.userFilter = 'uid',
    this.attributes = const <String>['cn', 'mail', 'uid'],
    this.allowBadCertificate = false,
  });

  final String host;
  final int port;
  final bool useTls;
  final String baseDn;
  final String? bindDn;
  final String? bindPassword;
  final String userFilter;
  final List<String> attributes;
  final bool allowBadCertificate;

  Future<DVLdapEntry?> authenticate(String username, String password) =>
      throw UnsupportedError(_noSocket);
}
