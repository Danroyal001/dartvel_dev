/// Hashing, comparing and minting bearer secrets: API keys, OAuth client
/// secrets, authorization codes and tokens.
///
/// SHA-256 rather than the password hasher, deliberately. A password is chosen
/// by a person and guessable from a dictionary, so it needs a slow hash. Every
/// secret minted here is 256 random bits from [Random.secure]; there is no
/// dictionary to walk, and a slow hash would only put a PBKDF2 run on every
/// API call. What matters is that the stored value is not the secret, which
/// SHA-256 gives, and that comparison leaks nothing through timing, which
/// [equals] gives.
library dartvel_core.auth.secret_hash;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;

abstract final class DVSecretHash {
  /// The stored form of [secret]: lowercase hex SHA-256, 64 characters.
  static String of(String secret) =>
      crypto.sha256.convert(utf8.encode(secret)).toString();

  /// Whether [presented] hashes to [expectedHash], compared in constant time.
  static bool matches(String expectedHash, String presented) =>
      equals(expectedHash, of(presented));

  /// How many characters the last [equals] examined.
  ///
  /// For tests that prove a comparison went through here and ran the whole
  /// length, rather than through `==`, which stops at the first difference.
  static int debugLastCompared = 0;

  /// Compares [expected] and [actual] over the whole of [expected], whatever
  /// differs and wherever, so the time taken says nothing about how much of a
  /// guess was right.
  static bool equals(String expected, String actual) {
    int difference = expected.length ^ actual.length;
    for (int i = 0; i < expected.length; i++) {
      final int other = i < actual.length ? actual.codeUnitAt(i) : 0;
      difference |= expected.codeUnitAt(i) ^ other;
    }
    debugLastCompared = expected.length;
    return difference == 0;
  }

  /// [bytes] random bytes as unpadded URL-safe base64.
  static String token(Random random, int bytes) => base64Url
      .encode(List<int>.generate(bytes, (_) => random.nextInt(256)))
      .replaceAll('=', '');

  /// [bytes] random bytes as lowercase hex.
  static String hex(Random random, int bytes) {
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < bytes; i++) {
      buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}
