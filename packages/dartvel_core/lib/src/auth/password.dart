/// Password hashing for Dartvel auth providers.
library dartvel_core.auth.password;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// PBKDF2-HMAC-SHA256 password hashing.
///
/// Providers store the string returned by [hash] and check candidates with
/// [verify]. Salts are random per password, so identical passwords never
/// produce identical hashes, and verification compares in constant time.
class DVPasswordHasher {
  /// Iteration count for new hashes. Existing hashes carry their own count, so
  /// raising this does not invalidate them.
  static const int defaultIterations = 120000;

  static const int _saltBytes = 16;
  static const int _keyBytes = 32;
  static const String _algorithm = 'pbkdf2-sha256';

  final int iterations;
  final Random _random;

  DVPasswordHasher({
    this.iterations = defaultIterations,
    Random? random,
  }) : _random = random ?? Random.secure() {
    if (iterations < 1) {
      throw ArgumentError.value(
        iterations,
        'iterations',
        'PBKDF2 requires at least one iteration.',
      );
    }
  }

  /// Encodes as `pbkdf2-sha256$<iterations>$<salt>$<derived key>`, with salt
  /// and key base64-encoded. Self-describing, so the parameters used for an
  /// old hash travel with it.
  String hash(String password) {
    final salt = List<int>.generate(_saltBytes, (_) => _random.nextInt(256));
    final derived = _deriveKey(
      password: password,
      salt: salt,
      iterations: iterations,
      keyLength: _keyBytes,
    );
    return '$_algorithm\$$iterations\$${base64Encode(salt)}'
        '\$${base64Encode(derived)}';
  }

  /// True when [password] produced [encoded]. A malformed or unknown-algorithm
  /// hash returns false rather than throwing, so a corrupt record cannot be
  /// used to bypass a check.
  bool verify(String password, String encoded) {
    final parts = encoded.split(r'$');
    if (parts.length != 4 || parts[0] != _algorithm) return false;

    final storedIterations = int.tryParse(parts[1]);
    if (storedIterations == null || storedIterations < 1) return false;

    final List<int> salt;
    final List<int> expected;
    try {
      salt = base64Decode(parts[2]);
      expected = base64Decode(parts[3]);
    } on FormatException {
      return false;
    }
    if (salt.isEmpty || expected.isEmpty) return false;

    final derived = _deriveKey(
      password: password,
      salt: salt,
      iterations: storedIterations,
      keyLength: expected.length,
    );
    return _constantTimeEquals(derived, expected);
  }

  /// True when [encoded] was produced with weaker parameters than this hasher
  /// currently uses, so a provider can re-hash on the next successful sign-in.
  bool needsRehash(String encoded) {
    final parts = encoded.split(r'$');
    if (parts.length != 4 || parts[0] != _algorithm) return true;
    final storedIterations = int.tryParse(parts[1]);
    return storedIterations == null || storedIterations < iterations;
  }

  static List<int> _deriveKey({
    required String password,
    required List<int> salt,
    required int iterations,
    required int keyLength,
  }) {
    final hmac = Hmac(sha256, utf8.encode(password));
    final output = <int>[];

    for (var block = 1; output.length < keyLength; block++) {
      var previous = hmac.convert(<int>[
        ...salt,
        (block >> 24) & 0xff,
        (block >> 16) & 0xff,
        (block >> 8) & 0xff,
        block & 0xff,
      ]).bytes;
      final accumulated = List<int>.of(previous);

      for (var round = 1; round < iterations; round++) {
        previous = hmac.convert(previous).bytes;
        for (var i = 0; i < accumulated.length; i++) {
          accumulated[i] ^= previous[i];
        }
      }
      output.addAll(accumulated);
    }

    return output.sublist(0, keyLength);
  }

  static bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var i = 0; i < left.length; i++) {
      difference |= left[i] ^ right[i];
    }
    return difference == 0;
  }
}
