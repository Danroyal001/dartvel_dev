/// Second factors: TOTP authenticator apps and recovery codes.
///
/// Part of the runtime the specification's `# Sessions and Account
/// Management` describes. The failures this exists to prevent are the silent
/// ones:
///
/// * a TOTP check without replay protection accepts the same six digits for
///   its whole window, so a code read over a shoulder is a second sign-in —
///   each account records the last step it accepted, and advancing it is a
///   compare-and-set in the store so two simultaneous requests cannot both
///   spend one code;
/// * a TOTP secret stored in the clear makes the second factor a copy of the
///   first — it is sealed with [DVFieldCipher] and opened only to check a code;
/// * recovery codes stored as themselves turn a database dump into account
///   takeover — each is kept only as a salted HMAC, shown once when generated,
///   and deleted when spent.
library dartvel_core.auth.second_factor;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import '../crypto/field_cipher.dart';
import '../database/adapter.dart';

/// The HMAC a TOTP code is derived with.
enum DVTotpAlgorithm { sha1, sha256, sha512 }

/// Time-based one-time passwords, RFC 6238 over HOTP (RFC 4226).
///
/// The defaults — SHA-1, six digits, thirty seconds — are what every
/// authenticator app implements; the others exist because the RFC defines
/// them, not because an app will agree to them.
class DVTotp {
  final int digits;
  final Duration period;
  final DVTotpAlgorithm algorithm;

  const DVTotp({
    this.digits = 6,
    this.period = const Duration(seconds: 30),
    this.algorithm = DVTotpAlgorithm.sha1,
  });

  /// The time step [at] falls in.
  int stepAt(DateTime at) =>
      at.millisecondsSinceEpoch ~/ 1000 ~/ period.inSeconds;

  /// The code for [secret] at [at].
  String generate(List<int> secret, {required DateTime at}) =>
      _code(secret, stepAt(at));

  /// The step [code] was generated for, or null when it matches none within
  /// [window] steps of [at] — or matches only steps at or before
  /// [lastUsedStep], which have already been spent.
  ///
  /// Every candidate is computed and compared in constant time before the
  /// answer is chosen, so how long a check takes does not say which step, or
  /// how much of a code, was right.
  int? verify(
    String code,
    List<int> secret, {
    required DateTime at,
    int window = 1,
    int? lastUsedStep,
  }) {
    final String given = code.replaceAll(RegExp(r'\s'), '');
    if (given.length != digits || !RegExp(r'^\d+$').hasMatch(given)) {
      return null;
    }
    final int current = stepAt(at);
    int? matched;
    for (int step = current - window; step <= current + window; step++) {
      final bool spent = lastUsedStep != null && step <= lastUsedStep;
      final bool equal = _constantTimeEquals(_code(secret, step), given);
      if (equal && !spent) matched ??= step;
    }
    return matched;
  }

  String _code(List<int> secret, int counter) {
    // Eight bytes big-endian, built by division rather than shifts: on the
    // web an integer shift truncates to 32 bits, which would corrupt every
    // counter past 2106.
    final Uint8List message = Uint8List(8);
    int value = counter;
    for (int i = 7; i >= 0; i--) {
      message[i] = value % 256;
      value = value ~/ 256;
    }
    final crypto.Hash hash = switch (algorithm) {
      DVTotpAlgorithm.sha1 => crypto.sha1,
      DVTotpAlgorithm.sha256 => crypto.sha256,
      DVTotpAlgorithm.sha512 => crypto.sha512,
    };
    final List<int> mac = crypto.Hmac(hash, secret).convert(message).bytes;
    final int offset = mac.last & 0x0f;
    final int binary = ((mac[offset] & 0x7f) * 0x1000000) +
        (mac[offset + 1] * 0x10000) +
        (mac[offset + 2] * 0x100) +
        mac[offset + 3];
    int modulus = 1;
    for (int i = 0; i < digits; i++) {
      modulus *= 10;
    }
    return (binary % modulus).toString().padLeft(digits, '0');
  }

  /// The `otpauth://` URI an authenticator app reads from a QR code.
  ///
  /// The label is `issuer:account`, percent-encoded as the key-uri format
  /// requires, with the issuer repeated as a parameter because some apps read
  /// one and some the other.
  Uri provisioningUri({
    required String secret,
    required String issuer,
    required String account,
  }) =>
      Uri(
        scheme: 'otpauth',
        host: 'totp',
        path: '/$issuer:$account',
        queryParameters: <String, String>{
          'secret': secret,
          'issuer': issuer,
          'algorithm': algorithm.name.toUpperCase(),
          'digits': '$digits',
          'period': '${period.inSeconds}',
        },
      );

