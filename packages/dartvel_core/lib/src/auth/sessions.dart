/// Sessions: the record of a signed-in device that carries every authenticated
/// request, and the policy that says when a second factor is needed.
///
/// The runtime the specification's `# Sessions and Account Management`
/// describes. Authentication says how somebody gets in; this is what exists
/// afterwards, and its behaviour is the part that goes wrong silently:
///
/// * a session token is a bearer credential, so the store holds only its
///   hash — a dump of the table is not a list of working sessions;
/// * the token is reissued on every privilege boundary ([DVSessions.rotate],
///   [DVSessions.elevate], [DVSessions.completeMfa]), because a stable
///   identifier across one is session fixation;
/// * revocation is checked on the next request rather than at expiry, so a
///   sign-out elsewhere signs this device out;
/// * rotation keeps the original sign-in time, so a session kept alive by
///   rotating still ends at its absolute lifetime.
library dartvel_core.auth.sessions;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;

import '../database/adapter.dart';
import '../database/framework_tables.dart';
import '../tenancy/tenants.dart';

/// A signed-in device.
///
/// A record of a device rather than a cookie with a friendly name. Nothing on
/// it is the bearer token: [id] is a separate handle, safe to list and to pass
/// to [DVSessions.revoke], so showing a person their devices never hands out
/// their other sessions.
class DVSession {
  /// Opaque handle for this session. Reissued with the token on rotation, and
  /// never a user identifier.
  final String id;

  final String userId;

  /// The tenant the session was issued on. It authenticates requests on this
  /// tenant only, and rotation does not change it: moving to another tenant
  /// is a new sign-in.
  final String tenant;

  /// When the person signed in. Rotation does not change it.
  final DateTime createdAt;

  /// When this session last authenticated a request.
  final DateTime lastSeenAt;

  /// What the platform reported the device as. Never a derived fingerprint.
  final String? device;

  /// Coarse location from the request, when the application configured one.
  final String? location;

  /// Server-issued claims. There is no way for a client to write one.
  final Map<String, Object?> claims;

  /// When a second factor was last presented in this session, or null.
  final DateTime? mfaSatisfiedAt;

  /// When the session was revoked, or null while it is live.
  final DateTime? revokedAt;

  /// Whether this is the session the listing was asked from.
  final bool isCurrent;

  const DVSession({
    required this.id,
    required this.userId,
    this.tenant = DVTenants.defaultTenant,
    required this.createdAt,
    required this.lastSeenAt,
    this.device,
    this.location,
    this.claims = const <String, Object?>{},
    this.mfaSatisfiedAt,
    this.revokedAt,
    this.isCurrent = false,
  });

  /// The claim a session issued at sign-in carries while the account's second
  /// factor has not been presented. Server-issued, like every claim.
  static const String mfaPendingClaim = 'dv.mfaPending';

  /// Whether this session was issued by a password alone for an account that
  /// has a second factor, which has not been presented yet. Such a session
  /// authenticates nothing but the second factor and sign-out:
  /// [DVSessions.completeMfa] records the factor, and the token it rotates to
  /// is the first that carries the person's privilege.
  bool get mfaPending => claims[mfaPendingClaim] == true && mfaSatisfiedAt == null;

