/// LDAP authentication.
///
/// The protocol is BER-encoded ASN.1 over a raw socket, and almost every way
/// of getting it slightly wrong produces a server that closes the connection
/// with no explanation. So the encoder is written explicitly rather than
/// generated, and its output is pinned byte-for-byte in tests: a length field
/// off by one is not visible in any Dart value, only in what the far end does
/// with it.
///
/// Authentication here is two binds. The first is the service account, used to
/// find the user's distinguished name from a search filter, because a user
/// types `ada` and the directory wants `uid=ada,ou=people,dc=example,dc=test`.
/// The second is that DN with the password the user supplied: a successful
/// bind *is* the password check, and no password ever leaves the connection in
/// a form this code inspects.
library dartvel_core.auth.ldap;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Thrown when a directory refuses or cannot be reached.
class DVLdapException implements Exception {
  const DVLdapException(this.message, {this.resultCode});

  final String message;

  /// The LDAP result code, where the server gave one.
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

  /// The first value of [name], or null.
  String? first(String name) {
    for (final MapEntry<String, List<String>> entry in attributes.entries) {
      if (entry.key.toLowerCase() == name.toLowerCase()) {
        return entry.value.isEmpty ? null : entry.value.first;
      }
    }
    return null;
  }
}

// --- BER ---------------------------------------------------------------

/// BER tags this client uses. LDAP is ASN.1 with application-tagged operations.
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

  /// Encodes a length in BER's short or long form.
  ///
  /// Under 128 it is one byte; above, it is a count byte with the high bit set
  /// followed by that many length bytes. Emitting the short form for a long
  /// value is the classic bug: the server reads the first content byte as part
  /// of the length and everything after it is garbage.
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

  /// Wraps [content] in a tag-length-value triple.
  static List<int> tlv(int tag, List<int> content) =>
      <int>[tag, ...length(content.length), ...content];

  static List<int> int32(int value) {
    // Two's-complement, minimal length, with a leading zero where the top bit
    // would otherwise make a positive value read as negative.
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
      tlv(octetString, utf8.encode(value));
}

/// A parsed BER element.
class _Element {
  _Element(this.tag, this.content);

  final int tag;
  final Uint8List content;

  /// Elements nested directly inside this one.
  List<_Element> get children => _parseAll(content);

  int get asInt {
    int value = 0;
    for (final int byte in content) {
      value = (value << 8) | byte;
    }
    return value;
  }

  String get asString => utf8.decode(content, allowMalformed: true);
}

/// Reads one element at [offset]. Returns it and the offset after it.
({_Element element, int next})? _parseOne(Uint8List bytes, int offset) {
  if (offset + 2 > bytes.length) return null;
  final int tag = bytes[offset];
  int at = offset + 1;

  int length = bytes[at++];
  if (length & 0x80 != 0) {
    final int count = length & 0x7f;
    // A length claiming more bytes than remain is hostile or corrupt; reading
    // it would run off the end of the buffer.
    if (count > 4 || at + count > bytes.length) return null;
    length = 0;
    for (int i = 0; i < count; i += 1) {
      length = (length << 8) | bytes[at++];
    }
  }
  if (at + length > bytes.length) return null;

  return (
    element: _Element(tag, Uint8List.sublistView(bytes, at, at + length)),
    next: at + length,
  );
}

List<_Element> _parseAll(Uint8List bytes) {
  final List<_Element> elements = <_Element>[];
  int at = 0;
  while (at < bytes.length) {
    final ({_Element element, int next})? read = _parseOne(bytes, at);
    if (read == null) break;
    elements.add(read.element);
    at = read.next;
  }
  return elements;
}

/// An LDAP client: bind and search, which is all authentication needs.
class DVLdapClient {
  DVLdapClient._(this._socket) {
    _subscription = _socket.listen(
      _onData,
      onError: (Object error) => _failAll('$error'),
      onDone: () => _failAll('the directory closed the connection'),
    );
  }

  final Socket _socket;
  late final StreamSubscription<Uint8List> _subscription;
  final BytesBuilder _buffer = BytesBuilder();
  final Map<int, Completer<List<_Element>>> _pending =
      <int, Completer<List<_Element>>>{};
  final Map<int, List<_Element>> _collected = <int, List<_Element>>{};
  int _nextMessageId = 1;

  /// Opens a connection. [useTls] wraps it in TLS from the first byte
  /// (ldaps://), which is the deployment most directories expect.
  static Future<DVLdapClient> connect({
    required String host,
    int port = 389,
    bool useTls = false,
    Duration timeout = const Duration(seconds: 10),
    bool allowBadCertificate = false,
  }) async {
    final Socket socket = useTls
        ? await SecureSocket.connect(
            host,
            port,
            timeout: timeout,
            onBadCertificate:
                allowBadCertificate ? (X509Certificate _) => true : null,
          )
        : await Socket.connect(host, port, timeout: timeout);
    socket.setOption(SocketOption.tcpNoDelay, true);
    return DVLdapClient._(socket);
  }