  static const String _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  /// RFC 4648 base32 without padding: what authenticator apps are given.
  static String base32Encode(List<int> bytes) {
    final StringBuffer out = StringBuffer();
    int buffer = 0;
    int bits = 0;
    for (final int byte in bytes) {
      buffer = (buffer * 256 + byte) % 65536;
      bits += 8;
      while (bits >= 5) {
        out.write(_alphabet[(buffer >> (bits - 5)) & 31]);
        bits -= 5;
      }
    }
    if (bits > 0) out.write(_alphabet[(buffer << (5 - bits)) & 31]);
    return out.toString();
  }

  /// Decodes base32, forgiving the spaces, hyphens, lower case and padding
  /// people type when they enter a key by hand.
  static Uint8List base32Decode(String input) {
    final String clean =
        input.toUpperCase().replaceAll(RegExp(r'[\s\-=]'), '');
    final List<int> out = <int>[];
    int buffer = 0;
    int bits = 0;
    for (int i = 0; i < clean.length; i++) {
      final int value = _alphabet.indexOf(clean[i]);
      if (value < 0) {
        throw FormatException('Not base32', input, i);
      }
      buffer = (buffer * 32 + value) % 65536;
      bits += 5;
      if (bits >= 8) {
        out.add((buffer >> (bits - 8)) & 0xff);
        bits -= 8;
      }
    }
    return Uint8List.fromList(out);
  }
}

bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  int difference = 0;
  for (int i = 0; i < a.length; i++) {
    difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return difference == 0;
}

/// A TOTP enrollment as stored: the sealed secret, whether a code has proven
/// the authenticator app holds it, and the last step spent.
class DVTotpRecord {
  final String userId;

  /// The base32 secret, sealed with [DVFieldCipher]. Never the secret itself.
  final String sealedSecret;
  final bool confirmed;

  /// The last time step a code was accepted for, or -1 before any.
  final int lastUsedStep;

  const DVTotpRecord({
    required this.userId,
    required this.sealedSecret,
    required this.confirmed,
    this.lastUsedStep = -1,
  });

  @override
  String toString() => 'DVTotpRecord($userId, confirmed: $confirmed)';
}

/// One unspent recovery code, as stored: a salt and an HMAC of the code.
class DVRecoveryCodeRecord {
  final String userId;
  final String salt;
  final String hash;

  const DVRecoveryCodeRecord({
    required this.userId,
    required this.salt,
    required this.hash,
  });
}

/// Where second factors live.
abstract class DVSecondFactorStore {
  Future<DVTotpRecord?> totp(String userId);

  /// Stores a pending enrollment, replacing any pending one for the user.
  Future<void> putPendingTotp(DVTotpRecord record);

  /// Marks the pending enrollment confirmed and spends [step], if it is
  /// still pending. Returns whether it was.
  Future<bool> confirmTotp(String userId, int step);

  /// Spends [step] if it is later than the last one spent. Returns whether it
  /// was — false is a replay, or a concurrent request that spent it first.
  Future<bool> advanceTotpStep(String userId, int step);

  Future<void> removeTotp(String userId);

  Future<List<DVRecoveryCodeRecord>> recoveryCodes(String userId);

  /// Replaces every recovery code the user has.
  Future<void> replaceRecoveryCodes(
      String userId, List<DVRecoveryCodeRecord> records);

  /// Deletes the code with [hash]. Returns whether it existed, so a code can
  /// be spent once even by two requests racing for it.
  Future<bool> consumeRecoveryCode(String userId, String hash);

  /// Stored rows as held, for tests proving what is written down.
  Future<List<Map<String, Object?>>> debugRows();
}

/// Second factors in process memory.
class DVMemorySecondFactorStore implements DVSecondFactorStore {
  final Map<String, DVTotpRecord> _totp = <String, DVTotpRecord>{};
  final Map<String, List<DVRecoveryCodeRecord>> _codes =
      <String, List<DVRecoveryCodeRecord>>{};

  @override
  Future<DVTotpRecord?> totp(String userId) async => _totp[userId];

  @override
  Future<void> putPendingTotp(DVTotpRecord record) async {
    _totp[record.userId] = record;
  }

  @override
  Future<bool> confirmTotp(String userId, int step) async {
    final DVTotpRecord? record = _totp[userId];
    if (record == null || record.confirmed) return false;
    _totp[userId] = DVTotpRecord(
      userId: userId,
      sealedSecret: record.sealedSecret,
      confirmed: true,
      lastUsedStep: step,
    );
    return true;
  }

