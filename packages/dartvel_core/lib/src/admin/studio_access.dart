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
import '../database/records.dart';
import '../tenancy/tenants.dart';

/// The action a signed-in caller needs to open Studio.
const String dvStudioAccessAction = 'Studio.access';

/// One person allowed into Studio, on one tenant.
typedef DVStudioGrant = ({
  String userId,
  String tenant,
  DateTime grantedAt,
  String role,
});

/// Single configurable entitlement gate for Studio Pro features
/// (e.g. role-based access control, custom roles, and revision history).
class DVStudioEntitlements {
  const DVStudioEntitlements({
    this.rolesEnabled = true,
    this.customRolesEnabled = true,
    this.revisionsEnabled = true,
  });

  /// Whether roles and permissions (Admin, Editor, Author, Viewer) are active.
  final bool rolesEnabled;

  /// Whether custom roles and permission editing are active.
  final bool customRolesEnabled;

  /// Whether version history and revisions are active.
  final bool revisionsEnabled;

  /// The active entitlement configuration.
  static DVStudioEntitlements current = const DVStudioEntitlements();
}

/// A role defining permissions for Studio operators.
class DVStudioRole {
  const DVStudioRole({
    required this.id,
    required this.name,
    required this.description,
    this.permissions = const <String>{},
    this.isBuiltIn = true,
  });

  final String id;
  final String name;
  final String description;
  final Set<String> permissions;
  final bool isBuiltIn;

  static const DVStudioRole admin = DVStudioRole(
    id: 'admin',
    name: 'Administrator',
    description:
        'Full control over all Studio sections, data models, settings, and team access.',
    permissions: <String>{
      'pages:read',
      'pages:write',
      'media:read',
      'media:write',
      'models:read',
      'models:write',
      'routes:read',
      'routes:write',
      'functions:read',
      'functions:write',
      'team:read',
      'team:write',
      'settings:read',
      'settings:write',
    },
  );

  static const DVStudioRole editor = DVStudioRole(
    id: 'editor',
    name: 'Editor',
    description:
        'Can view, create, edit, and publish pages, media, content, models, and routes.',
    permissions: <String>{
      'pages:read',
      'pages:write',
      'media:read',
      'media:write',
      'models:read',
      'models:write',
      'routes:read',
      'routes:write',
      'functions:read',
      'team:read',
    },
  );

  static const DVStudioRole author = DVStudioRole(
    id: 'author',
    name: 'Author',
    description:
        'Can upload media and create or edit own pages and content drafts.',
    permissions: <String>{
      'pages:read',
      'pages:write',
      'media:read',
      'media:write',
      'models:read',
    },
  );

  static const DVStudioRole viewer = DVStudioRole(
    id: 'viewer',
    name: 'Viewer',
    description: 'Read-only access to browse Studio without making changes.',
    permissions: <String>{
      'pages:read',
      'media:read',
      'models:read',
      'routes:read',
      'functions:read',
      'team:read',
    },
  );

  static const List<DVStudioRole> defaultRoles = <DVStudioRole>[
    admin,
    editor,
    author,
    viewer,
  ];

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'description': description,
        'permissions': permissions.toList()..sort(),
        'isBuiltIn': isBuiltIn,
      };

  factory DVStudioRole.fromJson(Map<String, Object?> json) => DVStudioRole(
        id: '${json['id']}',
        name: '${json['name']}',
        description: '${json['description'] ?? ''}',
        permissions: <String>{
          for (final Object? p
              in (json['permissions'] as List?) ?? const <Object?>[])
            '$p',
        },
        isBuiltIn: json['isBuiltIn'] != false,
      );
}

