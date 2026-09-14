/// API keys: how somebody else's software calls an application that is a
/// platform.
///
/// The runtime the specification's `# Platform API: Keys, Scopes and OAuth
/// Provider` describes under Keys. What goes wrong here goes wrong silently,
/// so each guard is stated where it lives:
///
/// * the secret is shown once, at issue, and only its SHA-256 is stored -- a
///   leaked table is not a list of working keys ([DVSecretHash]);
/// * the id before the secret is stored in clear, so support can tell which
///   key somebody means, and the hash is compared in constant time;
/// * rotation overlaps: the replacement is live at once and the old key
///   keeps working until the overlap ends (`DV-APIKEY-003` afterwards), while
///   revocation is immediate;
/// * a key belongs to one organization on one tenant, and a request resolved
///   to another tenant does not authenticate with it;
/// * issue, rotation and revocation are [DVRecordTable] writes with history,
///   so each carries its actor, tenant and transaction.
library dartvel_core.auth.api_keys;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../data/record_history.dart';
import '../database/adapter.dart';
import '../metering/meters.dart';
import '../middleware/middleware.dart';
import '../observability/observability.dart';
import '../tenancy/tenants.dart';
import '../transaction/transaction.dart';
import 'api_scopes.dart';
import 'organizations.dart';
import 'secret_hash.dart';

/// One issued key, as stored. Nothing on it is the secret.
class DVApiKey {
  const DVApiKey({
    required this.id,
    required this.organizationId,
    required this.tenant,
    required this.scopes,
    required this.createdAt,
    this.name,
    this.expiresAt,
    this.revokedAt,
    this.rotatedFrom,
    this.rotatedTo,
    this.ratePlan,
    this.createdBy,
  });

  /// The identifying part, stored in clear.
  final String id;
  final String organizationId;
  final String tenant;
  final List<String> scopes;
  final DateTime createdAt;
  final String? name;
  final DateTime? expiresAt;
  final DateTime? revokedAt;

  /// The key this one replaced.
  final String? rotatedFrom;

  /// The key that replaced this one.
  final String? rotatedTo;
  final String? ratePlan;
  final String? createdBy;

  /// What a person sees in a key list: `dvk_<id>`.
  String get prefix => '${DVApiKeys.keyPrefix}$id';

  bool isLiveAt(DateTime now) {
    final DateTime? expiry = expiresAt;
    return revokedAt == null && (expiry == null || now.isBefore(expiry));
  }

  @override
  String toString() => 'DVApiKey($prefix for $organizationId)';
}

/// A key and its secret, returned once, at issue.
class DVIssuedApiKey {
  const DVIssuedApiKey(this.key, this.secret, {this.codes = const <String>[]});

  final DVApiKey key;

  /// The only copy. Show it to the person issuing the key; never store or log
  /// it.
  final String secret;

  /// Diagnostics raised by issuing (`DV-APIKEY-005`).
  final List<String> codes;

  @override
  String toString() => 'DVIssuedApiKey(${key.prefix})';
}

enum DVApiKeyFailure {
  /// Not a key, or no key has this id and secret.
  invalid,
  revoked,
  expired,

  /// Issued for another tenant than the request resolved to.
  wrongTenant,

  /// The organization the key belongs to is closed or gone.
  organizationClosed,
}

/// The outcome of checking a presented key.
class DVApiKeyCheck {
  const DVApiKeyCheck.valid(DVApiKey this.key, DVApiPrincipal this.principal)
    : failure = null,
      code = null;

  const DVApiKeyCheck.failed(
    DVApiKeyFailure this.failure, {
    this.key,
    this.code,
  }) : principal = null;

  final DVApiPrincipal? principal;

  /// The key the presented secret named, when it named a real one.
  final DVApiKey? key;
  final DVApiKeyFailure? failure;

  /// `DV-APIKEY-003` when the key stopped at the end of a rotation overlap.
  final String? code;

  /// What a caller is told. The same words for every failure, so a caller
  /// cannot probe which ids exist or which keys were revoked.
  String get reveal => 'Invalid API key.';
}

/// Rotation asked of a key that is revoked, expired, gone or already
/// rotated.
class DVApiKeyNotLive implements Exception {
  const DVApiKeyNotLive(this.id, this.reason);

  final String id;
  final String reason;

  @override
  String toString() => 'DVApiKeyNotLive(${DVApiKeys.keyPrefix}$id: $reason)';
}