  @override
  Future<bool> advanceTotpStep(String userId, int step) async {
    final DVTotpRecord? record = _totp[userId];
    if (record == null || !record.confirmed || step <= record.lastUsedStep) {
      return false;
    }
    _totp[userId] = DVTotpRecord(
      userId: userId,
      sealedSecret: record.sealedSecret,
      confirmed: true,
      lastUsedStep: step,
    );
    return true;
  }

  @override
  Future<void> removeTotp(String userId) async => _totp.remove(userId);

  @override
  Future<List<DVRecoveryCodeRecord>> recoveryCodes(String userId) async =>
      List<DVRecoveryCodeRecord>.of(
          _codes[userId] ?? const <DVRecoveryCodeRecord>[]);

  @override
  Future<void> replaceRecoveryCodes(
      String userId, List<DVRecoveryCodeRecord> records) async {
    _codes[userId] = List<DVRecoveryCodeRecord>.of(records);
  }

  @override
  Future<bool> consumeRecoveryCode(String userId, String hash) async {
    final List<DVRecoveryCodeRecord>? codes = _codes[userId];
    if (codes == null) return false;
    final int before = codes.length;
    codes.removeWhere((DVRecoveryCodeRecord r) => r.hash == hash);
    return codes.length < before;
  }

  @override
  Future<List<Map<String, Object?>>> debugRows() async => <Map<String, Object?>>[
        for (final DVTotpRecord r in _totp.values)
          <String, Object?>{
            'user_id': r.userId,
            'secret': r.sealedSecret,
            'confirmed': r.confirmed,
            'last_step': r.lastUsedStep,
          },
        for (final List<DVRecoveryCodeRecord> list in _codes.values)
          for (final DVRecoveryCodeRecord r in list)
            <String, Object?>{
              'user_id': r.userId,
              'salt': r.salt,
              'hash': r.hash,
            },
      ];
}

/// Second factors in database tables, through [DVDatabaseAdapter].
///
/// Issues only the SQL subset the in-memory adapter runs. The compare-and-set
/// steps are conditional updates whose affected-row count is the answer, so
/// they hold across processes sharing the database.
class DVDatabaseSecondFactorStore implements DVSecondFactorStore {
  final DVDatabaseAdapter adapter;

  DVDatabaseSecondFactorStore(this.adapter);

  static const String _totpTable = 'dv_totp';
  static const String _codesTable = 'dv_recovery_codes';

  Future<void>? _ready;

  Future<void> _ensure() => _ready ??= () async {
        await adapter.execute(
          'CREATE TABLE IF NOT EXISTS $_totpTable ('
          'user_id TEXT, secret TEXT, confirmed INTEGER, last_step INTEGER)',
        );
        await adapter.execute(
          'CREATE TABLE IF NOT EXISTS $_codesTable ('
          'user_id TEXT, salt TEXT, hash TEXT)',
        );
      }();

  @override
  Future<DVTotpRecord?> totp(String userId) async {
    await _ensure();
    final List<Map<String, Object?>> rows = await adapter.query(
      'SELECT user_id, secret, confirmed, last_step FROM $_totpTable '
      'WHERE user_id = ?',
      <Object?>[userId],
    );
    if (rows.isEmpty) return null;
    final Map<String, Object?> row = rows.first;
    return DVTotpRecord(
      userId: row['user_id']! as String,
      sealedSecret: row['secret']! as String,
      confirmed: (row['confirmed']! as num).toInt() == 1,
      lastUsedStep: (row['last_step']! as num).toInt(),
    );
  }

  @override
  Future<void> putPendingTotp(DVTotpRecord record) async {
    await _ensure();
    await adapter.execute(
      'DELETE FROM $_totpTable WHERE user_id = ? AND confirmed = ?',
      <Object?>[record.userId, 0],
    );
    await adapter.execute(
      'INSERT INTO $_totpTable (user_id, secret, confirmed, last_step) '
      'VALUES (?, ?, ?, ?)',
      <Object?>[record.userId, record.sealedSecret, 0, -1],
    );
  }

  @override
  Future<bool> confirmTotp(String userId, int step) async {
    await _ensure();
    final int changed = await adapter.execute(
      'UPDATE $_totpTable SET confirmed = ?, last_step = ? '
      'WHERE user_id = ? AND confirmed = ?',
      <Object?>[1, step, userId, 0],
    );
    return changed > 0;
  }