/// The Studio grants, kept in the application's database.
class DVStudioGrants {
  DVStudioGrants(
    this.adapter, {
    this.table = 'dv_studio_grants',
    this.rolesTable = 'dv_studio_roles',
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final DVDatabaseAdapter adapter;
  final String table;
  final String rolesTable;
  final DateTime Function() _clock;

  Future<void>? _ready;
  Future<void>? _rolesReady;

  /// Records, not SQL, so Studio can be granted on a document database.
  DVRecordAdapter get _records => DVRecordAdapter.over(adapter);

  Future<void> _ensure() => _ready ??= _records.ensure(DVRecordShape(
        collection: table,
        fields: const <String, DVFieldType>{
          'user_id': DVFieldType.text,
          'tenant': DVFieldType.text,
          'granted_at': DVFieldType.integer,
          'role': DVFieldType.text,
        },
      ));

  Future<void> _ensureRoles() => _rolesReady ??= _records.ensure(DVRecordShape(
        collection: rolesTable,
        fields: const <String, DVFieldType>{
          'id': DVFieldType.text,
          'name': DVFieldType.text,
          'description': DVFieldType.text,
          'permissions': DVFieldType.text,
        },
      ));

  DVFilter _grantOf(String user, String tenant) => DVFilter.all(<DVFilter>[
        DVFilter.equals('user_id', user),
        DVFilter.equals('tenant', tenant),
      ]);

  /// Lets [userId] open Studio on [tenant] with [role].
  Future<void> grant(
    String userId, {
    String tenant = DVTenants.defaultTenant,
    String role = 'admin',
  }) async {
    final String user = _required(userId, 'userId');
    await _ensure();
    if (await isGranted(user, tenant: tenant)) {
      await _records.update(
        table,
        <String, Object?>{'role': role},
        where: _grantOf(user, tenant),
      );
      return;
    }
    await _records.insert(table, <String, Object?>{
      'user_id': user,
      'tenant': tenant,
      'granted_at': _clock().toUtc().millisecondsSinceEpoch,
      'role': role,
    });
  }

  /// Updates [userId]'s role on [tenant].
  Future<bool> updateRole(
    String userId,
    String role, {
    String tenant = DVTenants.defaultTenant,
  }) async {
    final String user = _required(userId, 'userId');
    if (!await isGranted(user, tenant: tenant)) return false;
    await _records.update(
      table,
      <String, Object?>{'role': role},
      where: _grantOf(user, tenant),
    );
    return true;
  }

  /// Returns the role for [userId] on [tenant], or null if ungranted.
  Future<String?> roleOf(
    String userId, {
    String tenant = DVTenants.defaultTenant,
  }) async {
    if (userId.isEmpty) return null;
    await _ensure();
    final List<Map<String, Object?>> rows = await _records.find(
      table,
      where: _grantOf(userId, tenant),
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (rows.first['role'] as String?) ?? 'admin';
  }

  /// Takes the grant away. False when there was none.
  Future<bool> revoke(
    String userId, {
    String tenant = DVTenants.defaultTenant,
  }) async {
    final String user = _required(userId, 'userId');
    if (!await isGranted(user, tenant: tenant)) return false;
    await _records.delete(table, where: _grantOf(user, tenant));
    return true;
  }

  /// Whether [userId] may open Studio on [tenant], optionally checking
  /// [requiredPermission].
  Future<bool> isGranted(
    String userId, {
    String tenant = DVTenants.defaultTenant,
    String? requiredPermission,
  }) async {
    if (userId.isEmpty) return false;
    await _ensure();
    final List<Map<String, Object?>> rows = await _records.find(
      table,
      where: _grantOf(userId, tenant),
      limit: 1,
    );
    if (rows.isEmpty) return false;
    if (requiredPermission == null) return true;
    final String roleId = (rows.first['role'] as String?) ?? 'admin';
    final List<DVStudioRole> roles = await listRoles();
    final DVStudioRole? role = roles.cast<DVStudioRole?>().firstWhere(
          (DVStudioRole? r) => r?.id == roleId,
          orElse: () => null,
        );
    if (role == null) return roleId == 'admin';
    return role.permissions.contains(requiredPermission);
  }

  /// Every available role (built-in and custom).
  Future<List<DVStudioRole>> listRoles() async {
    await _ensureRoles();
    final List<Map<String, Object?>> rows = await _records.find(rolesTable);
    final Map<String, DVStudioRole> all = <String, DVStudioRole>{
      for (final DVStudioRole role in DVStudioRole.defaultRoles) role.id: role,
    };
    for (final Map<String, Object?> row in rows) {
      final String id = '${row['id']}';
      final Object? permsRaw = row['permissions'];
      final Set<String> perms = permsRaw is String
          ? permsRaw.split(',').map((String s) => s.trim()).toSet()
          : <String>{};
      all[id] = DVStudioRole(
        id: id,
        name: '${row['name']}',
        description: '${row['description'] ?? ''}',
        permissions: perms,
        isBuiltIn: false,
      );
    }
    return all.values.toList();
  }

  /// Saves a custom role.
  Future<void> saveRole(DVStudioRole role) async {
    await _ensureRoles();
    final String perms = (role.permissions.toList()..sort()).join(',');
    final int existing = await _records
        .count(rolesTable, where: DVFilter.equals('id', role.id));
    if (existing > 0) {
      await _records.update(
        rolesTable,
        <String, Object?>{
          'name': role.name,
          'description': role.description,
          'permissions': perms,
        },
        where: DVFilter.equals('id', role.id),
      );
    } else {
      await _records.insert(rolesTable, <String, Object?>{
        'id': role.id,
        'name': role.name,
        'description': role.description,
        'permissions': perms,
      });
    }
  }

  /// Deletes a custom role. Throws if attempting to delete a built-in role.
  Future<bool> deleteRole(String roleId) async {
    if (DVStudioRole.defaultRoles.any((DVStudioRole r) => r.id == roleId)) {
      throw ArgumentError('Cannot delete built-in role: $roleId');
    }
    await _ensureRoles();
    final int count = await _records
        .count(rolesTable, where: DVFilter.equals('id', roleId));
    if (count == 0) return false;
    await _records.delete(rolesTable, where: DVFilter.equals('id', roleId));
    return true;
  }

  /// Every grant, oldest first.
  Future<List<DVStudioGrant>> list() async {
    await _ensure();
    final List<Map<String, Object?>> rows = await _records.find(
      table,
      orderBy: const <DVSort>[DVSort('granted_at')],
    );
    return <DVStudioGrant>[
      for (final Map<String, Object?> row in rows)
        (
          userId: '${row['user_id']}',
          tenant: '${row['tenant']}',
          grantedAt: DateTime.fromMillisecondsSinceEpoch(
              (row['granted_at'] as num?)?.toInt() ?? 0,
              isUtc: true),
          role: (row['role'] as String?) ?? 'admin',
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