/// Requests per window for a key on this plan.
class DVApiRatePlan {
  const DVApiRatePlan({required this.maxRequests, required this.window});

  final int maxRequests;
  final Duration window;
}

/// Issues, authenticates, rotates and revokes API keys, over one database.
class DVApiKeys {
  DVApiKeys({
    required this.database,
    required this.scopes,
    this.organizations,
    this.requireExpiry = false,
    this.defaultOverlap = const Duration(days: 7),
    DateTime Function()? clock,
    Random? random,
    DVLogger? logger,
  }) : _clock = clock ?? (() => DateTime.now().toUtc()),
       _random = random ?? Random.secure(),
       _logger = logger {
    _keys = DVRecordTable(
      table: 'dv_api_keys',
      key: 'id',
      columns: const <String>[
        'id',
        'secret_hash',
        'name',
        'organization_id',
        'tenant',
        'scopes',
        'rate_plan',
        'created_by',
        'created_at',
        'expires_at',
        'revoked_at',
        'rotated_from',
        'rotated_to',
      ],
      // History records that the hash was written, never the hash: a change
      // log is a second copy of the table with a different lifetime.
      sensitive: const <String>{'secret_hash'},
      history: const DVHistory(),
      database: database,
    );
  }

  /// Every key starts with this, so a scanner can find one pasted where it
  /// should not be.
  static const String keyPrefix = 'dvk_';

  /// Where [authentication] puts the principal on a [MiddlewareContext].
  static const String principalKey = 'dv.apiPrincipal';

  static const int _idBytes = 8;
  static const int _secretBytes = 32;
  static final RegExp _idPattern = RegExp(r'^[0-9a-f]{16}$');
  static final RegExp _secretPattern = RegExp(r'^[A-Za-z0-9_\-]{43}$');

  /// A hash to compare against when no key has the presented id, so an
  /// unknown id costs the same as a wrong secret.
  static final String _absentHash = DVSecretHash.of('dvk_absent');

  final DVDatabaseAdapter database;
  final DVApiScopes scopes;

  /// When given, a key stops authenticating when its organization closes.
  final DVOrganizations? organizations;

  /// Whether a key issued with no expiry raises `DV-APIKEY-005`.
  final bool requireExpiry;

  /// How long a rotated key keeps working when [rotate] is given no overlap.
  final Duration defaultOverlap;

  final DateTime Function() _clock;
  final Random _random;
  final DVLogger? _logger;
  late final DVRecordTable _keys;

  DVLogger get _log => _logger ?? DVObservability.logger;

  DateTime _now() => _clock().toUtc();

  Future<void> ensureSchema() => _keys.ensureSchema();

  /// Issues a key for [organization] with [scopes].
  Future<DVIssuedApiKey> issue({
    required DVOrganization organization,
    required List<String> scopes,
    Duration? expiresIn,
    String? name,
    String? ratePlan,
    String? actor,
  }) async {
    final DVOrganization current = await _open(organization);
    if (scopes.isEmpty) {
      throw ArgumentError.value(
        scopes,
        'scopes',
        'a key with no scopes can do nothing',
      );
    }
    this.scopes.requireDeclared(scopes);
    if (expiresIn != null && expiresIn <= Duration.zero) {
      throw ArgumentError.value(expiresIn, 'expiresIn', 'must be positive');
    }
    final DateTime now = _now();
    return _insert(
      organizationId: current.id,
      tenant: current.tenant,
      scopes: scopes,
      now: now,
      expiresAt: expiresIn == null ? null : now.add(expiresIn),
      name: name,
      ratePlan: ratePlan,
      actor: actor,
    );
  }

