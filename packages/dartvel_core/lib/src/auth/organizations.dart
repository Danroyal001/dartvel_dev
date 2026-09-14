/// Organizations, memberships and invitations.
///
/// A tenant is a data boundary: it is in every row, it is what a backup is
/// taken of, and it does not move. An organization is a group of people on
/// one tenant: it is renamed, its members come and go, its ownership changes
/// hands, and it can be closed. One organization has exactly one tenant; a
/// tenant may have no organization at all, which is what a personal tenant is.
///
/// This is the runtime the specification's `# Organizations, Membership and
/// Invitations` describes. Rows live in [DVRecordTable]s, so every membership
/// change carries its actor and transaction in the record's history, and
/// every write inside `DV.transaction` rolls back with it. Invitations are
/// [DVAuthTokens] magic links and passcodes: single use, expiring, and stored
/// only as a hash.
library dartvel_core.auth.organizations;

import 'dart:async';
import 'dart:math';

import '../data/record_history.dart';
import '../database/adapter.dart';
import '../metering/meters.dart';
import '../tenancy/tenants.dart';
import '../transaction/transaction.dart';
import 'tokens.dart';

/// A role in an organization, ordered by declaration: the first declared role
/// is the highest.
///
/// Two roles compare only when they come from the same declaration. A role
/// from another declaration has a rank that means nothing here, and comparing
/// it would answer confidently and wrongly.
final class DVOrgRole implements Comparable<DVOrgRole> {
  const DVOrgRole._(this.name, this.rank, this.declaration);

  static const DVOrgRole owner = DVOrgRole._(
    'owner',
    0,
    DVOrgRoles._standardNames,
  );
  static const DVOrgRole admin = DVOrgRole._(
    'admin',
    1,
    DVOrgRoles._standardNames,
  );
  static const DVOrgRole member = DVOrgRole._(
    'member',
    2,
    DVOrgRoles._standardNames,
  );
  static const DVOrgRole billing = DVOrgRole._(
    'billing',
    3,
    DVOrgRoles._standardNames,
  );

  final String name;

  /// The position in [declaration]; 0 is the highest.
  final int rank;

  /// The roles this one was declared among, highest first.
  final List<String> declaration;

  bool get isOwner => name == DVOrgRoles.ownerRole;

  @override
  int compareTo(DVOrgRole other) {
    if (!_sameDeclaration(other)) {
      throw ArgumentError.value(
        other,
        'other',
        'was declared among ${other.declaration}, and $name among '
            '$declaration; their ranks do not compare',
      );
    }
    return other.rank.compareTo(rank);
  }

  bool operator >(DVOrgRole other) => compareTo(other) > 0;
  bool operator >=(DVOrgRole other) => compareTo(other) >= 0;
  bool operator <(DVOrgRole other) => compareTo(other) < 0;
  bool operator <=(DVOrgRole other) => compareTo(other) <= 0;

