// Organizations, memberships and invitations, against the adapters Dartvel
// runs on without a network: the in-memory adapter and SQLite.
//
// The failures worth the effort are the silent ones. A redeemed invitation
// that redeems again looks like a normal join. A role checked against the
// wrong organization grants access that nobody sees until an audit. An
// organization whose last owner demoted themselves still works, until
// somebody needs to pay the bill. Two acceptances racing for the last seat
// both succeed and nobody is refused. A forwarded link joins whoever clicked
// it. Each has a test below that fails if the guard is removed.
import 'dart:async';

import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

typedef _Adapter = (String name, DVDatabaseAdapter Function() create);

final List<_Adapter> _adapters = <_Adapter>[
  ('memory', MemoryDVDatabaseAdapter.new),
  ('sqlite', SqliteDVDatabaseAdapter.memory),
];

final Uri _acceptUrl = Uri.parse('https://app.example/invitations/accept');

void main() {
  group('DVOrgRole', () {
    test('orders by declaration, first declared highest', () {
      expect(DVOrgRole.owner > DVOrgRole.admin, isTrue);
      expect(DVOrgRole.admin >= DVOrgRole.admin, isTrue);
      expect(DVOrgRole.member >= DVOrgRole.admin, isFalse);
      expect(DVOrgRole.billing < DVOrgRole.member, isTrue);
    });

    test('an undeclared role is DV-ORG-001, not a silently low rank', () {
      const DVOrgRoles roles = DVOrgRoles.standard;
      expect(roles['admin'], DVOrgRole.admin);
      expect(
        () => roles['superadmin'],
        throwsA(
          isA<DVUndeclaredOrgRole>().having(
            (DVUndeclaredOrgRole e) => e.code,
            'code',
            'DV-ORG-001',
          ),
        ),
      );
    });

    test('a declaration must name an owner', () {
      expect(
        () => DVOrgRoles(const <String>['admin', 'member']),
        throwsArgumentError,
      );
    });

    test('roles from two declarations do not compare', () {
      final DVOrgRoles other = DVOrgRoles(const <String>['owner', 'editor']);
      expect(() => other['owner'] >= DVOrgRole.admin, throwsArgumentError);
    });
  });

  for (final (String name, DVDatabaseAdapter Function() create) in _adapters) {
    group('organizations on $name', () {
      late DateTime now;
      late DVOrganizations orgs;
      late DVOrganization acme;

      DVOrganizations build({
        FutureOr<int?> Function(String tenant)? seatLimit,
        DVSeats seats = DVSeats.everyMember,
        DVAuthTokens? tokens,
        DVDatabaseAdapter? database,
      }) => DVOrganizations(
        database: database ?? create(),
        tokens: tokens,
        seats: seats,
        seatLimit: seatLimit,
        clock: () => now,
      );

      setUp(() async {
        now = DateTime.utc(2026, 9, 13, 12);
        orgs = build();
        await orgs.ensureSchema();
        acme = await orgs.create(
          name: 'Acme',
          tenant: 'acme',
          ownerId: 'ada',
          ownerEmail: 'ada@acme.test',
        );
      });

      group('tenant and organization', () {
        test(
          'the creator is the owner, on the organization\'s one tenant',
          () async {
            final DVMembership? ada = await orgs.membership(acme.id, 'ada');
            expect(ada?.role, DVOrgRole.owner);
            expect(ada?.tenant, 'acme');
            expect((await orgs.forTenant('acme'))?.id, acme.id);
          },
        );

        test('a tenant holds at most one organization', () async {
          await expectLater(
            orgs.create(name: 'Acme two', tenant: 'acme', ownerId: 'bob'),
            throwsA(isA<DVTenantAlreadyOrganized>()),
          );
        });

        test('renaming keeps the tenant: the boundary does not move', () async {
          final DVOrganization renamed = await orgs.rename(
            acme.id,
            'Acme Inc',
            actor: 'ada',
          );
          expect(renamed.name, 'Acme Inc');
          expect(renamed.tenant, 'acme');
        });

        test(
          'a personal tenant becomes an organization without moving data',
          () async {
            final String personal = DVOrganizations.personalTenantFor('cy');
            expect(await orgs.forTenant(personal), isNull);
            final DVOrganization adopted = await orgs.create(
              name: 'Cy',
              tenant: personal,
              ownerId: 'cy',
            );
            expect(adopted.tenant, personal);
            expect(
              (await orgs.membership(adopted.id, 'cy'))?.role,
              DVOrgRole.owner,
            );
          },
        );

        test(
          'membership on a tenant with no organization is DV-ORG-006',
          () async {
            await expectLater(
              const DVTenants().withTenant(
                DVOrganizations.personalTenantFor('cy'),
                () => orgs.currentMembership('cy'),
              ),
              throwsA(
                isA<DVTenantHasNoOrganization>().having(
                  (DVTenantHasNoOrganization e) => e.code,
                  'code',
                  'DV-ORG-006',
                ),
              ),
            );
          },
        );

        test('current membership follows the current tenant', () async {
          final DVOrganization globex = await orgs.create(
            name: 'Globex',
            tenant: 'globex',
            ownerId: 'hank',
          );
          await orgs.addMember(
            globex.id,
            'ada',
            role: DVOrgRole.member,
            actor: 'hank',
          );
          final DVMembership? onAcme = await const DVTenants().withTenant(
            'acme',
            () => orgs.currentMembership('ada'),
          );
          final DVMembership? onGlobex = await const DVTenants().withTenant(
            'globex',
            () => orgs.currentMembership('ada'),
          );
          expect(onAcme?.role, DVOrgRole.owner);
          expect(onGlobex?.role, DVOrgRole.member);
        });
      });

      group('cross-organization roles', () {
        late DVOrganization globex;

        setUp(() async {
          globex = await orgs.create(
            name: 'Globex',
            tenant: 'globex',
            ownerId: 'hank',
          );
          await orgs.addMember(
            globex.id,
            'ada',
            role: DVOrgRole.member,
            actor: 'hank',
          );
        });

        test(
          'an owner of one organization is only a member of another',
          () async {
            expect(await orgs.hasRole(acme.id, 'ada', DVOrgRole.admin), isTrue);
            expect(
              await orgs.hasRole(globex.id, 'ada', DVOrgRole.admin),
              isFalse,
            );
          },
        );

        test(
          'a membership grants nothing on an organization it is not in',
          () async {
            final DVMembership ada = (await orgs.membership(acme.id, 'ada'))!;
            expect(ada.grants(acme, DVOrgRole.admin), isTrue);
            expect(ada.grants(globex, DVOrgRole.admin), isFalse);
          },
        );

        test('feeds DV.Auth.authorization policies', () async {
          const DVAuthAuthorization authorization = DVAuthAuthorization();
          authorization.register<DVMembership, DVOrganization>(
            'org.invite',
            (DVMembership m, DVOrganization org) =>
                m.grants(org, DVOrgRole.admin),
          );
          final DVMembership ada = (await orgs.membership(acme.id, 'ada'))!;
          expect(await authorization.can(ada, 'org.invite', acme), isTrue);
          expect(await authorization.can(ada, 'org.invite', globex), isFalse);
        });

        test(
          'an inviter must belong to the organization they invite to',
          () async {
            await expectLater(
              orgs.invite(
                acme.id,
                'eve@x.test',
                role: DVOrgRole.member,
                invitedBy: 'hank',
                acceptUrl: _acceptUrl,
              ),
              throwsA(isA<DVNotAMember>()),
            );
          },
        );

        test('an inviter cannot hand out a role above their own', () async {
          await expectLater(
            orgs.invite(
              globex.id,
              'eve@x.test',
              role: DVOrgRole.owner,
              invitedBy: 'ada',
              acceptUrl: _acceptUrl,
            ),
            throwsA(isA<DVOrgRoleEscalation>()),
          );
        });
      });

      group('invitations', () {
        test(
          'an emailed link joins at the invited role, recording the inviter',
          () async {
            final DVIssuedInvitation issued = await orgs.invite(
              acme.id,
              'Bob@Acme.test ',
              role: DVOrgRole.member,
              invitedBy: 'ada',
              acceptUrl: _acceptUrl,
            );
            expect(issued.link.url.queryParameters['token'], issued.link.token);
            final DVMembership bob = await orgs.accept(
              issued.link.token,
              userId: 'bob',
              email: 'bob@acme.test',
            );
            expect(bob.role, DVOrgRole.member);
            expect(bob.organizationId, acme.id);
            final List<DVHistoryEntry> history = await orgs.membershipHistory(
              acme.id,
              'bob',
            );
            expect(history.single.actor, 'ada');
            expect(await orgs.pendingInvitations(acme.id), isEmpty);
          },
        );

        test('the stored invitation holds no token', () async {
          final DVIssuedInvitation issued = await orgs.invite(
            acme.id,
            'bob@acme.test',
            role: DVOrgRole.member,
            invitedBy: 'ada',
            acceptUrl: _acceptUrl,
          );
          final List<Map<String, Object?>> rows = await orgs.database.query(
            'SELECT * FROM dv_org_invitations',
          );
          expect(rows, hasLength(1));
          expect(
            rows.single.values.map((Object? v) => '$v').join('|'),
            isNot(contains(issued.link.token)),
          );
        });

        test('a redeemed invitation cannot be redeemed again', () async {
          final DVIssuedInvitation issued = await orgs.invite(
            acme.id,
            'bob@acme.test',
            role: DVOrgRole.member,
            invitedBy: 'ada',
            acceptUrl: _acceptUrl,
          );
          await orgs.accept(
            issued.link.token,
            userId: 'bob',
            email: 'bob@acme.test',
          );
          await orgs.remove(acme.id, 'bob', actor: 'ada');
          await expectLater(
            orgs.accept(
              issued.link.token,
              userId: 'bob',
              email: 'bob@acme.test',
            ),
            throwsA(isA<DVInvitationInvalid>()),
          );
          expect(await orgs.membership(acme.id, 'bob'), isNull);
        });

        test('an invitation past its lifetime is refused', () async {
          final DVIssuedInvitation issued = await orgs.invite(
            acme.id,
            'bob@acme.test',
            role: DVOrgRole.member,
            invitedBy: 'ada',
            acceptUrl: _acceptUrl,
          );
          now = now.add(
            DVOrganizations.defaultInvitationLifetime +
                const Duration(minutes: 1),
          );
          await expectLater(
            orgs.accept(
              issued.link.token,
              userId: 'bob',
              email: 'bob@acme.test',
            ),
            throwsA(isA<DVInvitationInvalid>()),
          );
          expect(await orgs.membership(acme.id, 'bob'), isNull);
        });

        test('a token the token store has expired is refused', () async {
          final DVOrganizations expiring = build(
            tokens: DVAuthTokens(lifetime: const Duration(seconds: -1)),
            database: orgs.database,
          );
          final DVIssuedInvitation issued = await expiring.invite(
            acme.id,
            'bob@acme.test',
            role: DVOrgRole.member,
            invitedBy: 'ada',
            acceptUrl: _acceptUrl,
          );
          await expectLater(
            expiring.accept(
              issued.link.token,
              userId: 'bob',
              email: 'bob@acme.test',
            ),
            throwsA(isA<DVInvitationInvalid>()),
          );
        });

        test('a revoked invitation is refused', () async {
          final DVIssuedInvitation issued = await orgs.invite(
            acme.id,
            'bob@acme.test',
            role: DVOrgRole.member,
            invitedBy: 'ada',
            acceptUrl: _acceptUrl,
          );
          await orgs.revokeInvitation(issued.invitation.id, actor: 'ada');
          await expectLater(
            orgs.accept(
              issued.link.token,
              userId: 'bob',
              email: 'bob@acme.test',
            ),
            throwsA(isA<DVInvitationInvalid>()),
          );
        });

        test('a forwarded link does not join someone else', () async {
          final DVIssuedInvitation issued = await orgs.invite(
            acme.id,
            'bob@acme.test',
            role: DVOrgRole.admin,
            invitedBy: 'ada',
            acceptUrl: _acceptUrl,
          );
          await expectLater(
            orgs.accept(
              issued.link.token,
              userId: 'mallory',
              email: 'mallory@evil.test',
            ),
            throwsA(isA<DVInvitationEmailMismatch>()),
          );
          expect(await orgs.membership(acme.id, 'mallory'), isNull);
          // The link is spent, but the invitation is still there to resend.
          expect(await orgs.pendingInvitations(acme.id), hasLength(1));
        });

        test(
          'a spent link stays spent while its invitation is pending',
          () async {
            final DVIssuedInvitation issued = await orgs.invite(
              acme.id,
              'bob@acme.test',
              role: DVOrgRole.member,
              invitedBy: 'ada',
              acceptUrl: _acceptUrl,
            );
            await expectLater(
              orgs.accept(
                issued.link.token,
                userId: 'mallory',
                email: 'mallory@evil.test',
              ),
              throwsA(isA<DVInvitationEmailMismatch>()),
            );
            // Only the token store stands between this replay and a join: the
            // invitation row is still there.
            await expectLater(
              orgs.accept(
                issued.link.token,
                userId: 'bob',
                email: 'bob@acme.test',
              ),
              throwsA(isA<DVInvitationInvalid>()),
            );
            expect(await orgs.membership(acme.id, 'bob'), isNull);
          },
        );

        test('a code joins only the address it was sent to', () async {
          final String code = await orgs.inviteByCode(
            acme.id,
            'bob@acme.test',
            role: DVOrgRole.member,
            invitedBy: 'ada',
          );
          await expectLater(
            orgs.acceptCode(
              acme.id,
              code,
              userId: 'mallory',
              email: 'mallory@evil.test',
            ),
            throwsA(isA<DVInvitationInvalid>()),
          );
          final DVMembership bob = await orgs.acceptCode(
            acme.id,
            code,
            userId: 'bob',
            email: 'bob@acme.test',
          );
          expect(bob.role, DVOrgRole.member);
        });

        test('inviting an existing member is DV-ORG-002', () async {
          await expectLater(
            orgs.invite(
              acme.id,
              'ADA@acme.test',
              role: DVOrgRole.member,
              invitedBy: 'ada',
              acceptUrl: _acceptUrl,
            ),
            throwsA(
              isA<DVAlreadyAMember>().having(
                (DVAlreadyAMember e) => e.code,
                'code',
                'DV-ORG-002',
              ),
            ),
          );
        });
      });

      group('seats', () {
        test('a query over memberships, not a counter', () async {
          await orgs.addMember(
            acme.id,
            'bob',
            role: DVOrgRole.member,
            actor: 'ada',
          );
          expect(await orgs.seatsUsed(acme.id), 2);
          await orgs.remove(acme.id, 'bob', actor: 'ada');
          expect(await orgs.seatsUsed(acme.id), 1);
        });

        test('counts what is declared: a role', () async {
          final DVOrganizations billed = build(
            seats: DVSeats.atRoles(<DVOrgRole>{
              DVOrgRole.owner,
              DVOrgRole.admin,
            }),
            database: orgs.database,
          );
          await billed.addMember(
            acme.id,
            'bob',
            role: DVOrgRole.member,
            actor: 'ada',
          );
          await billed.addMember(
            acme.id,
            'cy',
            role: DVOrgRole.admin,
            actor: 'ada',
          );
          expect(await billed.seatsUsed(acme.id), 2);
        });

        test('counts what is declared: signed in this period', () async {
          final DVOrganizations active = build(
            seats: const DVSeats.activeWithin(Duration(days: 30)),
            database: orgs.database,
          );
          await active.addMember(
            acme.id,
            'bob',
            role: DVOrgRole.member,
            actor: 'ada',
          );
          now = now.add(const Duration(days: 40));
          await active.recordActivity(acme.id, 'bob');
          expect(await active.seatsUsed(acme.id), 1);
        });

        test('a full organization refuses the next acceptance', () async {
          final DVOrganizations limited = build(
            seatLimit: (String _) => 2,
            database: orgs.database,
          );
          await limited.addMember(
            acme.id,
            'bob',
            role: DVOrgRole.member,
            actor: 'ada',
          );
          final DVIssuedInvitation issued = await limited.invite(
            acme.id,
            'cy@acme.test',
            role: DVOrgRole.member,
            invitedBy: 'ada',
            acceptUrl: _acceptUrl,
          );
          await expectLater(
            limited.accept(
              issued.link.token,
              userId: 'cy',
              email: 'cy@acme.test',
            ),
            throwsA(
              isA<DVSeatLimitReached>().having(
                (DVSeatLimitReached e) => e.code,
                'code',
                'DV-METER-004',
              ),
            ),
          );
          expect(await limited.membership(acme.id, 'cy'), isNull);
        });

        test('concurrent acceptances cannot overrun the seats', () async {
          final DVOrganizations limited = build(
            seatLimit: (String _) => 3,
            database: orgs.database,
          );
          final List<DVIssuedInvitation> issued = <DVIssuedInvitation>[
            for (int i = 0; i < 5; i++)
              await limited.invite(
                acme.id,
                'u$i@acme.test',
                role: DVOrgRole.member,
                invitedBy: 'ada',
                acceptUrl: _acceptUrl,
              ),
          ];
          final List<Object> outcomes = await Future.wait(<Future<Object>>[
            for (int i = 0; i < 5; i++)
              limited
                  .accept(
                    issued[i].link.token,
                    userId: 'u$i',
                    email: 'u$i@acme.test',
                  )
                  .then<Object>(
                    (DVMembership m) => m,
                    onError: (Object e) => e,
                  ),
          ]);
          expect(outcomes.whereType<DVMembership>(), hasLength(2));
          expect(outcomes.whereType<DVSeatLimitReached>(), hasLength(3));
          expect(await limited.seatsUsed(acme.id), 3);
        });

        test('the limit is a DV.Meter level limit', () async {
          final DVOrganizations limited = build(
            seatLimit: (String _) => 5,
            database: orgs.database,
          );
          final DVMeters meters = DVMeters(store: DVMemoryMeterStore());
          final DVMeterOutcome outcome = await const DVTenants().withTenant(
            'acme',
            () => meters.admitLevel(limited.seatLevel),
          );
          expect(outcome.total, 1);
          expect(outcome.limit, 5);
          expect(outcome.admitted, isTrue);
        });
      });

      group('owners', () {
        test('the last owner cannot be demoted: DV-ORG-003', () async {
          await expectLater(
            orgs.changeRole(acme.id, 'ada', DVOrgRole.admin, actor: 'ada'),
            throwsA(
              isA<DVLastOwner>().having(
                (DVLastOwner e) => e.code,
                'code',
                'DV-ORG-003',
              ),
            ),
          );
          expect(
            (await orgs.membership(acme.id, 'ada'))?.role,
            DVOrgRole.owner,
          );
        });

        test('the last owner cannot leave', () async {
          await expectLater(
            orgs.remove(acme.id, 'ada', actor: 'ada'),
            throwsA(isA<DVLastOwner>()),
          );
          expect(await orgs.membership(acme.id, 'ada'), isNotNull);
        });

        test(
          'two owners demoting each other at once leave one owner',
          () async {
            await orgs.addMember(
              acme.id,
              'bob',
              role: DVOrgRole.owner,
              actor: 'ada',
            );
            final List<Object?> outcomes = await Future.wait(<Future<Object?>>[
              orgs
                  .changeRole(acme.id, 'ada', DVOrgRole.admin, actor: 'bob')
                  .then<Object?>((_) => null, onError: (Object e) => e),
              orgs
                  .changeRole(acme.id, 'bob', DVOrgRole.admin, actor: 'ada')
                  .then<Object?>((_) => null, onError: (Object e) => e),
            ]);
            expect(outcomes.whereType<DVLastOwner>(), hasLength(1));
            final List<DVMembership> owners = (await orgs.members(
              acme.id,
            )).where((DVMembership m) => m.role == DVOrgRole.owner).toList();
            expect(owners, hasLength(1));
          },
        );

        test('transfer moves ownership and records who did it', () async {
          await orgs.addMember(
            acme.id,
            'bob',
            role: DVOrgRole.member,
            actor: 'ada',
          );
          await orgs.transferOwnership(
            acme.id,
            from: 'ada',
            to: 'bob',
            actor: 'ada',
          );
          expect(
            (await orgs.membership(acme.id, 'bob'))?.role,
            DVOrgRole.owner,
          );
          expect(
            (await orgs.membership(acme.id, 'ada'))?.role,
            DVOrgRole.admin,
          );
          final List<DVHistoryEntry> history = await orgs.membershipHistory(
            acme.id,
            'bob',
          );
          expect(history.last.actor, 'ada');
          expect(history.last.transactionId, isNotNull);
        });

        test(
          'transfer to a non-member is refused and changes nothing',
          () async {
            await expectLater(
              orgs.transferOwnership(
                acme.id,
                from: 'ada',
                to: 'zed',
                actor: 'ada',
              ),
              throwsA(isA<DVNotAMember>()),
            );
            expect(
              (await orgs.membership(acme.id, 'ada'))?.role,
              DVOrgRole.owner,
            );
          },
        );

        test('transfer rolls back with the transaction it ran in', () async {
          await orgs.addMember(
            acme.id,
            'bob',
            role: DVOrgRole.member,
            actor: 'ada',
          );
          await expectLater(
            DVTransactionRunner()<void>((DVContext context) async {
              await orgs.transferOwnership(
                acme.id,
                from: 'ada',
                to: 'bob',
                actor: 'ada',
              );
              throw StateError('payment provider refused');
            }),
            throwsStateError,
          );
          expect(
            (await orgs.membership(acme.id, 'ada'))?.role,
            DVOrgRole.owner,
          );
          expect(
            (await orgs.membership(acme.id, 'bob'))?.role,
            DVOrgRole.member,
          );
        });
      });

      group('closing', () {
        test('a closed organization refuses work with DV-ORG-004', () async {
          await orgs.close(acme.id, actor: 'ada');
          await expectLater(
            orgs.invite(
              acme.id,
              'bob@acme.test',
              role: DVOrgRole.member,
              invitedBy: 'ada',
              acceptUrl: _acceptUrl,
            ),
            throwsA(
              isA<DVOrganizationClosed>().having(
                (DVOrganizationClosed e) => e.code,
                'code',
                'DV-ORG-004',
              ),
            ),
          );
          expect(await orgs.forTenant('acme'), isNull);
        });

        test('an invitation issued before closing is refused after', () async {
          final DVIssuedInvitation issued = await orgs.invite(
            acme.id,
            'bob@acme.test',
            role: DVOrgRole.member,
            invitedBy: 'ada',
            acceptUrl: _acceptUrl,
          );
          await orgs.close(acme.id, actor: 'ada');
          await expectLater(
            orgs.accept(
              issued.link.token,
              userId: 'bob',
              email: 'bob@acme.test',
            ),
            throwsA(isA<DVOrganizationClosed>()),
          );
        });

        test('restorable within the grace period, with its members', () async {
          await orgs.close(acme.id, actor: 'ada');
          now = now.add(const Duration(days: 29));
          final DVOrganization restored = await orgs.restore(
            acme.id,
            actor: 'ada',
          );
          expect(restored.closedAt, isNull);
          expect(
            (await orgs.membership(acme.id, 'ada'))?.role,
            DVOrgRole.owner,
          );
        });

        test('not restorable after the grace period', () async {
          await orgs.close(acme.id, actor: 'ada');
          now = now.add(const Duration(days: 31));
          await expectLater(
            orgs.restore(acme.id, actor: 'ada'),
            throwsA(isA<DVOrganizationClosed>()),
          );
        });

        test('closing rolls back with the transaction it ran in', () async {
          await expectLater(
            DVTransactionRunner()<void>((DVContext context) async {
              await orgs.close(acme.id, actor: 'ada');
              throw StateError('export failed');
            }),
            throwsStateError,
          );
          expect((await orgs.forTenant('acme'))?.id, acme.id);
        });
      });

      group('SSO domain auto-join', () {
        test('a verified domain joins at its declared role', () async {
          await orgs.addDomain(
            acme.id,
            'acme.test',
            role: DVOrgRole.member,
            actor: 'ada',
          );
          await orgs.markDomainVerified(acme.id, 'acme.test', actor: 'ada');
          final DVMembership dee = await orgs.joinByDomain(
            acme.id,
            userId: 'dee',
            email: 'dee@ACME.test',
          );
          expect(dee.role, DVOrgRole.member);
        });

        test('an unverified domain is DV-ORG-005', () async {
          await orgs.addDomain(
            acme.id,
            'acme.test',
            role: DVOrgRole.admin,
            actor: 'ada',
          );
          await expectLater(
            orgs.joinByDomain(acme.id, userId: 'dee', email: 'dee@acme.test'),
            throwsA(
              isA<DVDomainNotVerified>().having(
                (DVDomainNotVerified e) => e.code,
                'code',
                'DV-ORG-005',
              ),
            ),
          );
          expect(await orgs.membership(acme.id, 'dee'), isNull);
        });

        test('a lookalike subdomain does not match', () async {
          await orgs.addDomain(
            acme.id,
            'acme.test',
            role: DVOrgRole.member,
            actor: 'ada',
          );
          await orgs.markDomainVerified(acme.id, 'acme.test', actor: 'ada');
          await expectLater(
            orgs.joinByDomain(
              acme.id,
              userId: 'mallory',
              email: 'mallory@evilacme.test',
            ),
            throwsA(isA<DVDomainNotVerified>()),
          );
        });
      });
    });
  }
}