  /// Checks [presented], with the reason when it does not authenticate.
  ///
  /// [tenant] is the tenant the request resolved to. When it is not given
  /// and the call runs inside a `DV.Tenants.withTenant` scope, that scope's
  /// tenant is the one the key must belong to.
  Future<DVApiKeyCheck> check(String presented, {String? tenant}) async {
    final String? id = _idOf(presented);
    if (id == null) {
      return const DVApiKeyCheck.failed(DVApiKeyFailure.invalid);
    }
    final DVRecord? record = await _keys.read(id);
    if (record == null) {
      DVSecretHash.matches(_absentHash, presented);
      return const DVApiKeyCheck.failed(DVApiKeyFailure.invalid);
    }
    if (!DVSecretHash.matches('${record.values['secret_hash']}', presented)) {
      return const DVApiKeyCheck.failed(DVApiKeyFailure.invalid);
    }
    final DVApiKey key = _keyFrom(record);
    final DateTime now = _now();
    if (key.revokedAt != null) {
      return DVApiKeyCheck.failed(DVApiKeyFailure.revoked, key: key);
    }
    final DateTime? expiry = key.expiresAt;
    if (expiry != null && !now.isBefore(expiry)) {
      if (key.rotatedTo == null) {
        return DVApiKeyCheck.failed(DVApiKeyFailure.expired, key: key);
      }
      _log.info(
        'DV-APIKEY-003: rotation overlap expired; ${key.prefix} no longer '
        'authenticates, its replacement is ${keyPrefix}${key.rotatedTo}.',
      );
      return DVApiKeyCheck.failed(
        DVApiKeyFailure.expired,
        key: key,
        code: 'DV-APIKEY-003',
      );
    }
    final String? requested =
        tenant ?? (DVTenants.hasScope ? const DVTenants().currentTenant : null);
    if (requested != null && requested != key.tenant) {
      return DVApiKeyCheck.failed(DVApiKeyFailure.wrongTenant, key: key);
    }
    final DVOrganizations? orgs = organizations;
    if (orgs != null) {
      final DVOrganization? organization = await orgs.find(key.organizationId);
      if (organization == null || organization.isClosed) {
        return DVApiKeyCheck.failed(
          DVApiKeyFailure.organizationClosed,
          key: key,
        );
      }
    }
    return DVApiKeyCheck.valid(key, principalFor(key));
  }

  /// The principal [presented] authenticates as, or null.
  Future<DVApiPrincipal?> authenticate(
    String presented, {
    String? tenant,
  }) async => (await check(presented, tenant: tenant)).principal;

  /// The principal [key] acts as, with its scopes resolved under the current
  /// declaration.
  DVApiPrincipal principalFor(DVApiKey key) => DVApiPrincipal(
    kind: DVApiPrincipalKind.apiKey,
    subject: key.id,
    tenant: key.tenant,
    organizationId: key.organizationId,
    scopes: key.scopes.toSet(),
    actions: scopes.actionsOf(key.scopes),
    ratePlan: key.ratePlan,
    expiresAt: key.expiresAt,
  );

  /// Issues a replacement for key [id] and leaves [id] working for [overlap]
  /// (or [defaultOverlap]), never past its own expiry.
  ///
  /// The replacement has the same organization, scopes and rate plan, and the
  /// lifetime the original was issued with, counted from now.
  Future<DVIssuedApiKey> rotate(
    String id, {
    Duration? overlap,
    String? actor,
  }) async {
    final DVRecord? record = await _keys.read(id);
    if (record == null) throw DVApiKeyNotLive(id, 'no such key');
    final DVApiKey key = _keyFrom(record);
    final DateTime now = _now();
    if (!key.isLiveAt(now)) {
      throw DVApiKeyNotLive(
        id,
        key.revokedAt != null ? 'it was revoked' : 'it has expired',
      );
    }
    if (key.rotatedTo != null) {
      throw DVApiKeyNotLive(
        id,
        'it was already rotated to $keyPrefix${key.rotatedTo}',
      );
    }
    final DVOrganizations? orgs = organizations;
    if (orgs != null) {
      final DVOrganization? organization = await orgs.find(key.organizationId);
      if (organization == null) {
        throw DVApiKeyNotLive(id, 'its organization no longer exists');
      }
      await _open(organization);
    }
    final Duration window = overlap ?? defaultOverlap;
    if (window < Duration.zero) {
      throw ArgumentError.value(window, 'overlap', 'cannot be negative');
    }
    final DateTime? expiry = key.expiresAt;
    DateTime oldExpiry = now.add(window);
    if (expiry != null && expiry.isBefore(oldExpiry)) oldExpiry = expiry;

    return DVTransactionRunner()<DVIssuedApiKey>((DVContext context) async {
      final DVIssuedApiKey next = await _insert(
        organizationId: key.organizationId,
        tenant: key.tenant,
        scopes: key.scopes,
        now: now,
        expiresAt: expiry == null
            ? null
            : now.add(expiry.difference(key.createdAt)),
        name: key.name,
        ratePlan: key.ratePlan,
        actor: actor,
        rotatedFrom: key.id,
      );
      await _keys.write(
        <String, Object?>{
          ...record.values,
          'expires_at': _stamp(oldExpiry),
          'rotated_to': next.key.id,
        },
        base: record,
        actor: actor,
        tenant: key.tenant,
      );
      return next;
    });
  }

