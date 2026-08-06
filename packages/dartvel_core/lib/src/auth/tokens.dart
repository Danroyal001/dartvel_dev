/// Single-use authentication tokens: magic links and one-time passcodes.
///
/// Both are the same primitive with different ergonomics — a secret issued to
/// a channel the user controls, redeemable once, within a window.
library dartvel_core.auth.tokens;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;

/// Why a redemption failed.
///
/// Deliberately coarse at the boundary: see [DVAuthTokenResult.reveal].
enum DVAuthTokenFailure {
  /// No such token, or it was already used, or it expired.
  invalid,

  /// Too many wrong attempts against this identifier.
  throttled,
}

/// The outcome of a redemption.
class DVAuthTokenResult {
  /// The identifier the token was issued for, when redemption succeeded.
  final String? identifier;

  final DVAuthTokenFailure? failure;

  const DVAuthTokenResult.success(String this.identifier) : failure = null;

  const DVAuthTokenResult.failed(DVAuthTokenFailure this.failure)
      : identifier = null;

  bool get isSuccess => identifier != null;

  /// A message safe to show a user.
  ///
  /// Never distinguishes "no such token" from "expired" from "already used":
  /// telling them apart lets an attacker enumerate which codes existed.
  String get reveal => switch (failure) {
        DVAuthTokenFailure.throttled =>
          'Too many attempts. Request a new code.',
        _ => 'That code is invalid or has expired.',
      };
}

/// One issued token, as stored.
class DVAuthTokenRecord {
  /// Who the token is for — an e-mail, a phone number, a user id.
  final String identifier;

  /// The hash of the secret. The secret itself is never stored, so a dump of
  /// this table does not let anyone sign in.
  final String hash;

  final DateTime expiresAt;

  /// Wrong attempts so far, which is what throttling counts.
  final int attempts;

  const DVAuthTokenRecord({
    required this.identifier,
    required this.hash,
    required this.expiresAt,
    this.attempts = 0,
  });

  DVAuthTokenRecord withAttempt() => DVAuthTokenRecord(
        identifier: identifier,
        hash: hash,
        expiresAt: expiresAt,
        attempts: attempts + 1,
      );
}

/// Where issued tokens live between request and redemption.
abstract class DVAuthTokenStore {
  Future<void> put(String lookup, DVAuthTokenRecord record);

  Future<DVAuthTokenRecord?> get(String lookup);

  Future<void> delete(String lookup);

  /// Replaces a record, for attempt counting.
  Future<void> update(String lookup, DVAuthTokenRecord record);
}

/// In-memory store. Fine for one process; use a database- or cache-backed
/// store when more than one serves the same users.
class DVMemoryAuthTokenStore implements DVAuthTokenStore {
  final Map<String, DVAuthTokenRecord> _records = {};

  @override
  Future<void> put(String lookup, DVAuthTokenRecord record) async {
    _records[lookup] = record;
  }

  @override
  Future<DVAuthTokenRecord?> get(String lookup) async => _records[lookup];

  @override
  Future<void> delete(String lookup) async => _records.remove(lookup);

  @override
  Future<void> update(String lookup, DVAuthTokenRecord record) async {
    _records[lookup] = record;
  }
}

/// An issued magic link.
class DVMagicLink {
  /// The URL to send. It carries the only copy of the secret.
  final Uri url;

  /// The raw token, if the caller wants to compose its own message.
  final String token;

  final DateTime expiresAt;

  const DVMagicLink({
    required this.url,
    required this.token,
    required this.expiresAt,
  });
}

/// Issues and redeems magic links and one-time passcodes.
class DVAuthTokens {
  final DVAuthTokenStore store;

  /// How long an issued secret stays redeemable.
  final Duration lifetime;

  /// Wrong attempts allowed before an identifier is throttled.
  ///
  /// A six-digit code is only a million possibilities; without a cap it is
  /// guessable in minutes.
  final int maxAttempts;

  final Random _random;

  DVAuthTokens({
    DVAuthTokenStore? store,
    this.lifetime = const Duration(minutes: 15),
    this.maxAttempts = 5,
    Random? random,
  })  : store = store ?? DVMemoryAuthTokenStore(),
        // Random.secure by default: a predictable code is no protection at
        // all. An injected Random is for tests only.
        _random = random ?? Random.secure();