  /// The session as a client may see it: never the token, which is not on a
  /// [DVSession] at all.
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'userId': userId,
        'tenant': tenant,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'lastSeenAt': lastSeenAt.toUtc().toIso8601String(),
        if (device != null) 'device': device,
        if (location != null) 'location': location,
        'claims': claims,
        'mfaSatisfiedAt': mfaSatisfiedAt?.toUtc().toIso8601String(),
        'isCurrent': isCurrent,
      };

  /// A session a server described with [toJson].
  factory DVSession.fromJson(Map<String, Object?> json) {
    DateTime? time(Object? value) =>
        value is String ? DateTime.tryParse(value)?.toUtc() : null;
    final Object? claims = json['claims'];
    return DVSession(
      id: json['id']! as String,
      userId: json['userId']! as String,
      tenant: json['tenant'] as String? ?? DVTenants.defaultTenant,
      createdAt: time(json['createdAt'])!,
      lastSeenAt: time(json['lastSeenAt'])!,
      device: json['device'] as String?,
      location: json['location'] as String?,
      claims: claims is Map
          ? Map<String, Object?>.unmodifiable(Map<String, Object?>.from(claims))
          : const <String, Object?>{},
      mfaSatisfiedAt: time(json['mfaSatisfiedAt']),
      isCurrent: json['isCurrent'] == true,
    );
  }

  DVSession _copy({
    String? id,
    DateTime? lastSeenAt,
    Map<String, Object?>? claims,
    DateTime? mfaSatisfiedAt,
    DateTime? revokedAt,
    bool? isCurrent,
  }) =>
      DVSession(
        id: id ?? this.id,
        userId: userId,
        tenant: tenant,
        createdAt: createdAt,
        lastSeenAt: lastSeenAt ?? this.lastSeenAt,
        device: device,
        location: location,
        claims: claims ?? this.claims,
        mfaSatisfiedAt: mfaSatisfiedAt ?? this.mfaSatisfiedAt,
        revokedAt: revokedAt ?? this.revokedAt,
        isCurrent: isCurrent ?? this.isCurrent,
      );

  @override
  String toString() => 'DVSession($id, user: $userId)';
}

/// A session and the token that authenticates it.
///
/// The only place the token exists outside the client that holds it: the
/// store has its hash, and nothing here logs it.
class DVIssuedSession {
  final DVSession session;
  final String token;

  const DVIssuedSession(this.session, this.token);

  @override
  String toString() => 'DVIssuedSession(${session.id})';
}

/// Why a token did not authenticate.
enum DVSessionFailure {
  /// No session has this token — never issued, or rotated away.
  unknown,

  /// The session was revoked, here or on another device.
  revoked,

  /// Idle for longer than the idle timeout, or older than the absolute one.
  expired,
}

/// The outcome of checking a token.
class DVSessionCheck {
  final DVSession? session;
  final DVSessionFailure? failure;

  const DVSessionCheck.valid(DVSession this.session) : failure = null;

  const DVSessionCheck.failed(DVSessionFailure this.failure) : session = null;

  /// The diagnostic a revoked session reports (`DV-SESSION-002`), or null.
  String? get code =>
      failure == DVSessionFailure.revoked ? 'DV-SESSION-002' : null;
}

/// A token that does not name a live session, where one was required.
class DVSessionInvalid implements Exception {
  final DVSessionFailure failure;

  const DVSessionInvalid(this.failure);

  @override
  String toString() => 'DVSessionInvalid(${failure.name})';
}

/// When a route or a backend function needs a second factor.
///
/// Declared where the risk is rather than at sign-in: a payout wants a recent
/// second factor, a settings page wants one at some point, most pages want
/// none.
final class DVMfa {
  const DVMfa._(this._needed, this.within);

  /// Step-up: a second factor within [window] of now.
  const DVMfa.recent(Duration window)
      : _needed = true,
        within = window;

  final bool _needed;

  /// How recent the second factor must be, or null for "at some point in
  /// this session".
  final Duration? within;

  /// No second factor needed.
  static const DVMfa none = DVMfa._(false, null);

  /// A second factor at some point in this session.
  static const DVMfa required = DVMfa._(true, null);

  /// Whether [session] meets this requirement at [now].
  bool isSatisfiedBy(DVSession session, DateTime now) {
    if (!_needed) return true;
    final DateTime? at = session.mfaSatisfiedAt;
    if (at == null) return false;
    final Duration? window = within;
    if (window == null) return true;
    return now.difference(at) <= window;
  }

  @override
  String toString() => !_needed
      ? 'DVMfa.none'
      : within == null
          ? 'DVMfa.required'
          : 'DVMfa.recent($within)';
}