  /// Revokes key [id]. Its next call fails; there is no overlap.
  Future<void> revoke(String id, {String? actor}) async {
    final DVRecord? record = await _keys.read(id);
    if (record == null) throw DVApiKeyNotLive(id, 'no such key');
    if (record.values['revoked_at'] != null) return;
    await _keys.write(
      <String, Object?>{...record.values, 'revoked_at': _stamp(_now())},
      base: record,
      actor: actor,
      tenant: '${record.values['tenant']}',
    );
  }

  /// The key with [id], revoked or expired ones included.
  Future<DVApiKey?> find(String id) async {
    final DVRecord? record = await _keys.read(id);
    return record == null ? null : _keyFrom(record);
  }

  /// Every key of [organizationId], oldest first.
  Future<List<DVApiKey>> forOrganization(String organizationId) async {
    final List<Map<String, Object?>> rows = await database.query(
      'SELECT id FROM dv_api_keys WHERE organization_id = ?',
      <Object?>[organizationId],
    );
    final List<DVApiKey> keys = <DVApiKey>[
      for (final Map<String, Object?> row in rows)
        if (await find('${row['id']}') case final DVApiKey key) key,
    ]..sort((DVApiKey a, DVApiKey b) => a.createdAt.compareTo(b.createdAt));
    return keys;
  }

  /// Who issued, rotated and revoked key [id], and when.
  Future<List<DVHistoryEntry>> audit(String id) => _keys.history(id);

  /// The authentication stage: the credential [credentialOf] finds on the
  /// request becomes the principal under [principalKey], or the call stops.
  Middleware authentication({
    required String? Function(Object? request) credentialOf,
  }) => (Object? request, MiddlewareContext context) async {
    final String? credential = credentialOf(request);
    if (credential == null) {
      context
        ..abort()
        ..data['authError'] = 'Unauthorized';
      return;
    }
    final DVApiKeyCheck result = await check(credential);
    final DVApiPrincipal? principal = result.principal;
    if (principal == null) {
      context
        ..abort()
        ..data['authError'] = result.reveal;
      if (result.code != null) context.data['diagnostic'] = result.code;
      return;
    }
    context.data[principalKey] = principal;
  };

  /// Each key's rate plan, enforced by the rate-limiting middleware that
  /// already exists, one limiter per plan counting per key.
  ///
  /// A key whose plan is not in [plans] is refused rather than let through
  /// unlimited: a typo in a plan name is otherwise an unmetered partner. A key
  /// with no plan takes [unplanned], or is not limited here when that is null.
  Middleware rateLimit(
    Map<String, DVApiRatePlan> plans, {
    DVApiRatePlan? unplanned,
  }) {
    final Map<String, Middleware> limiters = <String, Middleware>{};
    String? caller;
    return (Object? request, MiddlewareContext context) async {
      final DVApiPrincipal? principal = _principalOn(context);
      if (principal == null) return;
      final String? planName = principal.ratePlan;
      final DVApiRatePlan? plan = planName == null
          ? unplanned
          : plans[planName];
      if (plan == null) {
        if (planName == null) return;
        context
          ..abort()
          ..data['rateLimitError'] = 'Rate plan "$planName" is not declared';
        return;
      }
      final Middleware limiter = limiters[planName ?? ''] ??=
          CommonMiddleware.rateLimit(
            maxRequests: plan.maxRequests,
            window: plan.window,
            clientIdentifier: (_) => caller!,
          );
      // The limiter reads its identifier synchronously, before this call
      // returns, so no other request can change [caller] in between.
      caller = principal.subject;
      final FutureOr<void> pending = limiter(request, context);
      caller = null;
      await pending;
      if (!context.shouldContinue) {
        context.data['diagnostic'] = 'DV-APIKEY-006';
        _log.warn(
          'DV-APIKEY-006: $keyPrefix${principal.subject} exceeded rate plan '
          '"${planName ?? 'unplanned'}"; the call was throttled.',
        );
      }
    };
  }