  void _onData(Uint8List chunk) {
    _buffer.add(chunk);
    Uint8List pending = _buffer.toBytes();
    int consumed = 0;

    // A response may arrive split across packets or several in one; neither is
    // an error, and treating a partial message as malformed is how an LDAP
    // client works locally and fails against a real server.
    while (true) {
      final ({_Element element, int next})? read = _parseOne(pending, consumed);
      if (read == null) break;
      consumed = read.next;

      final List<_Element> parts = read.element.children;
      if (parts.length < 2) continue;
      final int messageId = parts[0].asInt;
      final _Element operation = parts[1];

      if (operation.tag == DVBer.searchResultEntry) {
        (_collected[messageId] ??= <_Element>[]).add(operation);
        continue;
      }
      final Completer<List<_Element>>? completer = _pending.remove(messageId);
      if (completer == null) continue;
      completer.complete(<_Element>[
        ...?_collected.remove(messageId),
        operation,
      ]);
    }

    _buffer.clear();
    if (consumed < pending.length) {
      _buffer.add(Uint8List.sublistView(pending, consumed));
    }
    pending = Uint8List(0);
  }

  void _failAll(String reason) {
    for (final Completer<List<_Element>> completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(DVLdapException(reason));
      }
    }
    _pending.clear();
  }

  Future<List<_Element>> _send(List<int> Function(int id) build) {
    final int id = _nextMessageId++;
    final Completer<List<_Element>> completer = Completer<List<_Element>>();
    _pending[id] = completer;
    _socket.add(build(id));
    return completer.future;
  }

  /// A simple bind. Returns whether the credentials were accepted.
  ///
  /// An empty password is refused before it reaches the directory: many
  /// servers treat a bind with a DN and no password as an *anonymous* bind and
  /// answer success, which would turn a blank password into a valid login.
  Future<bool> bind(String dn, String password) async {
    if (password.isEmpty) return false;

    final List<_Element> response = await _send((int id) {
      final List<int> request = DVBer.tlv(DVBer.bindRequest, <int>[
        ...DVBer.int32(3), // LDAP v3
        ...DVBer.string(dn),
        // Simple authentication is context tag 0, primitive.
        ...DVBer.tlv(0x80, utf8.encode(password)),
      ]);
      return DVBer.tlv(DVBer.sequence, <int>[...DVBer.int32(id), ...request]);
    });

    final _Element? result = response.isEmpty ? null : response.last;
    if (result == null || result.tag != DVBer.bindResponse) {
      throw const DVLdapException('The directory did not answer the bind.');
    }
    final List<_Element> parts = result.children;
    final int code = parts.isEmpty ? -1 : parts.first.asInt;
    if (code == 0) return true;
    // 49 is invalidCredentials, which is a failed login rather than a fault.
    if (code == 49) return false;
    throw DVLdapException(
      parts.length > 2 ? parts[2].asString : 'bind refused',
      resultCode: code,
    );
  }

  /// Searches [baseDn] for [filter], returning the entries found.
  ///
  /// [filter] is an equality match written `attribute=value`, which is what
  /// user lookup needs; anything richer belongs in the directory's own
  /// configuration rather than in a string this code assembles.
  Future<List<DVLdapEntry>> search({
    required String baseDn,
    required String filter,
    List<String> attributes = const <String>[],
    int scope = 2,
    int sizeLimit = 10,
  }) async {
    final int equals = filter.indexOf('=');
    if (equals <= 0) {
      throw DVLdapException('"$filter" is not an attribute=value filter.');
    }
    final String attribute = filter.substring(0, equals);
    final String value = filter.substring(equals + 1);

    final List<_Element> response = await _send((int id) {
      final List<int> request = DVBer.tlv(DVBer.searchRequest, <int>[
        ...DVBer.string(baseDn),
        ...DVBer.tlv(DVBer.enumerated, <int>[scope]),
        ...DVBer.tlv(DVBer.enumerated, <int>[0]), // never dereference aliases
        ...DVBer.int32(sizeLimit),
        ...DVBer.int32(30), // time limit, seconds
        ...DVBer.tlv(DVBer.boolean, <int>[0]), // want values, not just types
        // equalityMatch is context tag 3, constructed.
        ...DVBer.tlv(0xa3, <int>[
          ...DVBer.string(attribute),
          ...DVBer.string(value),
        ]),
        ...DVBer.tlv(DVBer.sequence, <int>[
          for (final String name in attributes) ...DVBer.string(name),
        ]),
      ]);
      return DVBer.tlv(DVBer.sequence, <int>[...DVBer.int32(id), ...request]);
    });

    final List<DVLdapEntry> entries = <DVLdapEntry>[];
    for (final _Element element in response) {
      if (element.tag != DVBer.searchResultEntry) continue;
      final List<_Element> parts = element.children;
      if (parts.isEmpty) continue;
      final String dn = parts.first.asString;
      final Map<String, List<String>> attributeMap = <String, List<String>>{};
      if (parts.length > 1) {
        for (final _Element attribute in parts[1].children) {
          final List<_Element> pair = attribute.children;
          if (pair.length < 2) continue;
          attributeMap[pair[0].asString] = <String>[
            for (final _Element v in pair[1].children) v.asString,
          ];
        }
      }
      entries.add(DVLdapEntry(dn, attributeMap));
    }

    final _Element done = response.last;
    if (done.tag == DVBer.searchResultDone) {
      final List<_Element> parts = done.children;
      final int code = parts.isEmpty ? -1 : parts.first.asInt;
      // 4 is sizeLimitExceeded, which still returns the entries it found.
      if (code != 0 && code != 4) {
        throw DVLdapException(
          parts.length > 2 ? parts[2].asString : 'search refused',
          resultCode: code,
        );
      }
    }
    return entries;
  }

  /// Closes the connection, sending an unbind first as the protocol asks.
  Future<void> close() async {
    try {
      _socket.add(DVBer.tlv(DVBer.sequence, <int>[
        ...DVBer.int32(_nextMessageId++),
        ...DVBer.tlv(DVBer.unbindRequest, const <int>[]),
      ]));
      await _socket.flush();
    } on Object {
      // Already gone; nothing to do.
    }
    await _subscription.cancel();
    await _socket.close();
    _socket.destroy();
  }
}