  bool _sameDeclaration(DVOrgRole other) {
    if (identical(declaration, other.declaration)) return true;
    if (declaration.length != other.declaration.length) return false;
    for (int i = 0; i < declaration.length; i++) {
      if (declaration[i] != other.declaration[i]) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is DVOrgRole && other.name == name && _sameDeclaration(other);

  @override
  int get hashCode => Object.hash(name, Object.hashAll(declaration));

  @override
  String toString() => 'DVOrgRole.$name';
}

/// The roles an application declares under `dartvel.organizations.roles`.
final class DVOrgRoles {
  const DVOrgRoles._const(this.names);

  DVOrgRoles(List<String> names) : names = List<String>.unmodifiable(names) {
    if (!names.contains(ownerRole)) {
      // Without an owner nobody can be the last one, and nothing stops an
      // organization from ending up with nobody able to close or transfer it.
      throw ArgumentError.value(names, 'names', 'must declare "$ownerRole"');
    }
    if (names.toSet().length != names.length) {
      throw ArgumentError.value(names, 'names', 'declares a role twice');
    }
  }

  static const String ownerRole = 'owner';

  static const List<String> _standardNames = <String>[
    'owner',
    'admin',
    'member',
    'billing',
  ];

  /// `roles: [owner, admin, member, billing]`.
  static const DVOrgRoles standard = DVOrgRoles._const(_standardNames);

  /// Highest first.
  final List<String> names;

  /// The declared role called [name] (`DV-ORG-001` when there is none).
  DVOrgRole operator [](String name) {
    final int rank = names.indexOf(name);
    if (rank < 0) throw DVUndeclaredOrgRole(name, names);
    return DVOrgRole._(name, rank, names);
  }

  DVOrgRole get owner => this[ownerRole];
}

/// An organization: a group of people on one tenant.
class DVOrganization {
  const DVOrganization({
    required this.id,
    required this.name,
    required this.tenant,
    required this.createdAt,
    this.closedAt,
  });

  final String id;
  final String name;

  /// The data boundary this organization is on. Never changes.
  final String tenant;

  final DateTime createdAt;

  /// When the organization was closed, or null while it is open.
  final DateTime? closedAt;

  bool get isClosed => closedAt != null;

  @override
  String toString() =>
      'DVOrganization($id "$name" on $tenant'
      '${isClosed ? ', closed' : ''})';
}

/// One person's role in one organization.
class DVMembership {
  const DVMembership({
    required this.organizationId,
    required this.tenant,
    required this.userId,
    required this.role,
    required this.joinedAt,
    this.email,
    this.lastActiveAt,
    this.invitedBy,
  });

  final String organizationId;
  final String tenant;
  final String userId;
  final String? email;
  final DVOrgRole role;
  final DateTime joinedAt;
  final DateTime? lastActiveAt;
  final String? invitedBy;

  /// Whether this membership gives at least [atLeast] on [organization].
  ///
  /// False for any organization other than the one this membership is in: an
  /// owner of one organization is nobody in another, and a policy that
  /// compared the role alone would let them in.
  bool grants(DVOrganization organization, DVOrgRole atLeast) =>
      organization.id == organizationId &&
      !organization.isClosed &&
      role >= atLeast;

  @override
  String toString() =>
      'DVMembership($userId as ${role.name} in $organizationId)';
}

/// A pending invitation. The secret that redeems it is not here: it went to
/// the invitee, and the token store holds only its hash.
class DVInvitation {
  const DVInvitation({
    required this.id,
    required this.organizationId,
    required this.email,
    required this.role,
    required this.invitedBy,
    required this.createdAt,
    required this.expiresAt,
  });

  final String id;
  final String organizationId;
  final String email;
  final DVOrgRole role;
  final String invitedBy;
  final DateTime createdAt;
  final DateTime expiresAt;
}

/// An invitation and the link to send for it.
class DVIssuedInvitation {
  const DVIssuedInvitation(this.invitation, this.link);

  final DVInvitation invitation;

  /// Carries the only copy of the secret: send it, do not store it.
  final DVMagicLink link;
}

/// Which memberships occupy a seat.
final class DVSeats {
  const DVSeats._(this.roles, this.activeWithin);

  /// Every member.
  static const DVSeats everyMember = DVSeats._(null, null);

  /// Members at one of [roles].
  const DVSeats.atRoles(Set<DVOrgRole> this.roles) : activeWithin = null;

  /// Members active within [period] of now.
  const DVSeats.activeWithin(Duration period)
    : roles = null,
      activeWithin = period;

  final Set<DVOrgRole>? roles;
  final Duration? activeWithin;

  bool counts(DVMembership membership, DateTime now) {
    final Set<DVOrgRole>? roles = this.roles;
    if (roles != null && !roles.contains(membership.role)) return false;
    final Duration? within = activeWithin;
    if (within != null) {
      final DateTime last = membership.lastActiveAt ?? membership.joinedAt;
      if (now.difference(last) > within) return false;
    }
    return true;
  }
}

/// Organizations, their members and their invitations, over one database.
class DVOrganizations {
  DVOrganizations({
    required this.database,
    DVAuthTokens? tokens,
    this.roles = DVOrgRoles.standard,
    this.seats = DVSeats.everyMember,
    this.seatLimit,
    DVMeters? meters,
    this.invitationLifetime = defaultInvitationLifetime,
    this.closeGrace = defaultCloseGrace,
    DateTime Function()? clock,
    Random? random,
  }) : tokens = tokens ?? DVAuthTokens(lifetime: invitationLifetime),
       _clock = clock ?? (() => DateTime.now().toUtc()),
       _random = random ?? Random.secure(),
       _meters = meters {
    _organizations = DVRecordTable(
      table: 'dv_organizations',
      key: 'id',
      columns: const <String>[
        'id',
        'name',
        'tenant',
        'created_at',
        'closed_at',
      ],
      history: const DVHistory(),
      database: database,
    );
    _memberships = DVRecordTable(
      table: 'dv_org_memberships',
      key: 'id',
      columns: const <String>[
        'id',
        'organization_id',
        'tenant',
        'user_id',
        'email',
        'role',
        'joined_at',
        'last_active_at',
        'invited_by',
      ],
      history: const DVHistory(),
      database: database,
    );
    _invitations = DVRecordTable(
      table: 'dv_org_invitations',
      key: 'id',
      columns: const <String>[
        'id',
        'organization_id',
        'email',
        'role',
        'invited_by',
        'channel',
        'created_at',
        'expires_at',
      ],
      versioned: false,
      database: database,
    );
    _domains = DVRecordTable(
      table: 'dv_org_domains',
      key: 'id',
      columns: const <String>[
        'id',
        'organization_id',
        'domain',
        'role',
        'verified_at',
      ],
      history: const DVHistory(),
      database: database,
    );
  }

  static const Duration defaultInvitationLifetime = Duration(days: 7);
  static const Duration defaultCloseGrace = Duration(days: 30);

  final DVDatabaseAdapter database;
  final DVAuthTokens tokens;
  final DVOrgRoles roles;
  final DVSeats seats;

  /// The tenant's seat limit under its plan, or null for none.
  final FutureOr<int?> Function(String tenant)? seatLimit;

  final Duration invitationLifetime;

  /// How long a closed organization can be restored.
  final Duration closeGrace;

  final DateTime Function() _clock;
  final Random _random;
  final DVMeters? _meters;

  late final DVRecordTable _organizations;
  late final DVRecordTable _memberships;
  late final DVRecordTable _invitations;
  late final DVRecordTable _domains;

  /// The tenant a person's own data lives on before they belong to any
  /// organization.
  static String personalTenantFor(String userId) => 'personal-$userId';

  /// Seats as a `DV.Meter` level: counted from memberships when asked, never
  /// kept as a second number beside them.
  DVLevelLimit get seatLevel => DVLevelLimit(
    'seats',
    count: (String tenant) async {
      final DVOrganization? organization = await forTenant(tenant);
      return organization == null ? 0 : seatsUsed(organization.id);
    },
    limit: (String tenant) async => seatLimit?.call(tenant),
    atLimit: DVQuota.block,
  );

  Future<void> ensureSchema() async {
    await _organizations.ensureSchema();
    await _memberships.ensureSchema();
    await _invitations.ensureSchema();
    await _domains.ensureSchema();
  }

  // --- organizations --------------------------------------------------------

  /// Creates an organization on [tenant] with [ownerId] as its owner.
  ///
  /// [tenant] may already hold data -- a personal tenant becoming an
  /// organization is this call, and nothing on the tenant moves.
  Future<DVOrganization> create({
    required String name,
    required String tenant,
    required String ownerId,
    String? ownerEmail,
  }) => _serially('tenant:$tenant', () async {
    final List<Map<String, Object?>> holders = await database.query(
      'SELECT id FROM dv_organizations WHERE tenant = ?',
      <Object?>[tenant],
    );
    if (holders.isNotEmpty) {
      throw DVTenantAlreadyOrganized(tenant, '${holders.first['id']}');
    }
    final DateTime now = _now();
    final String id = _newId('org');
    return DVTransactionRunner()<DVOrganization>((DVContext context) async {
      await _organizations.write(
        <String, Object?>{
          'id': id,
          'name': name,
          'tenant': tenant,
          'created_at': _stamp(now),
          'closed_at': null,
        },
        actor: ownerId,
        tenant: tenant,
      );
      await _memberships.write(
        _membershipRow(
          organizationId: id,
          tenant: tenant,
          userId: ownerId,
          email: ownerEmail,
          role: roles.owner,
          at: now,
        ),
        actor: ownerId,
        tenant: tenant,
      );
      return DVOrganization(id: id, name: name, tenant: tenant, createdAt: now);
    });
  });

  /// The organization with [id], closed ones included.
  Future<DVOrganization?> find(String id) async {
    final DVRecord? record = await _organizations.read(id);
    return record == null ? null : _organizationFrom(record);
  }

  /// The open organization on [tenant], or null.
  Future<DVOrganization?> forTenant(String tenant) async {
    final DVOrganization? organization = await _onTenant(tenant);
    return organization == null || organization.isClosed ? null : organization;
  }

  Future<DVOrganization> rename(
    String id,
    String name, {
    required String actor,
  }) => _serially(id, () async {
    final DVRecord record = await _liveRecord(id);
    final DVRecord written = (await _organizations.write(
      <String, Object?>{...record.values, 'name': name},
      base: record,
      actor: actor,
      tenant: '${record.values['tenant']}',
    )).record;
    return _organizationFrom(written);
  });

  /// Closes the organization. Restorable for [closeGrace]; its members and
  /// its tenant's data stay where they are meanwhile.
  Future<void> close(String id, {required String actor}) =>
      _serially(id, () async {
        final DVRecord record = await _liveRecord(id);
        await _organizations.write(
          <String, Object?>{...record.values, 'closed_at': _stamp(_now())},
          base: record,
          actor: actor,
          tenant: '${record.values['tenant']}',
        );
      });

  /// Reopens a closed organization within its grace period (`DV-ORG-004`
  /// after it).
  Future<DVOrganization> restore(String id, {required String actor}) =>
      _serially(id, () async {
        final DVRecord? record = await _organizations.read(id);
        if (record == null) throw DVOrganizationNotFound(id);
        final DVOrganization organization = _organizationFrom(record);
        final DateTime? closedAt = organization.closedAt;
        if (closedAt == null) return organization;
        final DateTime until = closedAt.add(closeGrace);
        if (_now().isAfter(until)) {
          throw DVOrganizationClosed(
            id,
            closedAt: closedAt,
            restorableUntil: until,
            expired: true,
          );
        }
        final DVRecord written = (await _organizations.write(
          <String, Object?>{...record.values, 'closed_at': null},
          base: record,
          actor: actor,
          tenant: organization.tenant,
        )).record;
        return _organizationFrom(written);
      });

  // --- memberships ----------------------------------------------------------

  Future<DVMembership?> membership(String organizationId, String userId) async {
    final DVRecord? record = await _memberships.read(
      _membershipKey(organizationId, userId),
    );
    return record == null ? null : _membershipFrom(record);
  }

  Future<List<DVMembership>> members(String organizationId) async {
    final List<Map<String, Object?>> rows = await database.query(
      'SELECT id FROM dv_org_memberships WHERE organization_id = ?',
      <Object?>[organizationId],
    );
    return <DVMembership>[
      for (final Map<String, Object?> row in rows)
        if (await _memberships.read(row['id']!) case final DVRecord record)
          _membershipFrom(record),
    ];
  }

  /// [userId]'s membership in the organization on the current tenant.
  ///
  /// A tenant with no organization is `DV-ORG-006`: a personal tenant has no
  /// members, and answering "none" would read as "not allowed" where the real
  /// mistake is asking at all.
  Future<DVMembership?> currentMembership(String userId) async {
    final String tenant = const DVTenants().currentTenant;
    final DVOrganization? organization = await _onTenant(tenant);
    if (organization == null) throw DVTenantHasNoOrganization(tenant);
    if (organization.isClosed) {
      throw DVOrganizationClosed(
        organization.id,
        closedAt: organization.closedAt!,
        restorableUntil: organization.closedAt!.add(closeGrace),
      );
    }
    return membership(organization.id, userId);
  }

  /// Whether [userId] holds at least [atLeast] in [organizationId]. False for
  /// a closed or unknown organization: a role check fails closed.
  Future<bool> hasRole(
    String organizationId,
    String userId,
    DVOrgRole atLeast,
  ) async {
    final DVOrganization? organization = await find(organizationId);
    if (organization == null) return false;
    final DVMembership? found = await membership(organizationId, userId);
    return found != null && found.grants(organization, _declared(atLeast));
  }

  /// Adds [userId] directly, inside the seat limit.
  Future<DVMembership> addMember(
    String organizationId,
    String userId, {
    required DVOrgRole role,
    required String actor,
    String? email,
  }) => _serially(organizationId, () async {
    final DVOrganization organization = await _live(organizationId);
    return _join(
      organization,
      userId,
      email: email,
      role: _declared(role),
      actor: actor,
    );
  });

  /// Changes a member's role. The last owner cannot be demoted (`DV-ORG-003`).
  Future<DVMembership> changeRole(
    String organizationId,
    String userId,
    DVOrgRole role, {
    required String actor,
  }) => _serially(organizationId, () async {
    final DVOrganization organization = await _live(organizationId);
    return _setRole(organization, userId, _declared(role), actor: actor);
  });

  /// Removes a member. The last owner cannot leave (`DV-ORG-003`).
  Future<void> remove(
    String organizationId,
    String userId, {
    required String actor,
  }) => _serially(organizationId, () async {
    final DVOrganization organization = await _live(organizationId);
    final DVRecord record = await _memberRecord(organizationId, userId);
    if (_membershipFrom(record).role.isOwner) {
      await _requireAnotherOwner(organizationId, userId);
    }
    await _memberships.delete(
      record.key,
      actor: actor,
      tenant: organization.tenant,
    );
  });

  /// Makes [to] an owner and [from] an admin, as one reversible unit: inside
  /// an enclosing `DV.transaction` it rolls back with it.
  Future<void> transferOwnership(
    String organizationId, {
    required String from,
    required String to,
    required String actor,
  }) => _serially(organizationId, () async {
    final DVOrganization organization = await _live(organizationId);
    final DVMembership current = _membershipFrom(
      await _memberRecord(organizationId, from),
    );
    if (!current.role.isOwner) {
      throw StateError(
        '$from is not an owner of $organizationId, so '
        'has no ownership to transfer.',
      );
    }
    await _memberRecord(organizationId, to);
    await DVTransactionRunner()<void>((DVContext context) async {
      // The successor first, so no moment exists with no owner at all.
      await _setRole(organization, to, roles.owner, actor: actor);
      await _setRole(organization, from, roles[_successorRole], actor: actor);
    });
  });

  /// Marks [userId] active now, for [DVSeats.activeWithin].
  Future<void> recordActivity(String organizationId, String userId) async {
    final DVRecord record = await _memberRecord(organizationId, userId);
    await _memberships.write(
      <String, Object?>{...record.values, 'last_active_at': _stamp(_now())},
      base: record,
      onConflict: DVConflict.lastWriteWins,
      actor: userId,
      tenant: '${record.values['tenant']}',
    );
  }

  /// The change log of one membership: who changed it, when, in which
  /// transaction.
  Future<List<DVHistoryEntry>> membershipHistory(
    String organizationId,
    String userId,
  ) => _memberships.history(_membershipKey(organizationId, userId));

  /// Seats in use: a query over memberships under [seats].
  Future<int> seatsUsed(String organizationId) async {
    final DateTime now = _now();
    return (await members(
      organizationId,
    )).where((DVMembership m) => seats.counts(m, now)).length;
  }

  // --- invitations ----------------------------------------------------------

  /// Invites [email] at [role], returning the link to send.
  ///
  /// [invitedBy] must be a member of this organization, at a role no lower
  /// than the one they hand out. An address that is already a member is
  /// refused (`DV-ORG-002`).
  Future<DVIssuedInvitation> invite(
    String organizationId,
    String email, {
    required DVOrgRole role,
    required String invitedBy,
    required Uri acceptUrl,
  }) => _serially(organizationId, () async {
    final DVInvitation invitation = await _prepareInvitation(
      organizationId,
      email,
      role,
      invitedBy,
      _linkChannel,
    );
    final DVMagicLink link = await tokens.issueMagicLink(
      '$_linkPrefix${invitation.id}',
      baseUrl: acceptUrl,
    );
    return DVIssuedInvitation(invitation, link);
  });

  /// Invites [email] with a passcode rather than a link, returning the code.
  ///
  /// The code is issued against the address, so it redeems only for the
  /// address it was sent to.
  Future<String> inviteByCode(
    String organizationId,
    String email, {
    required DVOrgRole role,
    required String invitedBy,
  }) => _serially(organizationId, () async {
    final DVInvitation invitation = await _prepareInvitation(
      organizationId,
      email,
      role,
      invitedBy,
      _codeChannel,
    );
    // One outstanding code per address, as the token store keeps one.
    for (final DVInvitation earlier in await _invitationsFor(
      organizationId,
      invitation.email,
    )) {
      if (earlier.id != invitation.id) {
        await _invitations.delete(earlier.id);
      }
    }
    return tokens.issueOtp(_codeIdentifier(organizationId, invitation.email));
  });

  /// Redeems an invitation link for the signed-in person.
  ///
  /// [email] must be the person's verified address. A link redeemed by
  /// anybody else is refused and spent -- the token store cannot be asked
  /// about a token without redeeming it -- and the invitation stays pending
  /// so it can be sent again.
  Future<DVMembership> accept(
    String token, {
    required String userId,
    required String email,
  }) async {
    final DVAuthTokenResult result = await tokens.redeemMagicLink(token);
    final String? identifier = result.identifier;
    if (identifier == null || !identifier.startsWith(_linkPrefix)) {
      throw DVInvitationInvalid(result.reveal);
    }
    final DVRecord? record = await _invitations.read(
      identifier.substring(_linkPrefix.length),
    );
    if (record == null) throw DVInvitationInvalid(result.reveal);
    return _redeem(_invitationFrom(record), userId: userId, email: email);
  }

  /// Redeems a passcode invitation for the signed-in person at [email].
  Future<DVMembership> acceptCode(
    String organizationId,
    String code, {
    required String userId,
    required String email,
  }) async {
    final String address = _normalizeEmail(email);
    final DVAuthTokenResult result = await tokens.redeemOtp(
      _codeIdentifier(organizationId, address),
      code,
    );
    if (!result.isSuccess) throw DVInvitationInvalid(result.reveal);
    final List<DVInvitation> pending = await _invitationsFor(
      organizationId,
      address,
    );
    if (pending.isEmpty) throw DVInvitationInvalid(result.reveal);
    return _redeem(pending.first, userId: userId, email: address);
  }

  /// Invitations not yet accepted and not expired.
  Future<List<DVInvitation>> pendingInvitations(String organizationId) async {
    final List<Map<String, Object?>> rows = await database.query(
      'SELECT id FROM dv_org_invitations WHERE organization_id = ?',
      <Object?>[organizationId],
    );
    final DateTime now = _now();
    return <DVInvitation>[
      for (final Map<String, Object?> row in rows)
        if (await _invitations.read(row['id']!) case final DVRecord record)
          if (_invitationFrom(record) case final DVInvitation invitation
              when !now.isAfter(invitation.expiresAt))
            invitation,
    ];
  }

  Future<void> revokeInvitation(String invitationId, {required String actor}) =>
      _invitations.delete(invitationId, actor: actor);

  // --- SSO domains ----------------------------------------------------------

  /// Declares that identities at [domain] may join at [role], once verified.
  Future<void> addDomain(
    String organizationId,
    String domain, {
    required DVOrgRole role,
    required String actor,
  }) => _serially(organizationId, () async {
    final DVOrganization organization = await _live(organizationId);
    final String name = _normalizeDomain(domain);
    await _domains.write(
      <String, Object?>{
        'id': '$organizationId:$name',
        'organization_id': organizationId,
        'domain': name,
        'role': _declared(role).name,
        'verified_at': null,
      },
      base: await _domains.read('$organizationId:$name'),
      actor: actor,
      tenant: organization.tenant,
    );
  });

  /// Records that the organization proved it controls [domain].
  Future<void> markDomainVerified(
    String organizationId,
    String domain, {
    required String actor,
  }) => _serially(organizationId, () async {
    final DVOrganization organization = await _live(organizationId);
    final DVRecord? record = await _domains.read(
      '$organizationId:${_normalizeDomain(domain)}',
    );
    if (record == null) {
      throw StateError('$domain is not declared for $organizationId.');
    }
    await _domains.write(
      <String, Object?>{...record.values, 'verified_at': _stamp(_now())},
      base: record,
      actor: actor,
      tenant: organization.tenant,
    );
  });

  /// Joins an SSO identity whose address is at a verified domain of the
  /// organization, at that domain's role (`DV-ORG-005` otherwise).
  ///
  /// [email] must come from the identity provider's assertion, not from a
  /// form. A domain matches exactly: `evilacme.test` is not `acme.test`.
  Future<DVMembership> joinByDomain(
    String organizationId, {
    required String userId,
    required String email,
  }) async {
    final String address = _normalizeEmail(email);
    final String domain = address.substring(address.lastIndexOf('@') + 1);
    final DVRecord? rule = await _domains.read('$organizationId:$domain');
    if (rule == null || rule.values['verified_at'] == null) {
      throw DVDomainNotVerified(organizationId, domain);
    }
    return _serially(organizationId, () async {
      final DVOrganization organization = await _live(organizationId);
      final DVMembership? existing = await membership(organizationId, userId);
      if (existing != null) return existing;
      return _join(
        organization,
        userId,
        email: address,
        role: roles['${rule.values['role']}'],
        actor: 'sso:$domain',
      );
    });
  }

  // --- internals ------------------------------------------------------------

  static const String _linkPrefix = 'org-invitation:';
  static const String _linkChannel = 'link';
  static const String _codeChannel = 'code';

  /// What a previous owner becomes after a transfer.
  String get _successorRole =>
      roles.names.length > 1 ? roles.names[1] : DVOrgRoles.ownerRole;

  Future<DVInvitation> _prepareInvitation(
    String organizationId,
    String email,
    DVOrgRole role,
    String invitedBy,
    String channel,
  ) async {
    await _live(organizationId);
    final DVOrgRole declared = _declared(role);
    final DVMembership? inviter = await membership(organizationId, invitedBy);
    if (inviter == null) throw DVNotAMember(organizationId, invitedBy);
    if (declared > inviter.role) {
      throw DVOrgRoleEscalation(
        organizationId,
        invitedBy,
        held: inviter.role,
        offered: declared,
      );
    }
    final String address = _normalizeEmail(email);
    final List<Map<String, Object?>> existing = await database.query(
      'SELECT id FROM dv_org_memberships WHERE organization_id = ? AND email = ?',
      <Object?>[organizationId, address],
    );
    if (existing.isNotEmpty) throw DVAlreadyAMember(organizationId, address);

    final DateTime now = _now();
    final DVInvitation invitation = DVInvitation(
      id: _newId('inv'),
      organizationId: organizationId,
      email: address,
      role: declared,
      invitedBy: invitedBy,
      createdAt: now,
      expiresAt: now.add(invitationLifetime),
    );
    await _invitations.write(<String, Object?>{
      'id': invitation.id,
      'organization_id': organizationId,
      'email': address,
      'role': declared.name,
      'invited_by': invitedBy,
      'channel': channel,
      'created_at': _stamp(now),
      'expires_at': _stamp(invitation.expiresAt),
    }, actor: invitedBy);
    return invitation;
  }

  Future<List<DVInvitation>> _invitationsFor(
    String organizationId,
    String address,
  ) async {
    final List<Map<String, Object?>> rows = await database.query(
      'SELECT id FROM dv_org_invitations WHERE organization_id = ? AND '
      'email = ? AND channel = ?',
      <Object?>[organizationId, address, _codeChannel],
    );
    return <DVInvitation>[
      for (final Map<String, Object?> row in rows)
        if (await _invitations.read(row['id']!) case final DVRecord record)
          _invitationFrom(record),
    ];
  }

  Future<DVMembership> _redeem(
    DVInvitation invitation, {
    required String userId,
    required String email,
  }) => _serially(invitation.organizationId, () async {
    final DVOrganization organization = await _live(invitation.organizationId);
    if (_now().isAfter(invitation.expiresAt)) {
      await _invitations.delete(invitation.id);
      throw const DVInvitationInvalid();
    }
    if (_normalizeEmail(email) != invitation.email) {
      throw DVInvitationEmailMismatch(invitation.id);
    }
    final DVMembership joined = await _join(
      organization,
      userId,
      email: invitation.email,
      role: invitation.role,
      actor: invitation.invitedBy,
    );
    await _invitations.delete(invitation.id);
    return joined;
  });

  /// Adds a membership, inside the seat limit. Callers hold the
  /// organization's lock: counting and inserting are two statements, and two
  /// acceptances between them would both see the last seat free.
  Future<DVMembership> _join(
    DVOrganization organization,
    String userId, {
    required String? email,
    required DVOrgRole role,
    required String actor,
  }) async {
    final String? address = email == null ? null : _normalizeEmail(email);
    if (await membership(organization.id, userId) != null) {
      throw DVAlreadyAMember(organization.id, address ?? userId);
    }
    final DVMeterOutcome outcome = await const DVTenants().withTenant(
      organization.tenant,
      () => (_meters ?? DVMeters(store: DVMemoryMeterStore(), clock: _clock))
          .admitLevel(seatLevel),
    );
    if (!outcome.admitted) {
      throw DVSeatLimitReached(
        organization.id,
        used: outcome.total,
        limit: outcome.limit,
      );
    }
    final DateTime now = _now();
    final DVRecord record = (await _memberships.write(
      _membershipRow(
        organizationId: organization.id,
        tenant: organization.tenant,
        userId: userId,
        email: address,
        role: role,
        at: now,
        invitedBy: actor,
      ),
      actor: actor,
      tenant: organization.tenant,
    )).record;
    return _membershipFrom(record);
  }

  Future<DVMembership> _setRole(
    DVOrganization organization,
    String userId,
    DVOrgRole role, {
    required String actor,
  }) async {
    final DVRecord record = await _memberRecord(organization.id, userId);
    final DVMembership current = _membershipFrom(record);
    if (current.role == role) return current;
    if (current.role.isOwner && !role.isOwner) {
      await _requireAnotherOwner(organization.id, userId);
    }
    final DVRecord written = (await _memberships.write(
      <String, Object?>{...record.values, 'role': role.name},
      base: record,
      actor: actor,
      tenant: organization.tenant,
    )).record;
    return _membershipFrom(written);
  }

  Future<void> _requireAnotherOwner(
    String organizationId,
    String userId,
  ) async {
    final List<Map<String, Object?>> owners = await database.query(
      'SELECT user_id FROM dv_org_memberships WHERE organization_id = ? AND '
      'role = ?',
      <Object?>[organizationId, DVOrgRoles.ownerRole],
    );
    if (!owners.any((Map<String, Object?> row) => row['user_id'] != userId)) {
      throw DVLastOwner(organizationId, userId);
    }
  }

  Future<DVRecord> _memberRecord(String organizationId, String userId) async {
    final DVRecord? record = await _memberships.read(
      _membershipKey(organizationId, userId),
    );
    if (record == null) throw DVNotAMember(organizationId, userId);
    return record;
  }

  Future<DVOrganization?> _onTenant(String tenant) async {
    final List<Map<String, Object?>> rows = await database.query(
      'SELECT id FROM dv_organizations WHERE tenant = ?',
      <Object?>[tenant],
    );
    if (rows.isEmpty) return null;
    return find('${rows.first['id']}');
  }

  Future<DVRecord> _liveRecord(String id) async {
    final DVRecord? record = await _organizations.read(id);
    if (record == null) throw DVOrganizationNotFound(id);
    final DVOrganization organization = _organizationFrom(record);
    final DateTime? closedAt = organization.closedAt;
    if (closedAt != null) {
      throw DVOrganizationClosed(
        id,
        closedAt: closedAt,
        restorableUntil: closedAt.add(closeGrace),
      );
    }
    return record;
  }

  Future<DVOrganization> _live(String id) async =>
      _organizationFrom(await _liveRecord(id));

  /// [role] as this application declares it (`DV-ORG-001` when it does not).
  DVOrgRole _declared(DVOrgRole role) {
    final DVOrgRole declared = roles[role.name];
    if (declared != role) {
      throw ArgumentError.value(
        role,
        'role',
        'was declared among ${role.declaration}, not ${roles.names}',
      );
    }
    return declared;
  }

  Map<String, Object?> _membershipRow({
    required String organizationId,
    required String tenant,
    required String userId,
    required String? email,
    required DVOrgRole role,
    required DateTime at,
    String? invitedBy,
  }) => <String, Object?>{
    'id': _membershipKey(organizationId, userId),
    'organization_id': organizationId,
    'tenant': tenant,
    'user_id': userId,
    'email': email == null ? null : _normalizeEmail(email),
    'role': role.name,
    'joined_at': _stamp(at),
    'last_active_at': _stamp(at),
    'invited_by': invitedBy,
  };

  DVOrganization _organizationFrom(DVRecord record) => DVOrganization(
    id: '${record.values['id']}',
    name: '${record.values['name']}',
    tenant: '${record.values['tenant']}',
    createdAt: _date(record.values['created_at'])!,
    closedAt: _date(record.values['closed_at']),
  );

  DVMembership _membershipFrom(DVRecord record) => DVMembership(
    organizationId: '${record.values['organization_id']}',
    tenant: '${record.values['tenant']}',
    userId: '${record.values['user_id']}',
    email: record.values['email'] as String?,
    role: roles['${record.values['role']}'],
    joinedAt: _date(record.values['joined_at'])!,
    lastActiveAt: _date(record.values['last_active_at']),
    invitedBy: record.values['invited_by'] as String?,
  );

  DVInvitation _invitationFrom(DVRecord record) => DVInvitation(
    id: '${record.values['id']}',
    organizationId: '${record.values['organization_id']}',
    email: '${record.values['email']}',
    role: roles['${record.values['role']}'],
    invitedBy: '${record.values['invited_by']}',
    createdAt: _date(record.values['created_at'])!,
    expiresAt: _date(record.values['expires_at'])!,
  );

  static String _membershipKey(String organizationId, String userId) =>
      '$organizationId:$userId';

  static String _codeIdentifier(String organizationId, String address) =>
      'org-invitation-code:$organizationId:$address';

  static String _normalizeEmail(String email) => email.trim().toLowerCase();

  static String _normalizeDomain(String domain) {
    final String name = domain.trim().toLowerCase();
    return name.startsWith('@') ? name.substring(1) : name;
  }

  DateTime _now() => _clock().toUtc();

  static String _stamp(DateTime at) => at.toUtc().toIso8601String();

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.parse('$value');

  String _newId(String prefix) {
    final StringBuffer buffer = StringBuffer('${prefix}_');
    for (int i = 0; i < 16; i++) {
      buffer.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  /// One lock per organization per database, shared by every
  /// [DVOrganizations] on that database in this process.
  static final Expando<Map<String, Future<void>>> _locks =
      Expando<Map<String, Future<void>>>('dartvel organization locks');

  Future<T> _serially<T>(String key, Future<T> Function() body) async {
    final Map<String, Future<void>> locks = _locks[database] ??=
        <String, Future<void>>{};
    final Future<void> previous = locks[key] ?? Future<void>.value();
    final Completer<void> released = Completer<void>();
    locks[key] = released.future;
    await previous;
    try {
      return await body();
    } finally {
      locks.removeWhere(
        (String held, Future<void> lock) =>
            held == key && identical(lock, released.future),
      );
      released.complete();
    }
  }
}

/// A role name the application does not declare (`DV-ORG-001`).
class DVUndeclaredOrgRole implements Exception {
  const DVUndeclaredOrgRole(this.role, this.declared);

  final String role;
  final List<String> declared;

  String get code => 'DV-ORG-001';

  @override
  String toString() =>
      'DVUndeclaredOrgRole($code: "$role" is not one of $declared)';
}

/// An invitation to an address that is already a member (`DV-ORG-002`).
class DVAlreadyAMember implements Exception {
  const DVAlreadyAMember(this.organizationId, this.address);

  final String organizationId;
  final String address;

  String get code => 'DV-ORG-002';

  @override
  String toString() =>
      'DVAlreadyAMember($code: $address is already in $organizationId)';
}

/// The last owner leaving or being demoted without a successor
/// (`DV-ORG-003`).
class DVLastOwner implements Exception {
  const DVLastOwner(this.organizationId, this.userId);

  final String organizationId;
  final String userId;

  String get code => 'DV-ORG-003';

  @override
  String toString() =>
      'DVLastOwner($code: $userId is the last owner of '
      '$organizationId; transfer ownership first)';
}

/// Work against a closed organization, or a restore after its grace period
/// (`DV-ORG-004`).
class DVOrganizationClosed implements Exception {
  const DVOrganizationClosed(
    this.organizationId, {
    required this.closedAt,
    required this.restorableUntil,
    this.expired = false,
  });

  final String organizationId;
  final DateTime closedAt;
  final DateTime restorableUntil;

  /// Whether the grace period has passed, so it can no longer be restored.
  final bool expired;

  String get code => 'DV-ORG-004';

  @override
  String toString() =>
      'DVOrganizationClosed($code: $organizationId closed at '
      '$closedAt; ${expired ? 'no longer restorable' : 'restorable until $restorableUntil'})';
}

/// SSO auto-join from a domain that is not verified (`DV-ORG-005`).
class DVDomainNotVerified implements Exception {
  const DVDomainNotVerified(this.organizationId, this.domain);

  final String organizationId;
  final String domain;

  String get code => 'DV-ORG-005';

  @override
  String toString() =>
      'DVDomainNotVerified($code: $domain is not a verified '
      'domain of $organizationId)';
}

/// Membership asked of a tenant with no organization (`DV-ORG-006`).
class DVTenantHasNoOrganization implements Exception {
  const DVTenantHasNoOrganization(this.tenant);

  final String tenant;

  String get code => 'DV-ORG-006';

  @override
  String toString() =>
      'DVTenantHasNoOrganization($code: tenant $tenant has no organization)';
}

/// An acceptance past the organization's seat limit (`DV-METER-004`).
class DVSeatLimitReached implements Exception {
  const DVSeatLimitReached(
    this.organizationId, {
    required this.used,
    this.limit,
  });

  final String organizationId;
  final num used;
  final num? limit;

  String get code => 'DV-METER-004';

  @override
  String toString() =>
      'DVSeatLimitReached($code: $organizationId uses $used of $limit seats)';
}

/// An invitation that is unknown, spent, revoked or expired.
///
/// Deliberately one type, for the reason [DVAuthTokenResult.reveal] gives.
class DVInvitationInvalid implements Exception {
  const DVInvitationInvalid([
    this.reveal = 'That invitation is invalid or has expired.',
  ]);

  /// A message safe to show the person.
  final String reveal;

  @override
  String toString() => 'DVInvitationInvalid($reveal)';
}

/// An invitation redeemed by an address it was not sent to.
class DVInvitationEmailMismatch implements Exception {
  const DVInvitationEmailMismatch(this.invitationId);

  final String invitationId;

  @override
  String toString() =>
      'DVInvitationEmailMismatch(invitation $invitationId '
      'was sent to a different address)';
}

/// Someone acting on an organization they do not belong to.
class DVNotAMember implements Exception {
  const DVNotAMember(this.organizationId, this.userId);

  final String organizationId;
  final String userId;

  @override
  String toString() => 'DVNotAMember($userId is not in $organizationId)';
}

/// An invitation at a role above the inviter's own.
class DVOrgRoleEscalation implements Exception {
  const DVOrgRoleEscalation(
    this.organizationId,
    this.userId, {
    required this.held,
    required this.offered,
  });

  final String organizationId;
  final String userId;
  final DVOrgRole held;
  final DVOrgRole offered;

  @override
  String toString() =>
      'DVOrgRoleEscalation($userId holds ${held.name} in '
      '$organizationId and cannot invite at ${offered.name})';
}

/// A second organization on a tenant that already has one.
class DVTenantAlreadyOrganized implements Exception {
  const DVTenantAlreadyOrganized(this.tenant, this.organizationId);

  final String tenant;
  final String organizationId;

  @override
  String toString() =>
      'DVTenantAlreadyOrganized(tenant $tenant already holds '
      '$organizationId)';
}

class DVOrganizationNotFound implements Exception {
  const DVOrganizationNotFound(this.organizationId);

  final String organizationId;

  @override
  String toString() => 'DVOrganizationNotFound($organizationId)';
}
