/// Who may open Studio, the admin dashboard, on a deployed application.
///
/// Not everybody who can sign in. An application that lets customers sign
/// up gives every customer a live session, and a dashboard that opened for
/// any session handed each of them the application's models, routes, jobs
/// and data. So opening it is an authorization question, asked through
/// `DV.Auth.authorization` like every other: may this caller
/// [dvStudioAccessAction]?
///
/// Nobody may, by default. The framework's answer is a grant kept in the
/// application's database, written by `dartvel admin grant`, and an
/// application that already knows who its operators are registers its own
/// answer with `registerAction(dvStudioAccessAction, ...)`, which is asked
/// instead.
library;

import '../../dartvel.dart' show DVAuthAuthorization;
import '../auth/session_authentication.dart';
import '../database/adapter.dart';
import '../database/framework_tables.dart';
import '../tenancy/tenants.dart';

/// The action a signed-in caller needs to open Studio.
const String dvStudioAccessAction = 'Studio.access';

/// One person allowed into Studio, on one tenant.
typedef DVStudioGrant = ({String userId, String tenant, DateTime grantedAt});

/// The Studio grants, kept in the application's database.
class DVStudioGrants {
  DVStudioGrants(
    this.adapter, {
    this.table = 'dv_studio_grants',
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final DVDatabaseAdapter adapter;
  final String table;
  final DateTime Function() _clock;

  Future<void>? _ready;

  Future<void> _ensure() => _ready ??= dvEnsureFrameworkTable(
        adapter,
        'CREATE TABLE IF NOT EXISTS $table ('
        'user_id TEXT, tenant TEXT, granted_at BIGINT)',
      );

  /// Lets [userId] open Studio on [tenant]. Granting twice is one grant.
  Future<void> grant(
    String userId, {
    String tenant = DVTenants.defaultTenant,
  }) async {
    final String user = _required(userId, 'userId');
    if (await isGranted(user, tenant: tenant)) return;
    await adapter.execute(
      'INSERT INTO $table (user_id, tenant, granted_at) VALUES (?, ?, ?)',
      <Object?>[user, tenant, _clock().toUtc().millisecondsSinceEpoch],
    );
  }

  /// Takes the grant away. False when there was none.
  Future<bool> revoke(
    String userId, {
    String tenant = DVTenants.defaultTenant,
  }) async {
    final String user = _required(userId, 'userId');
    if (!await isGranted(user, tenant: tenant)) return false;
    await adapter.execute(
      'DELETE FROM $table WHERE user_id = ? AND tenant = ?',
      <Object?>[user, tenant],
    );
    return true;
  }

  /// Whether [userId] may open Studio on [tenant].
  Future<bool> isGranted(
    String userId, {
    String tenant = DVTenants.defaultTenant,
  }) async {
    if (userId.isEmpty) return false;
    await _ensure();
    final List<Map<String, Object?>> rows = await adapter.query(
      'SELECT user_id FROM $table WHERE user_id = ? AND tenant = ?',
      <Object?>[userId, tenant],
    );
    return rows.isNotEmpty;
  }

  /// Every grant, oldest first.
  Future<List<DVStudioGrant>> list() async {
    await _ensure();
    final List<Map<String, Object?>> rows = await adapter.query(
      'SELECT user_id, tenant, granted_at FROM $table ORDER BY granted_at',
    );
    return <DVStudioGrant>[
      for (final Map<String, Object?> row in rows)
        (
          userId: '${row['user_id']}',
          tenant: '${row['tenant']}',
          grantedAt: DateTime.fromMillisecondsSinceEpoch(
              (row['granted_at'] as num?)?.toInt() ?? 0,
              isUtc: true),
        ),
    ];
  }

  /// Makes these grants the framework's answer to [dvStudioAccessAction]: a
  /// signed-in session whose user was granted on the session's tenant.
  /// Anything else -- no session, an API key, a person nobody granted -- is
  /// refused.
  void install() {
    const DVAuthAuthorization().registerDeclaredAction(
      dvStudioAccessAction,
      (Object? caller, Object? _) async {
        final DVSessionPrincipal? principal =
            caller is DVSessionPrincipal ? caller : DVSessionPrincipal.current;
        if (principal == null) return false;
        return isGranted(principal.userId, tenant: principal.tenant);
      },
    );
  }

  static String _required(String value, String name) {
    final String trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(value, name, 'must not be empty');
    }
    return trimmed;
  }
}
