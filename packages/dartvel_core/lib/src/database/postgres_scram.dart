/// SCRAM-SHA-256 (RFC 5802, RFC 7677) as Postgres speaks it.
///
/// Postgres has stored passwords as SCRAM verifiers and asked for this
/// exchange by default since version 14. The client proves it knows the
/// password without sending it, and the server proves it holds the verifier,
/// so a client that checks the server's signature cannot be talked to by an
/// impostor that merely accepts whatever proof it is sent.
///
/// Pure: no socket. The adapter feeds it the server's messages and writes
/// back what it returns.
library dartvel_core.database.postgres_scram;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

/// The exchange went wrong: a malformed or dishonest server message, a
/// message out of order, or an error the server reported.
class DVScramException implements Exception {
  final String message;

  const DVScramException(this.message);

  @override
  String toString() => 'DVScramException: $message';
}

/// One client side of one SCRAM-SHA-256 exchange.
///
/// Call [clientFirstMessage], then [clientFinalMessage] with the server's
/// first message, then [verifyServerFinal] with its final one.
///
/// Channel binding (`SCRAM-SHA-256-PLUS`) is not offered: the gs2 header is
/// `n,,`, which a Postgres server accepts on plaintext and TLS alike.
///
/// The password is used as its UTF-8 bytes. RFC 5802 asks for SASLprep
/// first; for an ASCII password that is the identity, and Postgres itself
/// falls back to the raw bytes when a password is not valid SASLprep input.
/// A non-ASCII password that SASLprep would rewrite (NFKC, mapped-to-nothing
/// characters, non-ASCII spaces) is the one case that does not match.
class DVScramSha256 {
  /// The mechanism name in Postgres's AuthenticationSASL list.
  static const String mechanism = 'SCRAM-SHA-256';

  static const String _gs2Header = 'n,,';

  final String _password;
  final String _username;
  final String _clientNonce;

  String? _clientFirstBare;
  Uint8List? _expectedServerSignature;
  bool _verified = false;

  DVScramSha256({
    required String password,
    // Postgres ignores this name (the startup message already carried the
    // user) and libpq sends it empty.
    String username = '',
    String? clientNonce,
  })  : _password = password,
        _username = username,
        _clientNonce = clientNonce ?? _freshNonce();

  /// Whether the server proved it holds the password's verifier.
  bool get isVerified => _verified;

  /// `n,,n=<user>,r=<client nonce>`.
  String clientFirstMessage() {
    final String bare = 'n=${_saslName(_username)},r=$_clientNonce';
    _clientFirstBare = bare;
    return '$_gs2Header$bare';
  }

  /// The client-final message, carrying the proof, for [serverFirst].
  String clientFinalMessage(String serverFirst) {
    final String? clientFirstBare = _clientFirstBare;
    if (clientFirstBare == null) {
      throw const DVScramException(
        'The server-first message arrived before the client-first was sent.',
      );
    }
    final Map<String, String> fields = _parse(serverFirst);
    final String? serverNonce = fields['r'];
    final String? saltText = fields['s'];
    final int? iterations = int.tryParse(fields['i'] ?? '');
    if (serverNonce == null || saltText == null || iterations == null) {
      throw DVScramException('Malformed server-first message: $serverFirst');
    }
    // The server's nonce must extend ours, or this is a replay of some other
    // exchange rather than an answer to this one.
    if (!serverNonce.startsWith(_clientNonce) ||
        serverNonce.length <= _clientNonce.length) {
      throw const DVScramException(
        'The server nonce does not extend the client nonce.',
      );
    }
    if (iterations < 1) {
      throw DVScramException('Invalid iteration count: $iterations');
    }
    final Uint8List salt;
    try {
      salt = base64.decode(saltText);
    } on FormatException {
      throw DVScramException('The salt is not base64: $saltText');
    }

    final Uint8List saltedPassword =
        _pbkdf2(utf8.encode(_password), salt, iterations);
    final List<int> clientKey = _hmac(saltedPassword, utf8.encode('Client Key'));
    final List<int> storedKey = crypto.sha256.convert(clientKey).bytes;
    final List<int> serverKey = _hmac(saltedPassword, utf8.encode('Server Key'));

    final String channelBinding = base64.encode(utf8.encode(_gs2Header));
    final String withoutProof = 'c=$channelBinding,r=$serverNonce';
    final List<int> authMessage =
        utf8.encode('$clientFirstBare,$serverFirst,$withoutProof');

    final List<int> clientSignature = _hmac(storedKey, authMessage);
    final Uint8List proof = Uint8List(clientKey.length);
    for (var index = 0; index < proof.length; index++) {
      proof[index] = clientKey[index] ^ clientSignature[index];
    }
    _expectedServerSignature =
        Uint8List.fromList(_hmac(serverKey, authMessage));
    return '$withoutProof,p=${base64.encode(proof)}';
  }

  /// Checks the server's signature, and throws unless it is the one only a
  /// holder of the verifier could produce.
  void verifyServerFinal(String serverFinal) {
    final Uint8List? expected = _expectedServerSignature;
    if (expected == null) {
      throw const DVScramException(
        'The server-final message arrived before the client-final was sent.',
      );
    }
    final Map<String, String> fields = _parse(serverFinal);
    final String? error = fields['e'];
    if (error != null) {
      throw DVScramException('The server rejected the exchange: $error');
    }
    final String? signatureText = fields['v'];
    if (signatureText == null) {
      throw DVScramException('Malformed server-final message: $serverFinal');
    }
    final Uint8List signature;
    try {
      signature = base64.decode(signatureText);
    } on FormatException {
      throw const DVScramException('The server signature is not base64.');
    }
    if (!_constantTimeEquals(signature, expected)) {
      throw const DVScramException(
        'The server signature does not match: the server does not hold this '
        "password's verifier.",
      );
    }
    _verified = true;
  }

  // --- helpers --------------------------------------------------------------

  static Map<String, String> _parse(String message) {
    final Map<String, String> fields = <String, String>{};
    for (final String part in message.split(',')) {
      if (part.length < 2 || part[1] != '=') continue;
      fields.putIfAbsent(part[0], () => part.substring(2));
    }
    return fields;
  }

  /// `=` and `,` are escaped in a SASL name.
  static String _saslName(String name) =>
      name.replaceAll('=', '=3D').replaceAll(',', '=2C');

  static String _freshNonce() {
    final Random random = Random.secure();
    final List<int> bytes =
        List<int>.generate(18, (int _) => random.nextInt(256));
    // Base64 never contains a comma, and every character is printable.
    return base64.encode(bytes);
  }

  static List<int> _hmac(List<int> key, List<int> data) =>
      crypto.Hmac(crypto.sha256, key).convert(data).bytes;

  /// PBKDF2-HMAC-SHA-256 for one 32-byte block, which is SCRAM's Hi().
  static Uint8List _pbkdf2(List<int> password, List<int> salt, int iterations) {
    final crypto.Hmac hmac = crypto.Hmac(crypto.sha256, password);
    List<int> block = hmac.convert(<int>[...salt, 0, 0, 0, 1]).bytes;
    final Uint8List result = Uint8List.fromList(block);
    for (var round = 1; round < iterations; round++) {
      block = hmac.convert(block).bytes;
      for (var index = 0; index < result.length; index++) {
        result[index] ^= block[index];
      }
    }
    return result;
  }

  static bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }
}