  /// Issues a magic link for [identifier].
  ///
  /// [baseUrl] receives the token as a query parameter, so the link is
  /// whatever route the application already serves.
  Future<DVMagicLink> issueMagicLink(
    String identifier, {
    required Uri baseUrl,
    String parameter = 'token',
  }) async {
    final token = _secret(32);
    final expiresAt = DateTime.now().add(lifetime);
    await store.put(
      _lookupForLink(token),
      DVAuthTokenRecord(
        identifier: identifier,
        hash: _hash(token),
        expiresAt: expiresAt,
      ),
    );
    return DVMagicLink(
      url: baseUrl.replace(
        queryParameters: <String, String>{
          ...baseUrl.queryParameters,
          parameter: token,
        },
      ),
      token: token,
      expiresAt: expiresAt,
    );
  }

  /// Redeems a magic-link token. Single use: a redeemed link cannot be
  /// replayed, which matters because links sit in mailboxes indefinitely.
  Future<DVAuthTokenResult> redeemMagicLink(String token) async {
    final lookup = _lookupForLink(token);
    final record = await store.get(lookup);
    if (record == null) {
      return const DVAuthTokenResult.failed(DVAuthTokenFailure.invalid);
    }
    await store.delete(lookup);
    if (DateTime.now().isAfter(record.expiresAt)) {
      return const DVAuthTokenResult.failed(DVAuthTokenFailure.invalid);
    }
    if (!_matches(record.hash, token)) {
      return const DVAuthTokenResult.failed(DVAuthTokenFailure.invalid);
    }
    return DVAuthTokenResult.success(record.identifier);
  }

  /// Issues a numeric passcode for [identifier], returning the code to send.
  ///
  /// Issuing again replaces any outstanding code, so a user who requests a
  /// second one is not left guessing which arrived first.
  Future<String> issueOtp(String identifier, {int digits = 6}) async {
    final code = _digits(digits);
    await store.put(
      _lookupForOtp(identifier),
      DVAuthTokenRecord(
        identifier: identifier,
        hash: _hash(code),
        expiresAt: DateTime.now().add(lifetime),
      ),
    );
    return code;
  }

  /// Redeems a passcode for [identifier].
  Future<DVAuthTokenResult> redeemOtp(String identifier, String code) async {
    final lookup = _lookupForOtp(identifier);
    final record = await store.get(lookup);
    if (record == null) {
      return const DVAuthTokenResult.failed(DVAuthTokenFailure.invalid);
    }
    if (record.attempts >= maxAttempts) {
      return const DVAuthTokenResult.failed(DVAuthTokenFailure.throttled);
    }
    if (DateTime.now().isAfter(record.expiresAt)) {
      await store.delete(lookup);
      return const DVAuthTokenResult.failed(DVAuthTokenFailure.invalid);
    }
    if (!_matches(record.hash, code)) {
      // Count the attempt rather than deleting: deleting on the first wrong
      // digit would let anyone cancel someone else's sign-in.
      await store.update(lookup, record.withAttempt());
      return const DVAuthTokenResult.failed(DVAuthTokenFailure.invalid);
    }
    await store.delete(lookup);
    return DVAuthTokenResult.success(record.identifier);
  }

  /// A magic link is looked up by its own token, so nothing about the
  /// recipient is derivable from the URL.
  String _lookupForLink(String token) => 'magic:${_hash(token)}';

  /// A passcode is looked up by identifier, because the user types the code
  /// and the server must find the pending record for them.
  String _lookupForOtp(String identifier) => 'otp:$identifier';

  String _secret(int bytes) {
    final values = List<int>.generate(bytes, (_) => _random.nextInt(256));
    return base64Url.encode(values).replaceAll('=', '');
  }

  String _digits(int count) {
    final buffer = StringBuffer();
    for (var i = 0; i < count; i++) {
      buffer.write(_random.nextInt(10));
    }
    return buffer.toString();
  }

  static String _hash(String secret) =>
      crypto.sha256.convert(utf8.encode(secret)).toString();

  /// Constant-time compare, so a timing difference cannot reveal how much of
  /// a code was right.
  static bool _matches(String expectedHash, String secret) {
    final actual = _hash(secret);
    if (actual.length != expectedHash.length) return false;
    var difference = 0;
    for (var i = 0; i < actual.length; i++) {
      difference |= actual.codeUnitAt(i) ^ expectedHash.codeUnitAt(i);
    }
    return difference == 0;
  }
}