/// A call that needs a second factor this session has not presented
/// (`DV-SESSION-001`).
///
/// Informational rather than a failure: the caller presents the challenge and
/// retries, the way a page redirect is followed.
class DVMfaRequired implements Exception {
  final DVMfa policy;
  final String sessionId;

  const DVMfaRequired(this.policy, this.sessionId);

  String get code => 'DV-SESSION-001';

  @override
  String toString() => 'DVMfaRequired($code: $policy for session $sessionId)';
}

/// One stored session: the public record plus the hash of its token.
class DVSessionRecord {
  final String tokenHash;
  final DVSession session;

  const DVSessionRecord(this.tokenHash, this.session);
}

/// Where sessions live.
///
/// Memory for one process and tests; [DVDatabaseSessionStore] over any
/// [DVDatabaseAdapter] — SQLite by default — when a session has to survive a
/// restart or be seen by more than one backend process.
abstract class DVSessionStore {
  Future<void> insert(DVSessionRecord record);

  Future<DVSessionRecord?> byTokenHash(String tokenHash);

  Future<DVSessionRecord?> byId(String id);

  /// Moves the session stored under [oldTokenHash] to [record], in one step,
  /// so there is no moment where both tokens authenticate.
  Future<void> replace(String oldTokenHash, DVSessionRecord record);

  Future<void> touch(String tokenHash, DateTime lastSeenAt);

  Future<void> revoke(String id, DateTime at);

  /// Every session of [userId], revoked or not.
  Future<List<DVSessionRecord>> forUser(String userId);

  /// The stored rows as they are held, for tests that prove what is and is
  /// not written down.
  Future<List<Map<String, Object?>>> debugRows();
}

/// Sessions in process memory.
class DVMemorySessionStore implements DVSessionStore {
  final Map<String, DVSessionRecord> _byHash = <String, DVSessionRecord>{};

  @override
  Future<void> insert(DVSessionRecord record) async {
    _byHash[record.tokenHash] = record;
  }

  @override
  Future<DVSessionRecord?> byTokenHash(String tokenHash) async =>
      _byHash[tokenHash];

  @override
  Future<DVSessionRecord?> byId(String id) async {
    for (final DVSessionRecord record in _byHash.values) {
      if (record.session.id == id) return record;
    }
    return null;
  }

  @override
  Future<void> replace(String oldTokenHash, DVSessionRecord record) async {
    _byHash.remove(oldTokenHash);
    _byHash[record.tokenHash] = record;
  }

  @override
  Future<void> touch(String tokenHash, DateTime lastSeenAt) async {
    final DVSessionRecord? record = _byHash[tokenHash];
    if (record == null) return;
    _byHash[tokenHash] =
        DVSessionRecord(tokenHash, record.session._copy(lastSeenAt: lastSeenAt));
  }

  @override
  Future<void> revoke(String id, DateTime at) async {
    for (final MapEntry<String, DVSessionRecord> entry in _byHash.entries) {
      if (entry.value.session.id == id) {
        _byHash[entry.key] =
            DVSessionRecord(entry.key, entry.value.session._copy(revokedAt: at));
        return;
      }
    }
  }

  @override
  Future<List<DVSessionRecord>> forUser(String userId) async => <DVSessionRecord>[
        for (final DVSessionRecord record in _byHash.values)
          if (record.session.userId == userId) record,
      ];

  @override
  Future<List<Map<String, Object?>>> debugRows() async => <Map<String, Object?>>[
        for (final DVSessionRecord record in _byHash.values)
          _DVSessionRows.toRow(record),
      ];
}

/// Sessions in a database table, through [DVDatabaseAdapter].
///
/// Issues only the SQL subset the in-memory adapter runs, so the same store
/// works with no database configured, on SQLite, and on the server adapters.
class DVDatabaseSessionStore implements DVSessionStore {
  final DVDatabaseAdapter adapter;
  final String table;

  DVDatabaseSessionStore(this.adapter, {this.table = 'dv_sessions'});

  Future<void>? _ready;