/// Authenticates against an LDAP directory.
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

  /// A service account able to search. Null for directories that permit
  /// anonymous search.
  final String? bindDn;
  final String? bindPassword;

  /// The attribute a username is matched against.
  final String userFilter;
  final List<String> attributes;
  final bool allowBadCertificate;

  /// Returns the user's entry when the password is right, null when it is not.
  ///
  /// Two binds: one to find the DN, one to check the password. The second bind
  /// *is* the check -- the password is never compared here, and no hash of it
  /// is ever read out of the directory.
  Future<DVLdapEntry?> authenticate(String username, String password) async {
    // Refused before connecting. A bind with a DN and an empty password is an
    // anonymous bind to many servers, which answers success and would make a
    // blank password a valid login for any account.
    if (password.isEmpty) return null;

    final DVLdapClient client = await DVLdapClient.connect(
      host: host,
      port: port,
      useTls: useTls,
      allowBadCertificate: allowBadCertificate,
    );

    try {
      if (bindDn != null) {
        final bool bound = await client.bind(bindDn!, bindPassword ?? '');
        if (!bound) {
          throw const DVLdapException(
            'The service account could not bind; check bindDn and '
            'bindPassword.',
          );
        }
      }

      final List<DVLdapEntry> found = await client.search(
        baseDn: baseDn,
        filter: '$userFilter=${_escapeFilter(username)}',
        attributes: attributes,
      );
      if (found.isEmpty) return null;

      // More than one match means the filter is not unique. Binding as the
      // first would authenticate whichever account the directory happened to
      // return first.
      if (found.length > 1) {
        throw DVLdapException(
          '"$username" matched ${found.length} entries under $baseDn; the '
          'filter attribute "$userFilter" is not unique.',
        );
      }

      final DVLdapEntry user = found.single;
      final bool ok = await client.bind(user.dn, password);
      return ok ? user : null;
    } finally {
      await client.close();
    }
  }

  /// Escapes the characters RFC 4515 reserves in a filter value.
  ///
  /// Without this, a username containing `*` matches every account and one
  /// containing `)` rewrites the filter -- the LDAP equivalent of SQL
  /// injection, and it authenticates rather than erroring.
  static String _escapeFilter(String value) {
    final StringBuffer out = StringBuffer();
    for (final int unit in utf8.encode(value)) {
      switch (unit) {
        case 0x2a: // *
          out.write(r'\2a');
        case 0x28: // (
          out.write(r'\28');
        case 0x29: // )
          out.write(r'\29');
        case 0x5c: // backslash
          out.write(r'\5c');
        case 0x00:
          out.write(r'\00');
        default:
          out.writeCharCode(unit);
      }
    }
    return out.toString();
  }
}