  @override
  Future<bool> advanceTotpStep(String userId, int step) async {
    await _ensure();
    final int changed = await adapter.execute(
      'UPDATE $_totpTable SET last_step = ? '
      'WHERE user_id = ? AND confirmed = ? AND last_step < ?',
      <Object?>[step, userId, 1, step],
    );
    return changed > 0;
  }

  @override
  Future<void> removeTotp(String userId) async {
    await _ensure();
    await adapter.execute(
        'DELETE FROM $_totpTable WHERE user_id = ?', <Object?>[userId]);
  }

  @override
  Future<List<DVRecoveryCodeRecord>> recoveryCodes(String userId) async {
    await _ensure();
    final List<Map<String, Object?>> rows = await adapter.query(
      'SELECT user_id, salt, hash FROM $_codesTable WHERE user_id = ?',
      <Object?>[userId],
    );
    return <DVRecoveryCodeRecord>[
      for (final Map<String, Object?> row in rows)
        DVRecoveryCodeRecord(
          userId: row['user_id']! as String,
          salt: row['salt']! as String,
          hash: row['hash']! as String,
        ),
    ];
  }

  @override
  Future<void> replaceRecoveryCodes(
      String userId, List<DVRecoveryCodeRecord> records) async {
    await _ensure();
    await adapter.execute(
        'DELETE FROM $_codesTable WHERE user_id = ?', <Object?>[userId]);
    for (final DVRecoveryCodeRecord record in records) {
      await adapter.execute(
        'INSERT INTO $_codesTable (user_id, salt, hash) VALUES (?, ?, ?)',
        <Object?>[record.userId, record.salt, record.hash],
      );
    }
  }

  @override
  Future<bool> consumeRecoveryCode(String userId, String hash) async {
    await _ensure();
    final int changed = await adapter.execute(
      'DELETE FROM $_codesTable WHERE user_id = ? AND hash = ?',
      <Object?>[userId, hash],
    );
    return changed > 0;
  }

  @override
  Future<List<Map<String, Object?>>> debugRows() async {
    await _ensure();
    return <Map<String, Object?>>[
      ...await adapter.query('SELECT * FROM $_totpTable'),
      ...await adapter.query('SELECT * FROM $_codesTable'),
    ];
  }
}

/// A TOTP enrollment in progress: the secret to show once, as text and as
/// the URI a QR code encodes.
class DVTotpEnrollment {
  /// Base32, for typing into an authenticator app by hand.
  final String secret;

  /// `otpauth://` — what the QR code encodes.
  final Uri uri;

  const DVTotpEnrollment({required this.secret, required this.uri});

  @override
  String toString() => 'DVTotpEnrollment(pending)';
}

/// Newly generated recovery codes. The only time they exist in readable form.
class DVRecoveryCodes {
  final List<String> codes;
  final DateTime generatedAt;

  const DVRecoveryCodes({required this.codes, required this.generatedAt});

  /// Never prints the codes, so an object dropped into a log does not carry
  /// them there.
  @override
  String toString() => 'DVRecoveryCodes(${codes.length} codes)';
}

/// Enrolls and checks second factors for accounts.
///
/// Presenting a factor proves who is present; it does not by itself change a
/// session. After a code verifies, the caller completes the session's second
/// factor with `DVSessions.completeMfa`, which rotates its token.
class DVSecondFactors {
  final DVSecondFactorStore store;
  final DVFieldCipher cipher;

  /// The name an authenticator app lists the account under.
  final String issuer;
  final DVTotp totp;

  /// How many recovery codes a set holds.
  final int recoveryCodeCount;

  final DateTime Function() _clock;
  final Random _random = Random.secure();

  DVSecondFactors({
    DVSecondFactorStore? store,
    required this.cipher,
    required this.issuer,
    this.totp = const DVTotp(),
    this.recoveryCodeCount = 10,
    DateTime Function()? clock,
  })  : store = store ?? DVMemorySecondFactorStore(),
        _clock = clock ?? DateTime.now;

  static const String _model = 'DVSecondFactor';
  static const String _field = 'totpSecret';