  Future<void> _ensure() => _ready ??= dvEnsureFrameworkTable(
        adapter,
        'CREATE TABLE IF NOT EXISTS $table ('
        'token_hash TEXT, id TEXT, user_id TEXT, tenant TEXT, '
        'created_at BIGINT, last_seen_at BIGINT, mfa_at BIGINT, '
        'revoked_at BIGINT, device TEXT, location TEXT, claims TEXT)',
      );

  static const String _columns =
      'token_hash, id, user_id, tenant, created_at, last_seen_at, mfa_at, '
      'revoked_at, device, location, claims';

  @override
  Future<void> insert(DVSessionRecord record) async {
    await _ensure();
    final Map<String, Object?> row = _DVSessionRows.toRow(record);
    await adapter.execute(
      'INSERT INTO $table ($_columns) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      <Object?>[
        row['token_hash'],
        row['id'],
        row['user_id'],
        row['tenant'],
        row['created_at'],
        row['last_seen_at'],
        row['mfa_at'],
        row['revoked_at'],
        row['device'],
        row['location'],
        row['claims'],
      ],
    );
  }

  @override
  Future<DVSessionRecord?> byTokenHash(String tokenHash) async {
    await _ensure();
    final List<Map<String, Object?>> rows = await adapter.query(
      'SELECT $_columns FROM $table WHERE token_hash = ?',
      <Object?>[tokenHash],
    );
    return rows.isEmpty ? null : _DVSessionRows.fromRow(rows.first);
  }

  @override
  Future<DVSessionRecord?> byId(String id) async {
    await _ensure();
    final List<Map<String, Object?>> rows = await adapter.query(
      'SELECT $_columns FROM $table WHERE id = ?',
      <Object?>[id],
    );
    return rows.isEmpty ? null : _DVSessionRows.fromRow(rows.first);
  }

  @override
  Future<void> replace(String oldTokenHash, DVSessionRecord record) async {
    await _ensure();
    final Map<String, Object?> row = _DVSessionRows.toRow(record);
    // One statement, so the old token stops authenticating in the same write
    // that makes the new one start.
    await adapter.execute(
      'UPDATE $table SET token_hash = ?, id = ?, last_seen_at = ?, mfa_at = ?, '
      'claims = ? WHERE token_hash = ?',
      <Object?>[
        row['token_hash'],
        row['id'],
        row['last_seen_at'],
        row['mfa_at'],
        row['claims'],
        oldTokenHash,
      ],
    );
  }

  @override
  Future<void> touch(String tokenHash, DateTime lastSeenAt) async {
    await _ensure();
    await adapter.execute(
      'UPDATE $table SET last_seen_at = ? WHERE token_hash = ?',
      <Object?>[lastSeenAt.millisecondsSinceEpoch, tokenHash],
    );
  }

  @override
  Future<void> revoke(String id, DateTime at) async {
    await _ensure();
    await adapter.execute(
      'UPDATE $table SET revoked_at = ? WHERE id = ?',
      <Object?>[at.millisecondsSinceEpoch, id],
    );
  }

  @override
  Future<List<DVSessionRecord>> forUser(String userId) async {
    await _ensure();
    final List<Map<String, Object?>> rows = await adapter.query(
      'SELECT $_columns FROM $table WHERE user_id = ?',
      <Object?>[userId],
    );
    return rows.map(_DVSessionRows.fromRow).toList();
  }

  @override
  Future<List<Map<String, Object?>>> debugRows() async {
    await _ensure();
    return adapter.query('SELECT * FROM $table');
  }
}

abstract final class _DVSessionRows {
  static Map<String, Object?> toRow(DVSessionRecord record) {
    final DVSession s = record.session;
    return <String, Object?>{
      'token_hash': record.tokenHash,
      'id': s.id,
      'user_id': s.userId,
      'tenant': s.tenant,
      'created_at': s.createdAt.millisecondsSinceEpoch,
      'last_seen_at': s.lastSeenAt.millisecondsSinceEpoch,
      'mfa_at': s.mfaSatisfiedAt?.millisecondsSinceEpoch,
      'revoked_at': s.revokedAt?.millisecondsSinceEpoch,
      'device': s.device,
      'location': s.location,
      'claims': jsonEncode(s.claims),
    };
  }