  /// Records one call against [meter] on the key's tenant, idempotently per
  /// request, and stops the call when the meter does not admit it.
  Middleware usage({
    required DVMeters meters,
    required DVMeterDefinition meter,
    required String Function(Object? request) requestIdOf,
  }) => (Object? request, MiddlewareContext context) async {
    final DVApiPrincipal? principal = _principalOn(context);
    if (principal == null) return;
    final DVMeterOutcome outcome = await principal.run(
      () => meters.record(
        meter,
        1,
        idempotencyKey: '${principal.subject}:${requestIdOf(request)}',
      ),
    );
    if (!outcome.admitted) {
      context
        ..abort()
        ..data['quotaError'] = 'Quota exceeded';
      if (outcome.codes.isNotEmpty) {
        context.data['diagnostic'] = outcome.codes.first;
      }
    }
  };

  DVApiPrincipal? _principalOn(MiddlewareContext context) {
    final Object? principal = context.data[principalKey];
    if (principal is DVApiPrincipal) return principal;
    // Limits placed before authentication would limit nobody.
    context
      ..abort()
      ..data['authError'] = 'Unauthorized';
    return null;
  }

  Future<DVOrganization> _open(DVOrganization organization) async {
    final DVOrganization current =
        await organizations?.find(organization.id) ?? organization;
    final DateTime? closedAt = current.closedAt;
    if (closedAt != null) {
      final DateTime until = closedAt.add(
        organizations?.closeGrace ?? DVOrganizations.defaultCloseGrace,
      );
      throw DVOrganizationClosed(
        current.id,
        closedAt: closedAt,
        restorableUntil: until,
        expired: !_now().isBefore(until),
      );
    }
    return current;
  }

  Future<DVIssuedApiKey> _insert({
    required String organizationId,
    required String tenant,
    required List<String> scopes,
    required DateTime now,
    required DateTime? expiresAt,
    required String? name,
    required String? ratePlan,
    required String? actor,
    String? rotatedFrom,
  }) async {
    final String id = DVSecretHash.hex(_random, _idBytes);
    final String secret =
        '$keyPrefix${id}_${DVSecretHash.token(_random, _secretBytes)}';
    final List<String> sorted = scopes.toSet().toList()..sort();
    final List<String> codes = <String>[];
    if (requireExpiry && expiresAt == null) {
      codes.add('DV-APIKEY-005');
      _log.warn(
        'DV-APIKEY-005: $keyPrefix$id was issued with no expiry, and the '
        'configuration requires one.',
      );
    }
    final DVRecord record = (await _keys.write(
      <String, Object?>{
        'id': id,
        'secret_hash': DVSecretHash.of(secret),
        'name': name,
        'organization_id': organizationId,
        'tenant': tenant,
        'scopes': jsonEncode(sorted),
        'rate_plan': ratePlan,
        'created_by': actor,
        'created_at': _stamp(now),
        'expires_at': expiresAt == null ? null : _stamp(expiresAt),
        'revoked_at': null,
        'rotated_from': rotatedFrom,
        'rotated_to': null,
      },
      actor: actor,
      tenant: tenant,
    )).record;
    return DVIssuedApiKey(_keyFrom(record), secret, codes: codes);
  }

  /// The id in [presented], when it has the shape of a key at all.
  static String? _idOf(String presented) {
    if (!presented.startsWith(keyPrefix)) return null;
    final String rest = presented.substring(keyPrefix.length);
    if (rest.length != 16 + 1 + 43 || rest[16] != '_') return null;
    final String id = rest.substring(0, 16);
    if (!_idPattern.hasMatch(id)) return null;
    if (!_secretPattern.hasMatch(rest.substring(17))) return null;
    return id;
  }

  static DVApiKey _keyFrom(DVRecord record) {
    final Map<String, Object?> v = record.values;
    return DVApiKey(
      id: '${v['id']}',
      organizationId: '${v['organization_id']}',
      tenant: '${v['tenant']}',
      scopes: List<String>.unmodifiable(
        (jsonDecode('${v['scopes']}') as List<Object?>).map(
          (Object? s) => '$s',
        ),
      ),
      createdAt: _date(v['created_at'])!,
      name: v['name'] as String?,
      expiresAt: _date(v['expires_at']),
      revokedAt: _date(v['revoked_at']),
      rotatedFrom: v['rotated_from'] as String?,
      rotatedTo: v['rotated_to'] as String?,
      ratePlan: v['rate_plan'] as String?,
      createdBy: v['created_by'] as String?,
    );
  }

  static String _stamp(DateTime at) => at.toUtc().toIso8601String();

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.parse('$value');
}