  /// Starts TOTP enrollment for [userId]. Nothing is required of later
  /// sign-ins until [confirmTotp] proves the app holds the secret.
  ///
  /// Refused while a confirmed authenticator exists: swapping it for a new one
  /// is removing a second factor, which is a decision to make after one is
  /// presented, not something a session can do on its own.
  Future<DVTotpEnrollment> beginTotp(String userId,
      {required String account}) async {
    final DVTotpRecord? existing = await store.totp(userId);
    if (existing != null && existing.confirmed) {
      throw StateError(
          'This account already has an authenticator. Remove it first.');
    }
    final String secret = DVTotp.base32Encode(
        List<int>.generate(20, (_) => _random.nextInt(256)));
    await store.putPendingTotp(DVTotpRecord(
      userId: userId,
      sealedSecret:
          cipher.encrypt(model: _model, field: _field, plaintext: secret),
      confirmed: false,
    ));
    return DVTotpEnrollment(
      secret: secret,
      uri: totp.provisioningUri(
          secret: secret, issuer: issuer, account: account),
    );
  }

  /// Confirms a pending enrollment with a code from the app. The code's step
  /// is spent, so it cannot then sign in.
  Future<bool> confirmTotp(String userId, String code) async {
    final DVTotpRecord? record = await store.totp(userId);
    if (record == null || record.confirmed) return false;
    final int? step = totp.verify(code, _secretOf(record), at: _clock());
    if (step == null) return false;
    return store.confirmTotp(userId, step);
  }

  /// Whether [userId] has a confirmed authenticator.
  Future<bool> hasTotp(String userId) async =>
      (await store.totp(userId))?.confirmed ?? false;

  /// Checks a code from [userId]'s authenticator. A code verifies once.
  Future<bool> verifyTotp(String userId, String code) async {
    final DVTotpRecord? record = await store.totp(userId);
    if (record == null || !record.confirmed) return false;
    final int? step = totp.verify(
      code,
      _secretOf(record),
      at: _clock(),
      lastUsedStep: record.lastUsedStep,
    );
    if (step == null) return false;
    return store.advanceTotpStep(userId, step);
  }

  /// Removes [userId]'s authenticator.
  Future<void> removeTotp(String userId) => store.removeTotp(userId);

  /// Generates a fresh set of recovery codes, invalidating every earlier one.
  /// The returned codes are the only readable copy.
  Future<DVRecoveryCodes> regenerateRecoveryCodes(String userId) async {
    final List<String> codes = <String>[];
    final List<DVRecoveryCodeRecord> records = <DVRecoveryCodeRecord>[];
    final Set<String> seen = <String>{};
    while (codes.length < recoveryCodeCount) {
      final String code = _recoveryCode();
      if (!seen.add(code)) continue;
      final String salt = base64Url
          .encode(List<int>.generate(16, (_) => _random.nextInt(256)));
      codes.add(code);
      records.add(DVRecoveryCodeRecord(
        userId: userId,
        salt: salt,
        hash: _hashCode(salt, code),
      ));
    }
    await store.replaceRecoveryCodes(userId, records);
    return DVRecoveryCodes(codes: List<String>.unmodifiable(codes),
        generatedAt: _clock());
  }

  /// Spends one of [userId]'s recovery codes. Each works once.
  Future<bool> redeemRecoveryCode(String userId, String code) async {
    final List<DVRecoveryCodeRecord> records =
        await store.recoveryCodes(userId);
    DVRecoveryCodeRecord? matched;
    // Every stored code is compared, so the time a guess takes does not say
    // how far down the list it got.
    for (final DVRecoveryCodeRecord record in records) {
      if (_constantTimeEquals(_hashCode(record.salt, code), record.hash)) {
        matched ??= record;
      }
    }
    if (matched == null) return false;
    return store.consumeRecoveryCode(userId, matched.hash);
  }

  /// How many unspent recovery codes [userId] has.
  Future<int> remainingRecoveryCodes(String userId) async =>
      (await store.recoveryCodes(userId)).length;

  List<int> _secretOf(DVTotpRecord record) => DVTotp.base32Decode(
      cipher.decrypt(
          model: _model, field: _field, ciphertext: record.sealedSecret));

  /// Ten base32 characters in two groups: fifty bits, which is far more than
  /// a throttled endpoint lets anybody guess.
  String _recoveryCode() {
    const String alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final StringBuffer out = StringBuffer();
    for (int i = 0; i < 10; i++) {
      if (i == 5) out.write('-');
      out.write(alphabet[_random.nextInt(alphabet.length)]);
    }
    return out.toString();
  }

  static String _normalize(String code) =>
      code.toUpperCase().replaceAll(RegExp(r'[\s\-]'), '');

  static String _hashCode(String salt, String code) => crypto.Hmac(
          crypto.sha256, utf8.encode(salt))
      .convert(utf8.encode(_normalize(code)))
      .toString();
}