  static DVSessionRecord fromRow(Map<String, Object?> row) {
    DateTime? time(Object? value) => value == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch((value as num).toInt(),
            isUtc: true);
    final Object? claims = row['claims'];
    return DVSessionRecord(
      row['token_hash']! as String,
      DVSession(
        id: row['id']! as String,
        userId: row['user_id']! as String,
        tenant: row['tenant'] as String? ?? DVTenants.defaultTenant,
        createdAt: time(row['created_at'])!,
        lastSeenAt: time(row['last_seen_at'])!,
        mfaSatisfiedAt: time(row['mfa_at']),
        revokedAt: time(row['revoked_at']),
        device: row['device'] as String?,
        location: row['location'] as String?,
        claims: claims is String && claims.isNotEmpty
            ? Map<String, Object?>.unmodifiable(
                jsonDecode(claims) as Map<String, Object?>)
            : const <String, Object?>{},
      ),
    );
  }
}

/// Issues, authenticates, rotates and revokes sessions.
class DVSessions {
  final DVSessionStore store;

  /// A session unused for this long no longer authenticates.
  final Duration idleTimeout;

  /// A session older than this no longer authenticates, however recently it
  /// was used or rotated.
  final Duration absoluteTimeout;

  final DateTime Function() _clock;
  final Random _random = Random.secure();

  DVSessions({
    DVSessionStore? store,
    this.idleTimeout = const Duration(days: 14),
    this.absoluteTimeout = const Duration(days: 30),
    DateTime Function()? clock,
  })  : store = store ?? DVMemorySessionStore(),
        _clock = clock ?? DateTime.now;

  DateTime get _now => _clock().toUtc();

  /// Every session token starts with this, so a request's authentication
  /// stage can tell the application's own session from an API key (`dvk_`),
  /// an OAuth access token (`dvat_`) and any other bearer token the
  /// application uses, without asking the store about each.
  static const String tokenPrefix = 'dvs_';

  /// Signs [userId] in on a device: a new session and the token for it.
  ///
  /// The session belongs to [tenant], or to the tenant current where it is
  /// created -- the tenant the sign-in request resolved to -- and
  /// authenticates on that tenant only.
  Future<DVIssuedSession> create(
    String userId, {
    String? tenant,
    String? device,
    String? location,
    Map<String, Object?> claims = const <String, Object?>{},
  }) async {
    final DateTime now = _now;
    final String token = _token();
    final DVSession session = DVSession(
      id: 'ses_${_secret(16)}',
      userId: userId,
      tenant: tenant ?? const DVTenants().currentTenant,
      createdAt: now,
      lastSeenAt: now,
      device: device,
      location: location,
      claims: Map<String, Object?>.unmodifiable(claims),
    );
    await store.insert(DVSessionRecord(_hash(token), session));
    return DVIssuedSession(session, token);
  }

  /// The session [token] authenticates, with why not when it does not.
  ///
  /// A valid check records use, which is what keeps an active session inside
  /// its idle timeout.
  ///
  /// With [tenant], a session issued on any other tenant is
  /// [DVSessionFailure.unknown] -- there is no session with this token here
  /// -- and its use is not recorded, so presenting it elsewhere does not keep
  /// it alive.
  Future<DVSessionCheck> check(String token, {String? tenant}) async {
    final String hash = _hash(token);
    final DVSessionRecord? record = await store.byTokenHash(hash);
    if (record == null ||
        !_sameHash(record.tokenHash, hash) ||
        (tenant != null && record.session.tenant != tenant)) {
      return const DVSessionCheck.failed(DVSessionFailure.unknown);
    }
    final DVSession session = record.session;
    if (session.revokedAt != null) {
      return const DVSessionCheck.failed(DVSessionFailure.revoked);
    }
    final DateTime now = _now;
    if (_expired(session, now)) {
      return const DVSessionCheck.failed(DVSessionFailure.expired);
    }
    await store.touch(hash, now);
    return DVSessionCheck.valid(session._copy(lastSeenAt: now, isCurrent: true));
  }

  /// The session [token] authenticates, or null.
  Future<DVSession?> authenticate(String token) async =>
      (await check(token)).session;

  /// Reissues the token for [token]'s session. The old token stops
  /// authenticating in the same write.
  Future<DVIssuedSession> rotate(String token) => _rotate(token);

  /// Rotates and merges [claims] over the session's own — a privilege change,
  /// which is the boundary fixation exploits.
  Future<DVIssuedSession> elevate(
    String token, {
    required Map<String, Object?> claims,
  }) =>
      _rotate(token, claims: claims);

  /// Rotates and records that a second factor was presented now.
  Future<DVIssuedSession> completeMfa(String token) =>
      _rotate(token, mfaSatisfied: true);

  Future<DVIssuedSession> _rotate(
    String token, {
    Map<String, Object?>? claims,
    bool mfaSatisfied = false,
  }) async {
    final DVSessionCheck current = await check(token);
    final DVSession? session = current.session;
    if (session == null) throw DVSessionInvalid(current.failure!);
    final DateTime now = _now;
    final String next = _token();
    final DVSession rotated = session._copy(
      id: 'ses_${_secret(16)}',
      lastSeenAt: now,
      claims: claims == null
          ? null
          : Map<String, Object?>.unmodifiable(
              <String, Object?>{...session.claims, ...claims}),
      mfaSatisfiedAt: mfaSatisfied ? now : null,
      isCurrent: true,
    );
    await store.replace(_hash(token), DVSessionRecord(_hash(next), rotated));
    return DVIssuedSession(rotated, next);
  }

  /// The session [token] authenticates, if it meets [policy]; otherwise
  /// [DVMfaRequired] when the second factor is missing or stale, and
  /// [DVSessionInvalid] when there is no live session at all.
  Future<DVSession> requireMfa(String token, DVMfa policy) async {
    final DVSessionCheck current = await check(token);
    final DVSession? session = current.session;
    if (session == null) throw DVSessionInvalid(current.failure!);
    if (!policy.isSatisfiedBy(session, _now)) {
      throw DVMfaRequired(policy, session.id);
    }
    return session;
  }

  /// Every live session of [userId], newest sign-in first, with the one
  /// [currentToken] authenticates marked current.
  Future<List<DVSession>> list(String userId, {String? currentToken}) async {
    final DateTime now = _now;
    final String? currentHash =
        currentToken == null ? null : _hash(currentToken);
    final List<DVSessionRecord> records = await store.forUser(userId);
    final List<DVSession> live = <DVSession>[
      for (final DVSessionRecord record in records)
        if (record.session.revokedAt == null && !_expired(record.session, now))
          record.session._copy(
            isCurrent: currentHash != null &&
                _sameHash(record.tokenHash, currentHash),
          ),
    ]..sort((DVSession a, DVSession b) => b.createdAt.compareTo(a.createdAt));
    return live;
  }

  /// Revokes one session by its listed [id]. Its next request fails.
  Future<void> revoke(String id) => store.revoke(id, _now);

  /// Revokes every other live session of the person [currentToken] belongs
  /// to, and returns how many.
  Future<int> revokeOthers(String currentToken) async {
    final DVSessionCheck current = await check(currentToken);
    final DVSession? session = current.session;
    if (session == null) throw DVSessionInvalid(current.failure!);
    int revoked = 0;
    for (final DVSession other in await list(session.userId)) {
      if (other.id == session.id) continue;
      await store.revoke(other.id, _now);
      revoked++;
    }
    return revoked;
  }

  bool _expired(DVSession session, DateTime now) =>
      now.difference(session.lastSeenAt) >= idleTimeout ||
      now.difference(session.createdAt) >= absoluteTimeout;

  String _token() => '$tokenPrefix${_secret(32)}';

  String _secret(int bytes) => base64Url
      .encode(List<int>.generate(bytes, (_) => _random.nextInt(256)))
      .replaceAll('=', '');

  static String _hash(String token) =>
      crypto.sha256.convert(utf8.encode(token)).toString();

  static bool _sameHash(String a, String b) {
    if (a.length != b.length) return false;
    int difference = 0;
    for (int i = 0; i < a.length; i++) {
      difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return difference == 0;
  }
}

/// The session cookie on server-rendered targets.
///
/// Its attributes are not the application's to weaken: `HttpOnly`, `Secure`
/// and a `__Host-` name outside development, `SameSite=Lax` or `Strict`. A
/// cross-site session (`SameSite=None`) is a configuration error naming the
/// setting (`DV-SESSION-003`) rather than a quietly weaker cookie.
class DVSessionCookie {
  final String name;
  final String sameSite;

  /// How long the browser keeps the cookie, or null for the browser session.
  final Duration? maxAge;

  const DVSessionCookie({
    this.name = 'dv_session',
    this.sameSite = 'Lax',
    this.maxAge,
  });

  static final RegExp _cookieSafe = RegExp(r'^[A-Za-z0-9_\-]+$');

  /// The name the cookie is set under. `__Host-` requires `Secure`, which
  /// plain-HTTP development cannot have, so development drops both rather
  /// than setting a cookie the browser silently refuses.
  String cookieName({required bool development}) =>
      development ? name : '__Host-$name';

  /// A `Set-Cookie` value carrying [token].
  String header(String token, {required bool development}) {
    final String site = _validatedSameSite();
    if (!_cookieSafe.hasMatch(token)) {
      throw ArgumentError('A session token is URL-safe base64.');
    }
    final Duration? age = maxAge;
    return <String>[
      '${cookieName(development: development)}=$token',
      'Path=/',
      'HttpOnly',
      if (!development) 'Secure',
      'SameSite=$site',
      if (age != null) 'Max-Age=${age.inSeconds}',
    ].join('; ');
  }

  /// A `Set-Cookie` value that removes the cookie, for sign-out and
  /// revocation.
  String clearHeader({required bool development}) => <String>[
        '${cookieName(development: development)}=',
        'Path=/',
        'HttpOnly',
        if (!development) 'Secure',
        'SameSite=${_validatedSameSite()}',
        'Max-Age=0',
      ].join('; ');

  /// The token in a request's `Cookie` header, or null.
  String? read(String? cookieHeader, {required bool development}) {
    if (cookieHeader == null) return null;
    final String wanted = cookieName(development: development);
    for (final String part in cookieHeader.split(';')) {
      final int equals = part.indexOf('=');
      if (equals < 0) continue;
      if (part.substring(0, equals).trim() != wanted) continue;
      final String value = part.substring(equals + 1).trim();
      return value.isEmpty ? null : value;
    }
    return null;
  }

  String _validatedSameSite() {
    switch (sameSite.toLowerCase()) {
      case 'lax':
        return 'Lax';
      case 'strict':
        return 'Strict';
    }
    throw DVSessionConfigError(
      setting: 'sameSite',
      value: sameSite,
      reason: sameSite.toLowerCase() == 'none'
          ? 'SameSite=None makes the session cross-site, which a first-party '
              'session never needs and a CSRF attack always does'
          : 'SameSite takes Lax or Strict',
    );
  }
}

/// A session setting weaker than a deployment allows (`DV-SESSION-003`).
class DVSessionConfigError extends Error {
  final String setting;
  final String value;
  final String reason;

  DVSessionConfigError({
    required this.setting,
    required this.value,
    required this.reason,
  });

  String get code => 'DV-SESSION-003';

  @override
  String toString() => '$code: session $setting "$value" refused — $reason.';
}
